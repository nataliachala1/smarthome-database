-- Technical history of committed HU11 identity transitions. No arbitrary JSON,
-- credential, lease token or claimed human actor is recorded here.
-- Lock before snapshot/trigger installation so concurrent writers cannot fall
-- into a gap between the snapshot and capture. Liquibase runs this atomically.
SET LOCAL lock_timeout = '5s';
LOCK TABLE devices.mqtt_identity IN SHARE ROW EXCLUSIVE MODE;

CREATE TABLE devices.mqtt_identity_event (
  id_mqtt_identity_event BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_mqtt_identity UUID NOT NULL REFERENCES devices.mqtt_identity(id_mqtt_identity) ON DELETE RESTRICT,
  event_type TEXT NOT NULL,
  previous_state TEXT,
  state TEXT NOT NULL,
  attempt_count INTEGER NOT NULL CHECK (attempt_count >= 0),
  error_code TEXT,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT ck_mqtt_event_states CHECK (
    state IN ('REGISTERED', 'REVOKE_PENDING', 'REVOKED')
    AND (previous_state IS NULL OR previous_state IN ('REGISTERED', 'REVOKE_PENDING', 'REVOKED'))
  ),
  CONSTRAINT ck_mqtt_event_error CHECK (error_code IN (
    'MQTT_ADMIN_UNAVAILABLE', 'MQTT_ADMIN_REJECTED', 'MQTT_ADMIN_OUTCOME_UNKNOWN',
    'MQTT_ADMIN_INVALID_RESPONSE', 'MQTT_ADMIN_UNSAFE_DEFAULT_ACL', 'MQTT_REVOCATION_UNEXPECTED'
  )),
  CONSTRAINT ck_mqtt_event_transition CHECK (COALESCE(
    (event_type = 'BASELINE_SNAPSHOT' AND previous_state IS NULL)
    OR (event_type = 'REGISTERED' AND previous_state IS NULL AND state = 'REGISTERED' AND attempt_count = 0 AND error_code IS NULL)
    OR (event_type = 'REVOKE_REQUESTED' AND previous_state = 'REGISTERED' AND state = 'REVOKE_PENDING' AND attempt_count = 0 AND error_code IS NULL)
    OR (event_type = 'ATTEMPT_STARTED' AND previous_state = 'REVOKE_PENDING' AND state = 'REVOKE_PENDING' AND attempt_count > 0 AND error_code IS NULL)
    OR (event_type = 'RETRY_SCHEDULED' AND previous_state = 'REVOKE_PENDING' AND state = 'REVOKE_PENDING' AND attempt_count > 0 AND error_code IS NOT NULL)
    OR (event_type = 'REVOKED' AND previous_state = 'REVOKE_PENDING' AND state = 'REVOKED' AND attempt_count > 0 AND error_code IS NULL)
  , false))
);
CREATE INDEX idx_mqtt_identity_event_history
  ON devices.mqtt_identity_event(id_mqtt_identity, id_mqtt_identity_event);
ALTER TABLE devices.mqtt_identity_event ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON devices.mqtt_identity_event FROM PUBLIC, smarthome_runtime_app, smarthome_ingest,
  smarthome_worker, smarthome_readonly, smarthome_admin, smarthome_mqtt_registrar, smarthome_mqtt_revoke;
REVOKE ALL ON SEQUENCE devices.mqtt_identity_event_id_mqtt_identity_event_seq
  FROM PUBLIC, smarthome_runtime_app, smarthome_ingest, smarthome_worker, smarthome_readonly,
  smarthome_admin, smarthome_mqtt_registrar, smarthome_mqtt_revoke;
COMMENT ON TABLE devices.mqtt_identity_event IS
  'HU11 append-only technical transition history, not a broker log or proof of physical state. BASELINE_SNAPSHOT observes migration-time state only.';

-- Do not invent past events for identities that predate this migration.
INSERT INTO devices.mqtt_identity_event(id_mqtt_identity, event_type, state, attempt_count, error_code)
  SELECT id_mqtt_identity, 'BASELINE_SNAPSHOT', state, attempt_count, last_error_code
  FROM devices.mqtt_identity ORDER BY id_mqtt_identity;

CREATE FUNCTION devices.fn_capture_mqtt_identity_event()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_event TEXT;
  v_previous TEXT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_event := 'REGISTERED';
  ELSE
    v_previous := OLD.state;
    IF OLD.state = 'REGISTERED' AND NEW.state = 'REVOKE_PENDING' THEN
      v_event := 'REVOKE_REQUESTED';
    ELSIF OLD.state = 'REVOKE_PENDING' AND NEW.state = 'REVOKED' THEN
      v_event := 'REVOKED';
    ELSIF NEW.state = 'REVOKE_PENDING' AND NEW.lease_token IS NOT NULL
      AND NEW.lease_token IS DISTINCT FROM OLD.lease_token THEN
      -- A fresh lease distinguishes attempts even if attempt_count saturates.
      v_event := 'ATTEMPT_STARTED';
    ELSIF OLD.state = 'REVOKE_PENDING' AND NEW.state = 'REVOKE_PENDING'
      AND OLD.lease_token IS NOT NULL AND NEW.lease_token IS NULL
      AND NEW.last_error_code IS NOT NULL THEN
      v_event := 'RETRY_SCHEDULED';
    ELSE
      RETURN NULL;
    END IF;
  END IF;
  INSERT INTO devices.mqtt_identity_event
    (id_mqtt_identity, event_type, previous_state, state, attempt_count, error_code)
  VALUES (NEW.id_mqtt_identity, v_event, v_previous, NEW.state, NEW.attempt_count,
    CASE WHEN v_event = 'RETRY_SCHEDULED' THEN NEW.last_error_code ELSE NULL END);
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_capture_mqtt_identity_event() FROM PUBLIC,
  smarthome_runtime_app, smarthome_ingest, smarthome_worker, smarthome_readonly,
  smarthome_admin, smarthome_mqtt_registrar, smarthome_mqtt_revoke;
CREATE TRIGGER trg_mqtt_identity_event
  AFTER INSERT OR UPDATE ON devices.mqtt_identity
  FOR EACH ROW EXECUTE FUNCTION devices.fn_capture_mqtt_identity_event();

CREATE FUNCTION devices.fn_mqtt_identity_event_append_only()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'MQTT_IDENTITY_HISTORY_APPEND_ONLY';
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_mqtt_identity_event_append_only() FROM PUBLIC,
  smarthome_runtime_app, smarthome_ingest, smarthome_worker, smarthome_readonly,
  smarthome_admin, smarthome_mqtt_registrar, smarthome_mqtt_revoke;
CREATE TRIGGER trg_mqtt_identity_event_append_only
  BEFORE UPDATE OR DELETE OR TRUNCATE ON devices.mqtt_identity_event
  FOR EACH STATEMENT EXECUTE FUNCTION devices.fn_mqtt_identity_event_append_only();
