-- HU16 / 026: durable single-use Shelly RPC challenge; NO broker proof or success transitions.
-- Requirements: hardened 022, 023, 024, 025. Roles have no table DML.
-- RPC id is a public correlation value, never a credential or possession proof.

DO $$
BEGIN
  IF to_regclass('devices.mqtt_pairing_operation') IS NULL
     OR to_regclass('devices.mqtt_pairing_state_event') IS NULL
     OR to_regprocedure('devices.fn_claim_mqtt_pairing_preparation(uuid,integer)') IS NULL
     OR to_regclass('devices.mqtt_rpc_challenge') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_roles WHERE rolname='smarthome_mqtt_rpc_worker')
  THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='MQTT_026_PREREQUISITES_NOT_MET';
  END IF;
END;
$$;

CREATE ROLE smarthome_mqtt_rpc_worker NOLOGIN NOINHERIT
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT USAGE ON SCHEMA devices TO smarthome_mqtt_rpc_worker;

CREATE TABLE devices.mqtt_rpc_challenge (
  rpc_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  id_mqtt_pairing_operation UUID NOT NULL
    REFERENCES devices.mqtt_pairing_operation(id_mqtt_pairing_operation) ON DELETE RESTRICT,
  challenge_index SMALLINT NOT NULL,
  issued_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  invalidated_at TIMESTAMPTZ,
  CONSTRAINT ck_mqtt_rpc_attempt CHECK (challenge_index BETWEEN 1 AND 5),
  CONSTRAINT uq_mqtt_rpc_attempt UNIQUE (id_mqtt_pairing_operation, challenge_index),
  CONSTRAINT ck_mqtt_rpc_window CHECK (expires_at = issued_at + INTERVAL '15 seconds'),
  CONSTRAINT ck_mqtt_rpc_outcome CHECK (NOT (consumed_at IS NOT NULL AND invalidated_at IS NOT NULL)),
  CONSTRAINT ck_mqtt_rpc_consumed_time CHECK (consumed_at IS NULL OR consumed_at >= issued_at),
  CONSTRAINT ck_mqtt_rpc_invalidated_time CHECK (invalidated_at IS NULL OR invalidated_at >= issued_at)
);
CREATE INDEX idx_mqtt_rpc_challenge_operation
  ON devices.mqtt_rpc_challenge(id_mqtt_pairing_operation, issued_at DESC);
CREATE UNIQUE INDEX uq_mqtt_rpc_one_pending_per_operation
  ON devices.mqtt_rpc_challenge(id_mqtt_pairing_operation)
  WHERE consumed_at IS NULL AND invalidated_at IS NULL;

ALTER TABLE devices.mqtt_rpc_challenge ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON devices.mqtt_rpc_challenge FROM PUBLIC,
  smarthome_runtime_app, smarthome_worker, smarthome_ingest, smarthome_readonly,
  smarthome_admin, smarthome_mqtt_registrar, smarthome_mqtt_revoke,
  smarthome_mqtt_reserver, smarthome_mqtt_lease_worker, smarthome_mqtt_rpc_worker;
COMMENT ON TABLE devices.mqtt_rpc_challenge IS
  'Append-only RPC correlation lifecycle. No secrets or broker proof, no success state transition. Only an authorized dedicated worker can issue/consume candidates.';

CREATE FUNCTION devices.fn_guard_mqtt_rpc_challenge()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_now TIMESTAMPTZ := clock_timestamp();
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_RPC_CHALLENGE_HISTORY_IMMUTABLE';
  END IF;
  IF NEW.rpc_id IS DISTINCT FROM OLD.rpc_id
     OR NEW.id_mqtt_pairing_operation IS DISTINCT FROM OLD.id_mqtt_pairing_operation
     OR NEW.challenge_index IS DISTINCT FROM OLD.challenge_index
     OR NEW.issued_at IS DISTINCT FROM OLD.issued_at
     OR NEW.expires_at IS DISTINCT FROM OLD.expires_at
     OR OLD.consumed_at IS NOT NULL OR OLD.invalidated_at IS NOT NULL
     OR NOT (
       (NEW.consumed_at IS NOT NULL AND NEW.invalidated_at IS NULL
         AND NEW.consumed_at >= OLD.issued_at AND NEW.consumed_at <= v_now + INTERVAL '1 second')
       OR
       (NEW.invalidated_at IS NOT NULL AND NEW.consumed_at IS NULL
         AND NEW.invalidated_at >= OLD.issued_at AND NEW.invalidated_at <= v_now + INTERVAL '1 second')
     )
  THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_RPC_CHALLENGE_HISTORY_IMMUTABLE';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_guard_mqtt_rpc_challenge() FROM PUBLIC;
