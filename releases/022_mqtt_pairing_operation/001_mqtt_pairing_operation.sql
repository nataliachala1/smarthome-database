-- HU16/HU11: durable *reservation* for an MQTT credential bootstrap before
-- devices.device exists. No plaintext or hashed MQTT/Wi-Fi passwords.
-- This changeset deliberately DOES NOT provision credentials, transition
-- the pairing session to CONNECTED, or relax mqtt_identity uniqueness.

-- Only a dedicated NOLOGIN purpose role may reserve an unbound MQTT identity.
-- The pre-existing registrar role also has fn_register_mqtt_identity permission
-- and must NOT be used by this reservation-only connector.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles
                 WHERE rolname = 'smarthome_mqtt_reserver') THEN
    CREATE ROLE smarthome_mqtt_reserver NOLOGIN NOSUPERUSER NOCREATEDB
      NOCREATEROLE NOREPLICATION NOBYPASSRLS;
  END IF;
END;
$$;
GRANT USAGE ON SCHEMA devices TO smarthome_mqtt_reserver;

CREATE TABLE devices.mqtt_pairing_operation (
  id_mqtt_pairing_operation UUID NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
  id_device_pairing_session UUID NOT NULL UNIQUE
    REFERENCES devices.device_pairing_session(id_device_pairing_session) ON DELETE RESTRICT,
  id_mqtt_identity UUID NOT NULL UNIQUE,
  manufacturer_device_id VARCHAR(100) NOT NULL,
  topic_scope VARCHAR(256) NOT NULL,
  broker_username VARCHAR(128) NOT NULL UNIQUE,
  broker_client_id VARCHAR(128) NOT NULL UNIQUE,
  broker_role_name VARCHAR(128) NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'RESERVED',
  id_device UUID UNIQUE REFERENCES devices.device(id_device) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  authenticated_at TIMESTAMPTZ,
  revocation_requested_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  retry_at TIMESTAMPTZ,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  lease_token UUID,
  lease_until TIMESTAMPTZ,
  last_error_code VARCHAR(64),
  CONSTRAINT ck_mqtt_pairing_manufacturer CHECK (
    manufacturer_device_id ~ '^[a-z0-9][a-z0-9_-]{0,99}$'
  ),
  CONSTRAINT ck_mqtt_pairing_topic_scope CHECK (
    topic_scope ~ '^[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*$'
    AND (topic_scope = manufacturer_device_id OR
      right(topic_scope, length('/devices/' || manufacturer_device_id)) =
        '/devices/' || manufacturer_device_id)
  ),
  CONSTRAINT ck_mqtt_pairing_names CHECK (
    broker_username ~ '^[A-Za-z0-9_-]{1,128}$'
    AND broker_client_id ~ '^[A-Za-z0-9_-]{1,128}$'
    AND broker_role_name ~ '^[A-Za-z0-9_-]{1,128}$'
  ),
  CONSTRAINT ck_mqtt_pairing_status CHECK (status IN (
    'RESERVED', 'PREPARING', 'PREPARED_DISABLED',
    'ENABLE_PENDING', 'ENABLING', 'AWAITING_AUTH',
    'AUTH_VERIFIED', 'ATTACHED', 'REVOKE_PENDING', 'REVOKING',
    'REVOKED', 'RECONCILIATION_REQUIRED'
  )),
  CONSTRAINT ck_mqtt_pairing_verified CHECK (
    status NOT IN ('AUTH_VERIFIED', 'ATTACHED') OR authenticated_at IS NOT NULL
  ),
  CONSTRAINT ck_mqtt_pairing_attached CHECK (
    status <> 'ATTACHED' OR id_device IS NOT NULL
  ),
  CONSTRAINT ck_mqtt_pairing_revoked CHECK (
    (status = 'REVOKED' AND revoked_at IS NOT NULL)
    OR (status <> 'REVOKED' AND revoked_at IS NULL)
  ),
  CONSTRAINT ck_mqtt_pairing_attempt CHECK (attempt_count >= 0),
  CONSTRAINT ck_mqtt_pairing_lease CHECK (
    (lease_token IS NULL AND lease_until IS NULL)
    OR (lease_token IS NOT NULL AND lease_until IS NOT NULL AND
      status IN ('PREPARING', 'ENABLING', 'REVOKING'))
  ),
  CONSTRAINT ck_mqtt_pairing_error CHECK (
    last_error_code IS NULL OR last_error_code IN (
      'MQTT_ADMIN_UNAVAILABLE', 'MQTT_ADMIN_REJECTED',
      'MQTT_ADMIN_OUTCOME_UNKNOWN', 'MQTT_ADMIN_INVALID_RESPONSE',
      'MQTT_ADMIN_UNSAFE_DEFAULT_ACL', 'MQTT_REVOCATION_UNEXPECTED',
      'MQTT_PROVISIONING_UNEXPECTED', 'MQTT_BROKER_AUTH_UNVERIFIED',
      'MQTT_IDENTITY_RECONCILIATION_REQUIRED'
    )
  )
);

