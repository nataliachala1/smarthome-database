-- Internal metadata for ALREADY provisioned identities. No bootstrap endpoint,
-- credential storage, automatic adoption or grant to the normal API/ingester.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'smarthome_mqtt_registrar') THEN
    CREATE ROLE smarthome_mqtt_registrar NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'smarthome_mqtt_revoke') THEN
    CREATE ROLE smarthome_mqtt_revoke NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
  END IF;
END;
$$;

CREATE TABLE devices.mqtt_identity (
  id_mqtt_identity UUID PRIMARY KEY,
  id_device UUID NOT NULL UNIQUE REFERENCES devices.device(id_device) ON DELETE RESTRICT,
  manufacturer_device_id VARCHAR(100) NOT NULL UNIQUE,
  state TEXT NOT NULL DEFAULT 'REGISTERED',
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  revoke_requested_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  retry_at TIMESTAMPTZ,
  lease_token UUID,
  lease_until TIMESTAMPTZ,
  last_error_code TEXT,
  CONSTRAINT ck_mqtt_identity_uuid CHECK (
    id_mqtt_identity::text ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  ),
  CONSTRAINT ck_mqtt_identity_manufacturer CHECK (
    manufacturer_device_id <> '' AND manufacturer_device_id !~ '[^A-Za-z0-9_-]'
  ),
  CONSTRAINT ck_mqtt_identity_state CHECK (
    (state = 'REGISTERED' AND revoke_requested_at IS NULL AND revoked_at IS NULL AND retry_at IS NULL)
    OR (state = 'REVOKE_PENDING' AND revoke_requested_at IS NOT NULL AND revoked_at IS NULL AND retry_at IS NOT NULL)
    OR (state = 'REVOKED' AND revoke_requested_at IS NOT NULL AND revoked_at IS NOT NULL AND retry_at IS NULL)
  ),
  CONSTRAINT ck_mqtt_identity_lease CHECK (
    (lease_token IS NULL AND lease_until IS NULL)
    OR (state = 'REVOKE_PENDING' AND lease_token IS NOT NULL AND lease_until IS NOT NULL)
  ),
  CONSTRAINT ck_mqtt_identity_error CHECK (last_error_code IN (
    'MQTT_ADMIN_UNAVAILABLE', 'MQTT_ADMIN_REJECTED', 'MQTT_ADMIN_OUTCOME_UNKNOWN',
    'MQTT_ADMIN_INVALID_RESPONSE', 'MQTT_ADMIN_UNSAFE_DEFAULT_ACL', 'MQTT_REVOCATION_UNEXPECTED'
  ))
);
CREATE INDEX idx_mqtt_identity_pending ON devices.mqtt_identity(retry_at, id_mqtt_identity)
  WHERE state = 'REVOKE_PENDING';
ALTER TABLE devices.mqtt_identity ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON devices.mqtt_identity FROM PUBLIC, smarthome_runtime_app, smarthome_ingest,
  smarthome_worker, smarthome_readonly, smarthome_admin, smarthome_mqtt_registrar, smarthome_mqtt_revoke;
COMMENT ON TABLE devices.mqtt_identity IS
  'HU11 internal broker identity reference and durable revocation; no passwords or verifiers. REGISTERED does not prove possession.';