CREATE TRIGGER trg_guard_mqtt_rpc_challenge
  BEFORE UPDATE OR DELETE ON devices.mqtt_rpc_challenge
  FOR EACH ROW EXECUTE FUNCTION devices.fn_guard_mqtt_rpc_challenge();

-- Idempotent issuance during the 15s window, serialized per pairing operation.
-- Replaces expired pending challenges without deleting historical rows.
-- Maximum five challenge issuances per pairing operation; exhaustion is fail-closed.
CREATE FUNCTION devices.fn_issue_mqtt_rpc_challenge(p_operation UUID)
RETURNS TABLE (
  rpc_id UUID, manufacturer_device_id TEXT,
  request_topic TEXT, response_topic TEXT, request_source TEXT,
  issued_at TIMESTAMPTZ, expires_at TIMESTAMPTZ,
  broker_username TEXT, broker_client_id TEXT, broker_role_name TEXT
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE
  v_op devices.mqtt_pairing_operation%ROWTYPE;
  v_existing devices.mqtt_rpc_challenge%ROWTYPE;
  v_id UUID;
  v_seq SMALLINT;
  v_now TIMESTAMPTZ;
BEGIN
  IF p_operation IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MQTT_RPC_OPERATION_REQUIRED';
  END IF;

  SELECT * INTO v_op FROM devices.mqtt_pairing_operation o
    WHERE o.id_mqtt_pairing_operation=p_operation FOR UPDATE;
  v_now := clock_timestamp();
  IF NOT FOUND OR v_op.status <> 'AWAITING_AUTH'
     OR v_op.authenticated_at IS NOT NULL OR v_op.id_device IS NOT NULL
     OR NOT EXISTS (
       SELECT 1 FROM devices.device_pairing_session ps
       JOIN auth."user" u ON u.id_user=ps.id_user AND u.status='ACTIVE'
       JOIN homes.home h ON h.id_home=ps.id_home
         AND h.status='ACTIVE' AND h.deleted_at IS NULL
       JOIN homes.home_member hm ON hm.id_home=ps.id_home
         AND hm.id_user=ps.id_user AND hm.role='OWNER' AND hm.status='ACTIVE'
       WHERE ps.id_device_pairing_session=v_op.id_device_pairing_session
         AND ps.status='WAITING_FOR_MQTT' AND ps.expires_at > v_now
         AND ps.model_code='S4SW-001P16EU'
         AND lower(ps.manufacturer_device_id)=v_op.manufacturer_device_id
     )
  THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MQTT_RPC_OPERATION_NOT_AWAITING_AUTH';
  END IF;

  SELECT * INTO v_existing FROM devices.mqtt_rpc_challenge c
    WHERE c.id_mqtt_pairing_operation=p_operation
      AND c.consumed_at IS NULL AND c.invalidated_at IS NULL
    FOR UPDATE;
  IF FOUND AND v_existing.expires_at > v_now THEN
    v_id := v_existing.rpc_id;
    RETURN QUERY SELECT v_id,v_op.manufacturer_device_id::text,
      (v_op.topic_scope||'/rpc')::text,
      (v_op.topic_scope||'/events/rpc')::text,
      (v_op.topic_scope||'/events')::text,
      v_existing.issued_at,v_existing.expires_at,
      v_op.broker_username::text,v_op.broker_client_id::text,
      v_op.broker_role_name::text;
    RETURN;
  END IF;
  IF FOUND THEN
    UPDATE devices.mqtt_rpc_challenge c SET invalidated_at=v_now
    WHERE c.rpc_id=v_existing.rpc_id
      AND c.consumed_at IS NULL AND c.invalidated_at IS NULL;
  END IF;

  SELECT COALESCE(max(c.challenge_index),0)+1 INTO v_seq
    FROM devices.mqtt_rpc_challenge c WHERE c.id_mqtt_pairing_operation=p_operation;
  IF v_seq > 5 THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MQTT_RPC_CHALLENGE_ATTEMPTS_EXHAUSTED';
  END IF;
  INSERT INTO devices.mqtt_rpc_challenge AS new_challenge (
    id_mqtt_pairing_operation, challenge_index, issued_at, expires_at
  ) VALUES (p_operation,v_seq,v_now,v_now + INTERVAL '15 seconds')
  RETURNING new_challenge.rpc_id INTO v_id;

  RETURN QUERY SELECT v_id,v_op.manufacturer_device_id::text,
    (v_op.topic_scope||'/rpc')::text,
    (v_op.topic_scope||'/events/rpc')::text,
    (v_op.topic_scope||'/events')::text,
    v_now,v_now+INTERVAL '15 seconds',
    v_op.broker_username::text,v_op.broker_client_id::text,
    v_op.broker_role_name::text;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_issue_mqtt_rpc_challenge(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_issue_mqtt_rpc_challenge(UUID) TO smarthome_mqtt_rpc_worker;

-- Consumes a response *candidate* at most once. Caller MUST validate the
-- broker snapshot AND the Shelly.GetDeviceInfo RPC payload before calling.
-- This function does NOT validate real MQTT provenance or mark AUTH_VERIFIED.
CREATE FUNCTION devices.fn_consume_mqtt_rpc_candidate(p_operation UUID,p_rpc_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE
  v_op devices.mqtt_pairing_operation%ROWTYPE;
  v_now TIMESTAMPTZ;
BEGIN
  IF p_operation IS NULL OR p_rpc_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='MQTT_RPC_CANDIDATE_ARGUMENTS_REQUIRED';
  END IF;
  SELECT * INTO v_op FROM devices.mqtt_pairing_operation o
    WHERE o.id_mqtt_pairing_operation=p_operation FOR UPDATE;
  v_now := clock_timestamp();
  IF NOT FOUND OR v_op.status <> 'AWAITING_AUTH'
     OR v_op.authenticated_at IS NOT NULL OR v_op.id_device IS NOT NULL
     OR NOT EXISTS (
       SELECT 1 FROM devices.device_pairing_session ps
       JOIN auth."user" u ON u.id_user=ps.id_user AND u.status='ACTIVE'
       JOIN homes.home h ON h.id_home=ps.id_home
         AND h.status='ACTIVE' AND h.deleted_at IS NULL
       JOIN homes.home_member hm ON hm.id_home=ps.id_home
         AND hm.id_user=ps.id_user AND hm.role='OWNER' AND hm.status='ACTIVE'
       WHERE ps.id_device_pairing_session=v_op.id_device_pairing_session
         AND ps.status='WAITING_FOR_MQTT' AND ps.expires_at > v_now
         AND ps.model_code='S4SW-001P16EU'
         AND lower(ps.manufacturer_device_id)=v_op.manufacturer_device_id
     )
  THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_RPC_CANDIDATE_NOT_ACCEPTABLE';
  END IF;
  UPDATE devices.mqtt_rpc_challenge c SET consumed_at=v_now
  WHERE c.id_mqtt_pairing_operation=p_operation AND c.rpc_id=p_rpc_id
    AND c.consumed_at IS NULL AND c.invalidated_at IS NULL
    AND c.expires_at > v_now;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_RPC_CANDIDATE_NOT_ACCEPTABLE';
  END IF;
  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_consume_mqtt_rpc_candidate(UUID,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_consume_mqtt_rpc_candidate(UUID,UUID) TO smarthome_mqtt_rpc_worker;

COMMENT ON FUNCTION devices.fn_consume_mqtt_rpc_candidate(UUID,UUID) IS
  'At-most-once correlation marker only. Does NOT prove physical possession, connection publisher, broker authentication or AUTH_VERIFIED.';
