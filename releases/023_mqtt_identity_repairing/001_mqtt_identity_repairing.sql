-- HU11/HU16: allow a physical Shelly to acquire a NEW MQTT identity only
-- after the prior identity has reached REVOKED. Retain the previous row,
-- its device FK and the append-only mqtt_identity_event history.
-- No stored credentials; this changeset never contacts the MQTT broker.
-- IMPORTANT: REVOKED must only be reported after verified broker revocation.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'devices.mqtt_identity'::regclass
      AND conname = 'mqtt_identity_manufacturer_device_id_key'
      AND contype = 'u'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'MQTT_IDENTITY_EXPECTED_GLOBAL_UNIQUE_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM devices.mqtt_identity
    WHERE state IN ('REGISTERED', 'REVOKE_PENDING')
    GROUP BY lower(manufacturer_device_id)
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23505',
      MESSAGE = 'MQTT_IDENTITY_DUPLICATE_UNREVOKED_MANUFACTURER';
  END IF;
END;
$$;

-- Build the replacement BEFORE dropping the original UNIQUE constraint.
-- This operation runs in a Liquibase transaction; CREATE INDEX (without
-- CONCURRENTLY) blocks concurrent writes until the transaction completes.
CREATE UNIQUE INDEX uq_mqtt_identity_unrevoked_manufacturer_ci
  ON devices.mqtt_identity (lower(manufacturer_device_id))
  WHERE state IN ('REGISTERED', 'REVOKE_PENDING');

ALTER TABLE devices.mqtt_identity
  DROP CONSTRAINT mqtt_identity_manufacturer_device_id_key;

COMMENT ON INDEX devices.uq_mqtt_identity_unrevoked_manufacturer_ci IS
  'Case-insensitive exclusivity for non-revoked MQTT identities. REVOKED rows retain immutable audit/device history and may coexist with a NEW registered identity.';

-- Keep the recorded binding immutable and make REVOKED terminal.
-- Existing revoke trigger/function transitions remain valid:
-- REGISTERED -> REVOKE_PENDING -> REVOKED; retries do not change state.
CREATE FUNCTION devices.fn_guard_mqtt_identity_repairing()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF NEW.id_mqtt_identity IS DISTINCT FROM OLD.id_mqtt_identity
     OR NEW.id_device IS DISTINCT FROM OLD.id_device
     OR NEW.manufacturer_device_id IS DISTINCT FROM OLD.manufacturer_device_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'MQTT_IDENTITY_BINDING_IMMUTABLE';
  END IF;

  IF NEW.state IS DISTINCT FROM OLD.state AND NOT (
    (OLD.state = 'REGISTERED' AND NEW.state = 'REVOKE_PENDING')
    OR (OLD.state = 'REVOKE_PENDING' AND NEW.state = 'REVOKED')
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'MQTT_IDENTITY_INVALID_STATE_TRANSITION';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_guard_mqtt_identity_repairing() FROM PUBLIC;

CREATE TRIGGER trg_guard_mqtt_identity_repairing
  BEFORE UPDATE ON devices.mqtt_identity
  FOR EACH ROW EXECUTE FUNCTION devices.fn_guard_mqtt_identity_repairing();
