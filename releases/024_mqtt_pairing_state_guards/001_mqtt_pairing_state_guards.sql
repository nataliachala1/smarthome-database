-- HU16/HU11 / 024: structural state-machine guard and append-only audit.
-- Requires 022 (hardened reservation) and 023. This changeset provides
-- NO new role grants, broker verification, credentials or worker actions.
-- A transition allowed by this trigger is NOT evidence of a broker outcome.

DO $$
BEGIN
  IF to_regclass('devices.mqtt_pairing_operation') IS NULL
     OR to_regclass('devices.mqtt_identity') IS NULL
     OR to_regclass('devices.mqtt_pairing_state_event') IS NOT NULL
     OR to_regprocedure('devices.fn_reserve_mqtt_pairing_operation(uuid,text,uuid,text)') IS NULL
  THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'MQTT_024_PREREQUISITES_NOT_MET';
  END IF;

  -- We cannot fabricate the earlier transition history. Stop if a worker
  -- somehow reached an advanced state before audit was installed.
  IF EXISTS (
    SELECT 1 FROM devices.mqtt_pairing_operation WHERE status <> 'RESERVED'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'MQTT_024_EXISTING_UNAUDITED_TRANSITIONS';
  END IF;
END;
$$;

CREATE TABLE devices.mqtt_pairing_state_event (
  id_event BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_mqtt_pairing_operation UUID NOT NULL
    REFERENCES devices.mqtt_pairing_operation(id_mqtt_pairing_operation)
    ON DELETE RESTRICT,
  from_status TEXT,
  to_status TEXT NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  transaction_id BIGINT NOT NULL DEFAULT txid_current(),
  CONSTRAINT ck_mqtt_pairing_state_event_initial CHECK (
    from_status IS NOT NULL OR to_status = 'RESERVED'
  )
);
CREATE INDEX idx_mqtt_pairing_state_event_operation
  ON devices.mqtt_pairing_state_event(id_mqtt_pairing_operation, id_event);

ALTER TABLE devices.mqtt_pairing_state_event ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE devices.mqtt_pairing_state_event
  FROM PUBLIC, smarthome_runtime_app, smarthome_worker, smarthome_ingest,
       smarthome_readonly, smarthome_admin, smarthome_mqtt_registrar,
       smarthome_mqtt_revoke, smarthome_mqtt_reserver;

COMMENT ON TABLE devices.mqtt_pairing_state_event IS
  'Internal append-only state audit, not a broker proof. No DML or SELECT to runtime roles. Historical data must not be erased on rollback.';

CREATE FUNCTION devices.fn_guard_mqtt_pairing_state_event()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '23514',
    MESSAGE = 'MQTT_PAIRING_STATE_AUDIT_IMMUTABLE';
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_guard_mqtt_pairing_state_event() FROM PUBLIC;
CREATE TRIGGER trg_guard_mqtt_pairing_state_event
  BEFORE UPDATE OR DELETE ON devices.mqtt_pairing_state_event
  FOR EACH ROW EXECUTE FUNCTION devices.fn_guard_mqtt_pairing_state_event();

-- A fixed allow-list matching mqtt-pairing-state.policy.ts. The check is
-- structural; a future SECURITY DEFINER function MUST verify broker facts
-- and compare lease tokens before issuing any positive transition.
CREATE FUNCTION devices.fn_guard_mqtt_pairing_operation_state()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_now TIMESTAMPTZ := clock_timestamp();
  v_lease_entry BOOLEAN;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'RESERVED'
       OR NEW.id_device IS NOT NULL
       OR NEW.authenticated_at IS NOT NULL
       OR NEW.revocation_requested_at IS NOT NULL
       OR NEW.revoked_at IS NOT NULL
       OR NEW.lease_token IS NOT NULL
       OR NEW.lease_until IS NOT NULL
       OR NEW.attempt_count <> 0 THEN
      RAISE EXCEPTION USING ERRCODE = '23514',
        MESSAGE = 'MQTT_PAIRING_INSERT_MUST_BE_RESERVED';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status = 'REVOKED' THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'MQTT_PAIRING_REVOKED_TERMINAL';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status AND NOT EXISTS (
    SELECT 1 FROM (VALUES
      ('RESERVED', 'PREPARING'),
      ('PREPARING', 'PREPARED_DISABLED'),
      ('PREPARED_DISABLED', 'ENABLE_PENDING'),
      ('ENABLE_PENDING', 'ENABLING'),
      ('ENABLING', 'AWAITING_AUTH'),
      ('AWAITING_AUTH', 'AUTH_VERIFIED'),
      ('AUTH_VERIFIED', 'ATTACHED'),
      ('RESERVED', 'REVOKE_PENDING'),
      ('PREPARING', 'REVOKE_PENDING'),
      ('PREPARED_DISABLED', 'REVOKE_PENDING'),
      ('ENABLE_PENDING', 'REVOKE_PENDING'),
      ('ENABLING', 'REVOKE_PENDING'),
      ('AWAITING_AUTH', 'REVOKE_PENDING'),
      ('AUTH_VERIFIED', 'REVOKE_PENDING'),
      ('ATTACHED', 'REVOKE_PENDING'),
      ('REVOKE_PENDING', 'REVOKING'),
      ('REVOKING', 'REVOKED'),
      ('PREPARING', 'RECONCILIATION_REQUIRED'),
      ('ENABLING', 'RECONCILIATION_REQUIRED'),
      ('REVOKING', 'RECONCILIATION_REQUIRED'),
      ('RECONCILIATION_REQUIRED', 'REVOKE_PENDING')
    ) AS rule(from_status, to_status)
    WHERE rule.from_status = OLD.status AND rule.to_status = NEW.status
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'MQTT_PAIRING_INVALID_STATE_TRANSITION';
  END IF;

  v_lease_entry := NEW.status IN ('PREPARING', 'ENABLING', 'REVOKING')
                   AND NEW.status IS DISTINCT FROM OLD.status;

  -- Leased states must have a live lease. Outside those states, clear it.
  IF NEW.status IN ('PREPARING', 'ENABLING', 'REVOKING') THEN
    IF NEW.lease_token IS NULL OR NEW.lease_until IS NULL
       OR NEW.lease_until <= v_now THEN
      RAISE EXCEPTION USING ERRCODE = '23514',
        MESSAGE = 'MQTT_PAIRING_LEASE_REQUIRED';
    END IF;
    IF v_lease_entry AND (
      NEW.lease_token IS NOT DISTINCT FROM OLD.lease_token
      OR NEW.attempt_count <> OLD.attempt_count + 1
    ) THEN
      RAISE EXCEPTION USING ERRCODE = '23514',
        MESSAGE = 'MQTT_PAIRING_LEASE_CLAIM_INVALID';
    END IF;
    IF NOT v_lease_entry AND NEW.lease_token IS DISTINCT FROM OLD.lease_token
       AND (OLD.lease_until IS NULL OR OLD.lease_until > v_now
            OR NEW.attempt_count <> OLD.attempt_count + 1) THEN
      RAISE EXCEPTION USING ERRCODE = '23514',
        MESSAGE = 'MQTT_PAIRING_LEASE_RECLAIM_INVALID';
    END IF;
  ELSIF NEW.lease_token IS NOT NULL OR NEW.lease_until IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'MQTT_PAIRING_LEASE_MUST_BE_CLEARED';
  END IF;

  IF NEW.attempt_count < OLD.attempt_count THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'MQTT_PAIRING_ATTEMPT_COUNTER_NONMONOTONIC';
  END IF;

  -- Timestamp existence is NOT a broker authentication proof. Future
  -- privileged functions must independently authenticate the broker event.
  IF NEW.authenticated_at IS DISTINCT FROM OLD.authenticated_at AND NOT (
    OLD.status = 'AWAITING_AUTH' AND NEW.status = 'AUTH_VERIFIED'
    AND OLD.authenticated_at IS NULL
    AND NEW.authenticated_at IS NOT NULL
    AND NEW.authenticated_at >= OLD.created_at
    AND NEW.authenticated_at <= v_now + INTERVAL '30 seconds'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'MQTT_PAIRING_AUTH_TIME_IMMUTABLE';
  END IF;

  IF NEW.status = 'AUTH_VERIFIED' AND NEW.authenticated_at IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'MQTT_PAIRING_AUTH_TIME_REQUIRED';
  END IF;

  -- Only the atomic attach step can bind a device. Do not rebind histories.
  IF NEW.id_device IS DISTINCT FROM OLD.id_device AND NOT (
    OLD.status = 'AUTH_VERIFIED' AND NEW.status = 'ATTACHED'
    AND OLD.id_device IS NULL AND NEW.id_device IS NOT NULL
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'MQTT_PAIRING_DEVICE_BINDING_IMMUTABLE';
  END IF;

  IF NEW.status = 'ATTACHED' AND OLD.status IS DISTINCT FROM 'ATTACHED' AND NOT EXISTS (
    SELECT 1 FROM devices.mqtt_identity i
    JOIN devices.device d ON d.id_device = i.id_device
    JOIN devices.device_pairing_session ps
      ON ps.id_device_pairing_session = NEW.id_device_pairing_session
    WHERE i.id_mqtt_identity = NEW.id_mqtt_identity
      AND i.id_device = NEW.id_device
      AND i.state = 'REGISTERED'
      AND lower(i.manufacturer_device_id) = NEW.manufacturer_device_id
      AND lower(d.manufacturer_device_id) = NEW.manufacturer_device_id
      AND d.id_home = ps.id_home
      AND d.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'MQTT_PAIRING_ATTACHED_IDENTITY_MISMATCH';
  END IF;

  IF NEW.revocation_requested_at IS DISTINCT FROM OLD.revocation_requested_at AND NOT (
    NEW.status = 'REVOKE_PENDING'
    AND OLD.status IS DISTINCT FROM 'REVOKE_PENDING'
    AND OLD.revocation_requested_at IS NULL
    AND NEW.revocation_requested_at IS NOT NULL
    AND NEW.revocation_requested_at >= OLD.created_at
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'MQTT_PAIRING_REVOCATION_REQUEST_TIME_IMMUTABLE';
  END IF;

  IF NEW.status = 'REVOKE_PENDING' AND NEW.revocation_requested_at IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'MQTT_PAIRING_REVOCATION_REQUEST_TIME_REQUIRED';
  END IF;

  IF NEW.revoked_at IS DISTINCT FROM OLD.revoked_at AND NOT (
    OLD.status = 'REVOKING' AND NEW.status = 'REVOKED'
    AND OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL
    AND NEW.revocation_requested_at IS NOT NULL
    AND NEW.revoked_at >= NEW.revocation_requested_at
    AND NEW.revoked_at <= v_now + INTERVAL '30 seconds'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'MQTT_PAIRING_REVOKED_TIME_IMMUTABLE';
  END IF;

  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_guard_mqtt_pairing_operation_state() FROM PUBLIC;

CREATE TRIGGER trg_guard_mqtt_pairing_operation_state
  BEFORE INSERT OR UPDATE ON devices.mqtt_pairing_operation
  FOR EACH ROW EXECUTE FUNCTION devices.fn_guard_mqtt_pairing_operation_state();

-- Writes happen in the same transaction as the state update; a rollback
-- reverses both the state and audit entry, avoiding phantom transitions.
CREATE FUNCTION devices.fn_audit_mqtt_pairing_operation_state()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO devices.mqtt_pairing_state_event
      (id_mqtt_pairing_operation, from_status, to_status, occurred_at)
    VALUES (NEW.id_mqtt_pairing_operation, NULL, NEW.status, NEW.created_at);
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO devices.mqtt_pairing_state_event
      (id_mqtt_pairing_operation, from_status, to_status)
    VALUES (NEW.id_mqtt_pairing_operation, OLD.status, NEW.status);
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_audit_mqtt_pairing_operation_state() FROM PUBLIC;

-- Preserve an audit of existing RESERVED reservations from before 024.
INSERT INTO devices.mqtt_pairing_state_event
  (id_mqtt_pairing_operation, from_status, to_status, occurred_at)
SELECT id_mqtt_pairing_operation, NULL, 'RESERVED', created_at
FROM devices.mqtt_pairing_operation;

CREATE TRIGGER trg_audit_mqtt_pairing_operation_state
  AFTER INSERT OR UPDATE ON devices.mqtt_pairing_operation
  FOR EACH ROW EXECUTE FUNCTION devices.fn_audit_mqtt_pairing_operation_state();