-- Intentionally fail closed: an uncertain/abandoned operation continues to
-- reserve the physical ID until a trusted cleanup verifies broker revocation.
CREATE UNIQUE INDEX uq_mqtt_pairing_one_unrevoked_manufacturer
  ON devices.mqtt_pairing_operation(lower(manufacturer_device_id))
  WHERE status <> 'REVOKED';
CREATE INDEX idx_mqtt_pairing_recovery
  ON devices.mqtt_pairing_operation(retry_at, id_mqtt_pairing_operation)
  WHERE status IN ('PREPARING', 'ENABLE_PENDING', 'ENABLING',
    'REVOKE_PENDING', 'REVOKING', 'RECONCILIATION_REQUIRED');

ALTER TABLE devices.mqtt_pairing_operation ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE devices.mqtt_pairing_operation
  FROM PUBLIC, smarthome_runtime_app, smarthome_worker, smarthome_ingest,
       smarthome_readonly, smarthome_admin,
       smarthome_mqtt_registrar, smarthome_mqtt_revoke,
       smarthome_mqtt_reserver;

COMMENT ON TABLE devices.mqtt_pairing_operation IS
  'Privileged pre-registration MQTT provisioning reservation. No MQTT/Wi-Fi secrets and no untrusted transition to broker-authenticated. A non-REVOKED row blocks re-pairing.';
COMMENT ON COLUMN devices.mqtt_pairing_operation.authenticated_at IS
  'Reserved for a future trusted broker-observed session-bound proof; must not be set from device/mobile self-reports.';

-- Prevent changes to the stable broker binding, even through future privileged
-- state transitions. All actual state transitions remain unimplemented here.
CREATE FUNCTION devices.fn_guard_mqtt_pairing_operation_binding()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF NEW.id_mqtt_pairing_operation IS DISTINCT FROM OLD.id_mqtt_pairing_operation
    OR NEW.id_device_pairing_session IS DISTINCT FROM OLD.id_device_pairing_session
    OR NEW.id_mqtt_identity IS DISTINCT FROM OLD.id_mqtt_identity
    OR NEW.manufacturer_device_id IS DISTINCT FROM OLD.manufacturer_device_id
    OR NEW.topic_scope IS DISTINCT FROM OLD.topic_scope
    OR NEW.broker_username IS DISTINCT FROM OLD.broker_username
    OR NEW.broker_client_id IS DISTINCT FROM OLD.broker_client_id
    OR NEW.broker_role_name IS DISTINCT FROM OLD.broker_role_name
    OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'MQTT_PAIRING_BINDING_IMMUTABLE';
  END IF;
  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_guard_mqtt_pairing_operation_binding() FROM PUBLIC;
CREATE TRIGGER trg_guard_mqtt_pairing_operation_binding
  BEFORE UPDATE ON devices.mqtt_pairing_operation
  FOR EACH ROW EXECUTE FUNCTION devices.fn_guard_mqtt_pairing_operation_binding();