-- The caller must have verified the broker binding. This function is not an
-- authorization/possession check and must never be exposed directly to a client.
-- Lock the same device row as DELETE's logical UPDATE to serialize registration.
CREATE FUNCTION devices.fn_register_mqtt_identity(p_device UUID, p_identity UUID, p_manufacturer TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_device devices.device%ROWTYPE;
  v_existing devices.mqtt_identity%ROWTYPE;
BEGIN
  SELECT * INTO v_device FROM devices.device WHERE id_device = p_device FOR UPDATE;
  IF NOT FOUND OR v_device.deleted_at IS NOT NULL OR v_device.status <> 'ACTIVE'
    OR v_device.messaging_protocol IS DISTINCT FROM 'MQTT'
    OR p_manufacturer IS NULL OR v_device.manufacturer_device_id IS DISTINCT FROM p_manufacturer
    OR NOT EXISTS (SELECT 1 FROM homes.home h WHERE h.id_home = v_device.id_home AND h.status = 'ACTIVE' AND h.deleted_at IS NULL)
  THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'MQTT_IDENTITY_DEVICE_UNAVAILABLE';
  END IF;
  SELECT * INTO v_existing FROM devices.mqtt_identity WHERE id_device = p_device;
  IF FOUND THEN
    IF v_existing.state <> 'REGISTERED' THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'MQTT_IDENTITY_REVOCATION_TERMINAL';
    END IF;
    IF v_existing.id_mqtt_identity = p_identity AND v_existing.manufacturer_device_id = p_manufacturer THEN
      RETURN v_existing.id_mqtt_identity;
    END IF;
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'MQTT_IDENTITY_BINDING_CONFLICT';
  END IF;
  INSERT INTO devices.mqtt_identity(id_mqtt_identity, id_device, manufacturer_device_id)
    VALUES (p_identity, p_device, p_manufacturer);
  RETURN p_identity;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_register_mqtt_identity(UUID, UUID, TEXT) FROM PUBLIC;

-- Runs inside the existing device UPDATE transaction; rollback rolls back both.
-- No network calls. Repeated updates never reset an in-flight lease or retry.
CREATE FUNCTION devices.fn_mqtt_identity_device_update()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF (NEW.id_home IS DISTINCT FROM OLD.id_home
      OR NEW.manufacturer_device_id IS DISTINCT FROM OLD.manufacturer_device_id)
    AND EXISTS (SELECT 1 FROM devices.mqtt_identity WHERE id_device = OLD.id_device)
  THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'MQTT_IDENTITY_BINDING_IMMUTABLE';
  END IF;
  IF NEW.deleted_at IS NOT NULL THEN
    UPDATE devices.mqtt_identity SET state = 'REVOKE_PENDING',
      revoke_requested_at = clock_timestamp(), retry_at = clock_timestamp()
      WHERE id_device = OLD.id_device AND state = 'REGISTERED';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_mqtt_identity_device_update() FROM PUBLIC;
CREATE TRIGGER trg_device_mqtt_revocation
  BEFORE UPDATE OF deleted_at, id_home, manufacturer_device_id ON devices.device
  FOR EACH ROW EXECUTE FUNCTION devices.fn_mqtt_identity_device_update();

-- Claim one job, committing BEFORE contacting the broker. Fixed 60 s lease.
-- A crashed worker is recoverable; the new random token fences old completions.
CREATE FUNCTION devices.fn_claim_mqtt_revocation()
RETURNS TABLE(identity_id UUID, claim_token UUID, attempt INTEGER)
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  WITH candidate AS (
    SELECT id_mqtt_identity FROM devices.mqtt_identity
    WHERE state = 'REVOKE_PENDING' AND retry_at <= clock_timestamp()
      AND (lease_until IS NULL OR lease_until <= clock_timestamp())
    ORDER BY retry_at, id_mqtt_identity
    LIMIT 1 FOR UPDATE SKIP LOCKED
  )
  UPDATE devices.mqtt_identity i SET lease_token = gen_random_uuid(),
    lease_until = clock_timestamp() + INTERVAL '60 seconds',
    attempt_count = LEAST(i.attempt_count::bigint + 1, 2147483647)::integer
  FROM candidate c WHERE i.id_mqtt_identity = c.id_mqtt_identity
  RETURNING i.id_mqtt_identity, i.lease_token, i.attempt_count;
$$;
REVOKE ALL ON FUNCTION devices.fn_claim_mqtt_revocation() FROM PUBLIC;

-- NULL error means a correlated successful disableClient response was received.
-- Unknown/failed outcomes stay pending; only fixed codes, never broker payloads.
CREATE FUNCTION devices.fn_finish_mqtt_revocation(p_identity UUID, p_token UUID, p_error TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE v_count INTEGER;
BEGIN
  IF p_error IS NOT NULL AND p_error NOT IN (
    'MQTT_ADMIN_UNAVAILABLE', 'MQTT_ADMIN_REJECTED', 'MQTT_ADMIN_OUTCOME_UNKNOWN',
    'MQTT_ADMIN_INVALID_RESPONSE', 'MQTT_ADMIN_UNSAFE_DEFAULT_ACL', 'MQTT_REVOCATION_UNEXPECTED'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'MQTT_REVOCATION_INVALID_ERROR_CODE';
  END IF;
  UPDATE devices.mqtt_identity SET
    state = CASE WHEN p_error IS NULL THEN 'REVOKED' ELSE 'REVOKE_PENDING' END,
    revoked_at = CASE WHEN p_error IS NULL THEN clock_timestamp() ELSE NULL END,
    retry_at = CASE WHEN p_error IS NULL THEN NULL ELSE clock_timestamp()
      + make_interval(secs => LEAST(300, 5 * power(2, LEAST(attempt_count - 1, 6)))::integer) END,
    lease_token = NULL, lease_until = NULL, last_error_code = p_error
  WHERE id_mqtt_identity = p_identity AND state = 'REVOKE_PENDING'
    AND lease_token = p_token AND lease_until > clock_timestamp();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count = 1;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_finish_mqtt_revocation(UUID, UUID, TEXT) FROM PUBLIC;

GRANT USAGE ON SCHEMA devices TO smarthome_mqtt_registrar, smarthome_mqtt_revoke;
GRANT EXECUTE ON FUNCTION devices.fn_register_mqtt_identity(UUID, UUID, TEXT) TO smarthome_mqtt_registrar;
GRANT EXECUTE ON FUNCTION devices.fn_claim_mqtt_revocation(),
  devices.fn_finish_mqtt_revocation(UUID, UUID, TEXT) TO smarthome_mqtt_revoke;