-- A trusted registrar may *reserve* a broker identity for an existing,
-- authorized, non-expired pairing session. It cannot enable it or mark it
-- authenticated. The human OWNER authorization is still enforced by the
-- current active OWNER and the session token hash. Orchestration must
-- recheck OWNER authorization before and after this transaction.
CREATE FUNCTION devices.fn_reserve_mqtt_pairing_operation(
  p_session UUID,
  p_topic_scope TEXT,
  p_actor UUID,
  p_token_hash TEXT
)
RETURNS TABLE (
  operation_id UUID, identity_id UUID, username TEXT,
  client_id TEXT, role_name TEXT, reserved_topic_scope TEXT
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_session devices.device_pairing_session%ROWTYPE;
  v_existing devices.mqtt_pairing_operation%ROWTYPE;
  v_operation UUID;
  v_identity UUID;
  v_suffix TEXT;
  v_manufacturer TEXT;
BEGIN
  SELECT * INTO v_session FROM devices.device_pairing_session
    WHERE id_device_pairing_session = p_session FOR UPDATE;
  IF NOT FOUND
    OR p_actor IS NULL
    OR v_session.id_user IS DISTINCT FROM p_actor
    OR p_token_hash IS NULL
    OR p_token_hash !~ '^[0-9a-f]{64}$'
    OR v_session.token_hash::text IS DISTINCT FROM p_token_hash
    OR NOT EXISTS (
      SELECT 1 FROM auth."user" u
      JOIN homes.home_member hm ON hm.id_user = u.id_user
      WHERE u.id_user = p_actor AND u.status = 'ACTIVE'
        AND hm.id_home = v_session.id_home
        AND hm.role = 'OWNER' AND hm.status = 'ACTIVE'
    )
    OR v_session.status NOT IN ('DEVICE_IDENTIFIED', 'WAITING_FOR_MQTT')
    OR v_session.expires_at <= clock_timestamp()
    OR v_session.model_code IS DISTINCT FROM 'S4SW-001P16EU'
    OR v_session.manufacturer_device_id IS NULL
    OR NOT EXISTS (
      SELECT 1 FROM homes.home h
      WHERE h.id_home = v_session.id_home
        AND h.status = 'ACTIVE' AND h.deleted_at IS NULL
    ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'MQTT_PAIRING_SESSION_NOT_RESERVABLE';
  END IF;

  v_manufacturer := lower(v_session.manufacturer_device_id);
  IF v_manufacturer !~ '^[a-z0-9][a-z0-9_-]{0,99}$'
    OR p_topic_scope IS NULL
    OR length(p_topic_scope) > 256
    OR p_topic_scope !~ '^[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*$'
    OR NOT (
      p_topic_scope = v_manufacturer OR
      right(p_topic_scope, length('/devices/' || v_manufacturer)) =
        '/devices/' || v_manufacturer
    ) THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'MQTT_PAIRING_TOPIC_SCOPE_INVALID';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_manufacturer, 0));

  SELECT * INTO v_existing FROM devices.mqtt_pairing_operation
    WHERE id_device_pairing_session = p_session FOR UPDATE;
  IF FOUND THEN
    IF v_existing.status <> 'RESERVED'
      OR v_existing.topic_scope <> p_topic_scope
      OR v_existing.manufacturer_device_id <> v_manufacturer THEN
      RAISE EXCEPTION USING ERRCODE = '23514',
        MESSAGE = 'MQTT_PAIRING_OPERATION_REUSE_DENIED';
    END IF;
    RETURN QUERY SELECT v_existing.id_mqtt_pairing_operation,
      v_existing.id_mqtt_identity, v_existing.broker_username::text,
      v_existing.broker_client_id::text,
      v_existing.broker_role_name::text, v_existing.topic_scope::text;
    RETURN;
  END IF;

  -- A live device, an unrevoked MQTT binding or a preexisting unknown
  -- legacy binding prevents unsafe adoption to a new home.
  IF EXISTS (
    SELECT 1 FROM devices.device d
    WHERE lower(d.manufacturer_device_id) = v_manufacturer
      AND d.deleted_at IS NULL
  ) OR EXISTS (
    SELECT 1 FROM devices.mqtt_identity i
    WHERE lower(i.manufacturer_device_id) = v_manufacturer
      AND i.state <> 'REVOKED'
  ) OR EXISTS (
    SELECT 1 FROM devices.device d
    WHERE lower(d.manufacturer_device_id) = v_manufacturer
      AND d.deleted_at IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM devices.mqtt_identity i
        WHERE i.id_device = d.id_device AND i.state = 'REVOKED'
      )
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'MQTT_PAIRING_PREVIOUS_IDENTITY_NOT_REVOKED';
  END IF;

  v_operation := gen_random_uuid();
  v_identity := gen_random_uuid();
  v_suffix := replace(v_identity::text, '-', '');
  INSERT INTO devices.mqtt_pairing_operation (
    id_mqtt_pairing_operation, id_device_pairing_session, id_mqtt_identity,
    manufacturer_device_id, topic_scope,
    broker_username, broker_client_id, broker_role_name
  ) VALUES (
    v_operation, p_session, v_identity, v_manufacturer, p_topic_scope,
    'shd_' || v_suffix, 'shd-' || v_suffix, 'role_shd_' || v_suffix
  );

  RETURN QUERY SELECT v_operation, v_identity,
    ('shd_' || v_suffix)::text, ('shd-' || v_suffix)::text,
    ('role_shd_' || v_suffix)::text, p_topic_scope::text;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_reserve_mqtt_pairing_operation(UUID, TEXT, UUID, TEXT)
  FROM PUBLIC, smarthome_mqtt_registrar;
GRANT EXECUTE ON FUNCTION devices.fn_reserve_mqtt_pairing_operation(UUID, TEXT, UUID, TEXT)
  TO smarthome_mqtt_reserver;

COMMENT ON FUNCTION devices.fn_reserve_mqtt_pairing_operation(UUID, TEXT, UUID, TEXT) IS
  'Privileged reservation requires current ACTIVE OWNER and matching session token proof. Refuses unknown legacy broker credentials and unrevoked prior identities. No password storage or broker action.';
