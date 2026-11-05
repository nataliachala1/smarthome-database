-- SmartHome 032: durable revocation and reconciliation for unbound pairing operations.
-- Do not execute against a database until an approved DEV rollout. This file is
-- additive; historical SQL011-031 files remain unchanged.
DO $$
BEGIN
  IF to_regclass('devices.mqtt_pairing_operation') IS NULL
     OR to_regclass('devices.mqtt_pairing_state_event') IS NULL
     OR to_regclass('devices.mqtt_identity') IS NULL
     OR to_regclass('devices.mqtt_preparation_secret') IS NULL
     OR to_regprocedure('devices.fn_claim_mqtt_revocation()') IS NULL
     OR to_regprocedure('devices.fn_finish_mqtt_revocation(uuid,uuid,text)') IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='smarthome_mqtt_revoke')
     OR to_regclass('devices.mqtt_pairing_revocation_attestation') IS NOT NULL
  THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='MQTT_032_PREREQUISITES_NOT_MET';
  END IF;
  -- Never replace a live lease or invent evidence for old terminal rows.
  IF EXISTS (SELECT 1 FROM devices.mqtt_pairing_operation
             WHERE status IN ('PREPARING','ENABLING','REVOKING'))
     OR EXISTS (SELECT 1 FROM devices.mqtt_identity
                WHERE state='REVOKE_PENDING' AND lease_token IS NOT NULL
                  AND lease_until > clock_timestamp())
     OR EXISTS (SELECT 1 FROM devices.mqtt_pairing_operation WHERE status='REVOKED')
  THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='MQTT_032_ACTIVE_OR_UNATTESTED_WORK_REQUIRES_REVIEW';
  END IF;
END $$;

-- A first clean observation starts a quiet window. A second observation after
-- that window is required to close races with delayed broker commands after a
-- worker timeout or process crash.
ALTER TABLE devices.mqtt_pairing_operation
  ADD COLUMN revocation_probe_at TIMESTAMPTZ;
COMMENT ON COLUMN devices.mqtt_pairing_operation.revocation_probe_at IS
  'First broker-confirmed disabled/absent observation. REVOKED requires another clean observation at least 120 seconds later.';

-- REVOKED on a pre-attachment operation is backed by a worker observation,
-- never by the Android client or an administrative command's attempted send.
CREATE TABLE devices.mqtt_pairing_revocation_attestation (
  id_mqtt_pairing_operation UUID PRIMARY KEY
    REFERENCES devices.mqtt_pairing_operation(id_mqtt_pairing_operation) ON DELETE RESTRICT,
  broker_username VARCHAR(128) NOT NULL,
  broker_client_id VARCHAR(128) NOT NULL,
  broker_role_name VARCHAR(128) NOT NULL,
  outcome TEXT NOT NULL CHECK (outcome IN ('IDENTITY_ABSENT','DISABLED_NO_CONNECTIONS')),
  observed_at TIMESTAMPTZ NOT NULL,
  CONSTRAINT ck_mqtt_pairing_revocation_binding CHECK (
    broker_username ~ '^[A-Za-z0-9_-]{1,128}$'
    AND broker_client_id ~ '^[A-Za-z0-9_-]{1,128}$'
    AND broker_role_name ~ '^[A-Za-z0-9_-]{1,128}$'
  )
);
ALTER TABLE devices.mqtt_pairing_revocation_attestation ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON devices.mqtt_pairing_revocation_attestation FROM PUBLIC,
  smarthome_runtime_app, smarthome_worker, smarthome_ingest, smarthome_readonly,
  smarthome_admin, smarthome_mqtt_registrar, smarthome_mqtt_revoke,
  smarthome_mqtt_reserver, smarthome_mqtt_lease_worker,
  smarthome_mqtt_auth_confirmer, smarthome_mqtt_rpc_worker,
  smarthome_mqtt_prepare_confirmer, smarthome_mqtt_secret_worker;
COMMENT ON TABLE devices.mqtt_pairing_revocation_attestation IS
  'Broker observation asserted by the isolated revocation worker before REVOKED. Contains identity binding and outcome only; no secret, token, or payload.';

CREATE FUNCTION devices.fn_guard_mqtt_pairing_revocation_attestation()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
BEGIN
  RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='MQTT_PAIRING_REVOCATION_EVIDENCE_IMMUTABLE';
END $$;
REVOKE ALL ON FUNCTION devices.fn_guard_mqtt_pairing_revocation_attestation() FROM PUBLIC;
CREATE TRIGGER trg_guard_mqtt_pairing_revocation_attestation
  BEFORE UPDATE OR DELETE OR TRUNCATE ON devices.mqtt_pairing_revocation_attestation
  FOR EACH STATEMENT EXECUTE FUNCTION devices.fn_guard_mqtt_pairing_revocation_attestation();

-- Keep the existing SQL024 state guard and add a second, evidence-specific
-- guard. Even an accidental privileged update cannot set REVOKED without the
-- attestation for the exact reserved broker binding.
CREATE FUNCTION devices.fn_guard_mqtt_pairing_revoked_evidence()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
BEGIN
  IF NEW.status='REVOKED' AND OLD.status IS DISTINCT FROM 'REVOKED'
     AND NOT EXISTS (
       SELECT 1 FROM devices.mqtt_pairing_revocation_attestation a
       WHERE a.id_mqtt_pairing_operation=NEW.id_mqtt_pairing_operation
         AND a.broker_username=NEW.broker_username
         AND a.broker_client_id=NEW.broker_client_id
         AND a.broker_role_name=NEW.broker_role_name
         AND a.observed_at=NEW.revoked_at
     ) THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_PAIRING_REVOKED_REQUIRES_BROKER_EVIDENCE';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION devices.fn_guard_mqtt_pairing_revoked_evidence() FROM PUBLIC;
CREATE TRIGGER trg_guard_mqtt_pairing_revoked_evidence
  BEFORE UPDATE OF status ON devices.mqtt_pairing_operation
  FOR EACH ROW EXECUTE FUNCTION devices.fn_guard_mqtt_pairing_revoked_evidence();

-- One call normalizes expired/cancelled work, queues revocation and claims at
-- most one row. SKIP LOCKED plus random lease tokens fence concurrent workers.
-- A live PREPARING/ENABLING lease is never stolen: cancellation/expiry waits
-- for its bounded broker request to finish or for the lease to expire.
CREATE FUNCTION devices.fn_claim_mqtt_pairing_revocation(p_lease_seconds INTEGER DEFAULT 60)
RETURNS TABLE(operation_id UUID, lease_token UUID, lease_until TIMESTAMPTZ,
  identity_id UUID, username TEXT, client_id TEXT, role_name TEXT,
  attempt INTEGER, revocation_probe_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE
  v_now TIMESTAMPTZ := clock_timestamp();
  v_token UUID;
  v_until TIMESTAMPTZ;
  v_op devices.mqtt_pairing_operation%ROWTYPE;
BEGIN
  IF p_lease_seconds IS NULL OR p_lease_seconds NOT BETWEEN 30 AND 120 THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='MQTT_PAIRING_REVOCATION_LEASE_INVALID';
  END IF;

  -- A crashed provision/enable/revoke worker may have completed its external
  -- side effect. Quarantine first; it is never treated as success or retried
  -- as a positive action.
  WITH stale AS (
    SELECT o.id_mqtt_pairing_operation
    FROM devices.mqtt_pairing_operation o
    WHERE o.id_device IS NULL
      AND o.status IN ('PREPARING','ENABLING','REVOKING')
      AND o.lease_until <= v_now
    ORDER BY o.lease_until, o.id_mqtt_pairing_operation
    LIMIT 64 FOR UPDATE OF o SKIP LOCKED
  )
  UPDATE devices.mqtt_pairing_operation o
    SET status='RECONCILIATION_REQUIRED', lease_token=NULL, lease_until=NULL,
        retry_at=v_now+INTERVAL '120 seconds',
        revocation_probe_at=NULL,
        last_error_code='MQTT_ADMIN_OUTCOME_UNKNOWN'
  FROM stale s WHERE o.id_mqtt_pairing_operation=s.id_mqtt_pairing_operation;

  -- SQL025 can leave an uncertain operation without retry_at. Start its quiet
  -- window before considering any reconciliation row eligible for claiming.
  UPDATE devices.mqtt_pairing_operation
    SET retry_at=v_now+INTERVAL '120 seconds'
  WHERE id_device IS NULL AND status='RECONCILIATION_REQUIRED'
    AND retry_at IS NULL;

  -- Cancellation, expiry and an impossible completed-but-unattached row are
  -- read from the durable session row. No HTTP report is trusted. Any
  -- uncertain operation is also revoked fail-closed.
  WITH due AS (
    SELECT o.id_mqtt_pairing_operation
    FROM devices.mqtt_pairing_operation o
    JOIN devices.device_pairing_session ps
      ON ps.id_device_pairing_session=o.id_device_pairing_session
    WHERE o.id_device IS NULL AND o.lease_token IS NULL AND o.lease_until IS NULL
      AND o.status IN ('RESERVED','PREPARED_DISABLED','ENABLE_PENDING',
                       'AWAITING_AUTH','AUTH_VERIFIED','RECONCILIATION_REQUIRED')
      AND (
        (o.status='RECONCILIATION_REQUIRED'
          AND o.retry_at IS NOT NULL AND o.retry_at <= v_now)
        OR (o.status<>'RECONCILIATION_REQUIRED' AND
          (ps.status IN ('CANCELLED','EXPIRED','FAILED','COMPLETED') OR ps.expires_at <= v_now))
      )
    ORDER BY COALESCE(o.retry_at, ps.expires_at), o.id_mqtt_pairing_operation
    LIMIT 128 FOR UPDATE OF o SKIP LOCKED
  )
  UPDATE devices.mqtt_pairing_operation o
    SET status='REVOKE_PENDING',
        revocation_requested_at=COALESCE(o.revocation_requested_at,v_now),
        retry_at=v_now
  FROM due d WHERE o.id_mqtt_pairing_operation=d.id_mqtt_pairing_operation;

  SELECT * INTO v_op FROM devices.mqtt_pairing_operation o
  WHERE o.id_device IS NULL AND o.status='REVOKE_PENDING'
    AND o.revocation_requested_at IS NOT NULL
    AND o.retry_at IS NOT NULL AND o.retry_at <= v_now
    AND o.lease_token IS NULL AND o.lease_until IS NULL
    AND o.attempt_count < 2147483647
  ORDER BY COALESCE(o.retry_at,o.revocation_requested_at),o.id_mqtt_pairing_operation
  LIMIT 1 FOR UPDATE SKIP LOCKED;
  IF NOT FOUND THEN RETURN; END IF;

  v_token:=gen_random_uuid();
  v_until:=v_now+make_interval(secs=>p_lease_seconds);
  UPDATE devices.mqtt_pairing_operation AS target
  SET status='REVOKING', lease_token=v_token, lease_until=v_until,
      attempt_count=target.attempt_count+1, retry_at=NULL, last_error_code=NULL
  WHERE target.id_mqtt_pairing_operation=v_op.id_mqtt_pairing_operation
    AND target.status='REVOKE_PENDING' AND target.lease_token IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_PAIRING_REVOCATION_CLAIM_FENCED';
  END IF;
  RETURN QUERY SELECT v_op.id_mqtt_pairing_operation,v_token,v_until,
    v_op.id_mqtt_identity,v_op.broker_username::text,
    v_op.broker_client_id::text,v_op.broker_role_name::text,
    v_op.attempt_count,v_op.revocation_probe_at;
END $$;
REVOKE ALL ON FUNCTION devices.fn_claim_mqtt_pairing_revocation(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_claim_mqtt_pairing_revocation(INTEGER)
  TO smarthome_mqtt_revoke;

CREATE FUNCTION devices.fn_finish_mqtt_pairing_revocation(
  p_operation UUID,p_token UUID,p_outcome TEXT,p_error TEXT
) RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE
  v_op devices.mqtt_pairing_operation%ROWTYPE;
  v_now TIMESTAMPTZ:=clock_timestamp();
  v_retry TIMESTAMPTZ;
  v_count INTEGER;
BEGIN
  IF p_operation IS NULL OR p_token IS NULL
     OR (p_error IS NULL AND (p_outcome IS NULL OR p_outcome NOT IN ('IDENTITY_ABSENT','DISABLED_NO_CONNECTIONS')))
     OR (p_error IS NOT NULL AND (p_outcome IS NOT NULL OR p_error NOT IN (
       'MQTT_ADMIN_UNAVAILABLE','MQTT_ADMIN_REJECTED','MQTT_ADMIN_OUTCOME_UNKNOWN',
       'MQTT_ADMIN_INVALID_RESPONSE','MQTT_ADMIN_UNSAFE_DEFAULT_ACL',
       'MQTT_REVOCATION_UNEXPECTED'
     ))) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='MQTT_PAIRING_REVOCATION_FINISH_INVALID';
  END IF;
  SELECT * INTO v_op FROM devices.mqtt_pairing_operation
  WHERE id_mqtt_pairing_operation=p_operation FOR UPDATE;
  IF NOT FOUND OR v_op.status<>'REVOKING' OR v_op.id_device IS NOT NULL
     OR v_op.revocation_requested_at IS NULL OR v_op.lease_token IS DISTINCT FROM p_token
     OR v_op.lease_until IS NULL OR v_op.lease_until<=v_now THEN
    RETURN 'LEASE_LOST';
  END IF;

  IF p_error IS NULL THEN
    IF v_op.revocation_probe_at IS NULL OR
       v_op.revocation_probe_at > v_now-INTERVAL '120 seconds' THEN
      UPDATE devices.mqtt_pairing_operation SET
        status='RECONCILIATION_REQUIRED',
        lease_token=NULL,lease_until=NULL,
        revocation_probe_at=COALESCE(revocation_probe_at,v_now),
        retry_at=COALESCE(revocation_probe_at,v_now)+INTERVAL '120 seconds',
        last_error_code='MQTT_ADMIN_OUTCOME_UNKNOWN'
      WHERE id_mqtt_pairing_operation=p_operation AND status='REVOKING'
        AND lease_token=p_token AND lease_until>v_now;
      GET DIAGNOSTICS v_count=ROW_COUNT;
      RETURN CASE WHEN v_count=1 THEN 'RETRY_SCHEDULED' ELSE 'LEASE_LOST' END;
    END IF;
    INSERT INTO devices.mqtt_pairing_revocation_attestation(
      id_mqtt_pairing_operation,broker_username,broker_client_id,
      broker_role_name,outcome,observed_at
    ) VALUES (p_operation,v_op.broker_username,v_op.broker_client_id,
      v_op.broker_role_name,p_outcome,v_now);
    UPDATE devices.mqtt_pairing_operation SET
      status='REVOKED',revoked_at=v_now,lease_token=NULL,lease_until=NULL,
      retry_at=NULL,last_error_code=NULL
    WHERE id_mqtt_pairing_operation=p_operation AND status='REVOKING'
      AND lease_token=p_token AND lease_until>v_now;
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>1 THEN
      RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_PAIRING_REVOCATION_FINISH_FENCED';
    END IF;
    DELETE FROM devices.mqtt_preparation_secret WHERE id_mqtt_pairing_operation=p_operation;
    RETURN 'REVOKED';
  END IF;

  v_retry:=v_now+make_interval(secs=>LEAST(300,
    (5*power(2,LEAST(v_op.attempt_count-1,6)))::INTEGER));
  v_retry:=GREATEST(v_retry,v_now+INTERVAL '120 seconds');
  UPDATE devices.mqtt_pairing_operation SET
    status='RECONCILIATION_REQUIRED',lease_token=NULL,lease_until=NULL,
    retry_at=v_retry,last_error_code=p_error,revocation_probe_at=NULL
  WHERE id_mqtt_pairing_operation=p_operation AND status='REVOKING'
    AND lease_token=p_token AND lease_until>v_now;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  RETURN CASE WHEN v_count=1 THEN 'RETRY_SCHEDULED' ELSE 'LEASE_LOST' END;
END $$;
REVOKE ALL ON FUNCTION devices.fn_finish_mqtt_pairing_revocation(UUID,UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_finish_mqtt_pairing_revocation(UUID,UUID,TEXT,TEXT)
  TO smarthome_mqtt_revoke;

-- Adapter around the established SQL011 queue. It preserves the old claim
-- contract but also returns the broker binding reserved by SQL022 when one
-- exists, then mirrors that same lease into mqtt_pairing_operation.
CREATE FUNCTION devices.fn_claim_mqtt_revocation_with_binding()
RETURNS TABLE(identity_id UUID,claim_token UUID,attempt INTEGER,
  operation_id UUID,revocation_probe_at TIMESTAMPTZ,
  broker_username TEXT,broker_client_id TEXT,broker_role_name TEXT)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE
  v_claim RECORD;
  v_op devices.mqtt_pairing_operation%ROWTYPE;
  v_identity devices.mqtt_identity%ROWTYPE;
  v_token UUID;
  v_until TIMESTAMPTZ;
  v_count INTEGER;
BEGIN
  SELECT * INTO v_claim FROM devices.fn_claim_mqtt_revocation();
  IF NOT FOUND THEN RETURN; END IF;
  v_token:=v_claim.claim_token;
  SELECT * INTO v_identity FROM devices.mqtt_identity
  WHERE id_mqtt_identity=v_claim.identity_id AND state='REVOKE_PENDING'
    AND lease_token=v_token FOR UPDATE;
  IF NOT FOUND OR v_identity.lease_until IS NULL OR v_identity.lease_until<=clock_timestamp() THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MQTT_IDENTITY_REVOCATION_CLAIM_CHANGED';
  END IF;
  v_until:=v_identity.lease_until;

  SELECT * INTO v_op FROM devices.mqtt_pairing_operation
  WHERE id_mqtt_identity=v_claim.identity_id FOR UPDATE;
  IF FOUND THEN
    IF v_op.id_device IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MQTT_IDENTITY_PAIRING_ATTACHMENT_MISMATCH';
    END IF;
    IF v_op.status='ATTACHED' THEN
      UPDATE devices.mqtt_pairing_operation SET status='REVOKE_PENDING',
        revocation_requested_at=COALESCE(revocation_requested_at,clock_timestamp()),
        retry_at=clock_timestamp()
      WHERE id_mqtt_pairing_operation=v_op.id_mqtt_pairing_operation AND status='ATTACHED';
      SELECT * INTO v_op FROM devices.mqtt_pairing_operation
      WHERE id_mqtt_pairing_operation=v_op.id_mqtt_pairing_operation FOR UPDATE;
    ELSIF v_op.status='REVOKING' AND v_op.lease_until<=clock_timestamp() THEN
      UPDATE devices.mqtt_pairing_operation SET status='RECONCILIATION_REQUIRED',
        lease_token=NULL,lease_until=NULL,retry_at=clock_timestamp(),
        last_error_code='MQTT_ADMIN_OUTCOME_UNKNOWN'
      WHERE id_mqtt_pairing_operation=v_op.id_mqtt_pairing_operation
        AND status='REVOKING' AND lease_until<=clock_timestamp();
      SELECT * INTO v_op FROM devices.mqtt_pairing_operation
      WHERE id_mqtt_pairing_operation=v_op.id_mqtt_pairing_operation FOR UPDATE;
    ELSIF v_op.status='RECONCILIATION_REQUIRED'
      AND (v_op.retry_at IS NULL OR v_op.retry_at<=clock_timestamp()) THEN
      UPDATE devices.mqtt_pairing_operation SET status='REVOKE_PENDING',
        revocation_requested_at=COALESCE(revocation_requested_at,clock_timestamp()),
        retry_at=clock_timestamp()
      WHERE id_mqtt_pairing_operation=v_op.id_mqtt_pairing_operation
        AND status='RECONCILIATION_REQUIRED';
      SELECT * INTO v_op FROM devices.mqtt_pairing_operation
      WHERE id_mqtt_pairing_operation=v_op.id_mqtt_pairing_operation FOR UPDATE;
    END IF;

    -- The previous REVOKING lease may have expired at the same time as the
    -- SQL011 identity lease. Normalize it, then let this fresh identity claim
    -- establish the next operation lease in the same transaction.
    IF v_op.status='RECONCILIATION_REQUIRED'
       AND (v_op.retry_at IS NULL OR v_op.retry_at<=clock_timestamp()) THEN
      UPDATE devices.mqtt_pairing_operation SET status='REVOKE_PENDING',
        revocation_requested_at=COALESCE(revocation_requested_at,clock_timestamp()),
        retry_at=clock_timestamp()
      WHERE id_mqtt_pairing_operation=v_op.id_mqtt_pairing_operation
        AND status='RECONCILIATION_REQUIRED';
      SELECT * INTO v_op FROM devices.mqtt_pairing_operation
      WHERE id_mqtt_pairing_operation=v_op.id_mqtt_pairing_operation FOR UPDATE;
    END IF;

    IF v_op.status='REVOKE_PENDING' THEN
      IF v_op.attempt_count >= 2147483647 THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MQTT_IDENTITY_PAIRING_REVOCATION_ATTEMPTS_EXHAUSTED';
      END IF;
      UPDATE devices.mqtt_pairing_operation SET status='REVOKING',
        lease_token=v_token,lease_until=v_until,
        attempt_count=attempt_count+1,retry_at=NULL,last_error_code=NULL
      WHERE id_mqtt_pairing_operation=v_op.id_mqtt_pairing_operation
        AND status='REVOKE_PENDING' AND lease_token IS NULL;
      GET DIAGNOSTICS v_count=ROW_COUNT;
      IF v_count<>1 THEN
        RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MQTT_IDENTITY_PAIRING_REVOCATION_FENCED';
      END IF;
    ELSIF v_op.status<>'REVOKING' OR v_op.lease_token IS DISTINCT FROM v_token
      OR v_op.lease_until IS NULL OR v_op.lease_until<=clock_timestamp() THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MQTT_IDENTITY_PAIRING_REVOCATION_FENCED';
    END IF;
    RETURN QUERY SELECT v_claim.identity_id,v_token,v_claim.attempt,
      v_op.id_mqtt_pairing_operation,v_op.revocation_probe_at,
      v_op.broker_username::text,v_op.broker_client_id::text,v_op.broker_role_name::text;
    RETURN;
  END IF;

  -- Legacy SQL011 identities predate per-operation broker names.
  RETURN QUERY SELECT v_claim.identity_id,v_token,v_claim.attempt,
    NULL::UUID,NULL::TIMESTAMPTZ,
    ('device-'||v_claim.identity_id::text)::text,NULL::text,NULL::text;
END $$;
REVOKE ALL ON FUNCTION devices.fn_claim_mqtt_revocation_with_binding() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_claim_mqtt_revocation_with_binding()
  TO smarthome_mqtt_revoke;

-- Completes SQL011 identity revocation and the attached pairing operation in
-- one DB transaction. The existing SQL011 queue/audit/backoff stays canonical.
CREATE FUNCTION devices.fn_finish_mqtt_revocation_evidenced(
  p_identity UUID,p_token UUID,p_error TEXT,p_outcome TEXT
) RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE
  v_op devices.mqtt_pairing_operation%ROWTYPE;
  v_identity devices.mqtt_identity%ROWTYPE;
  v_has_op BOOLEAN:=FALSE;
  v_now TIMESTAMPTZ:=clock_timestamp();
  v_finished BOOLEAN;
  v_retry TIMESTAMPTZ;
  v_count INTEGER;
BEGIN
  IF p_identity IS NULL OR p_token IS NULL
     OR (p_error IS NULL AND (p_outcome IS NULL OR p_outcome NOT IN ('IDENTITY_ABSENT','DISABLED_NO_CONNECTIONS')))
     OR (p_error IS NOT NULL AND (p_outcome IS NOT NULL OR p_error NOT IN (
       'MQTT_ADMIN_UNAVAILABLE','MQTT_ADMIN_REJECTED','MQTT_ADMIN_OUTCOME_UNKNOWN',
       'MQTT_ADMIN_INVALID_RESPONSE','MQTT_ADMIN_UNSAFE_DEFAULT_ACL',
       'MQTT_REVOCATION_UNEXPECTED'
     ))) THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MQTT_IDENTITY_REVOCATION_FINISH_INVALID';
  END IF;
  -- Keep the lock order identical to the claim wrapper (identity, then
  -- operation) to avoid deadlocks when a lease expires during a late ACK.
  SELECT * INTO v_identity FROM devices.mqtt_identity
  WHERE id_mqtt_identity=p_identity FOR UPDATE;
  IF NOT FOUND OR v_identity.state<>'REVOKE_PENDING'
     OR v_identity.lease_token IS DISTINCT FROM p_token
     OR v_identity.lease_until IS NULL OR v_identity.lease_until<=v_now THEN
    RETURN 'LEASE_LOST';
  END IF;
  SELECT * INTO v_op FROM devices.mqtt_pairing_operation
  WHERE id_mqtt_identity=p_identity FOR UPDATE;
  v_has_op:=FOUND;
  IF v_has_op AND (v_op.id_device IS NULL OR v_op.status<>'REVOKING'
     OR v_op.lease_token IS DISTINCT FROM p_token OR v_op.lease_until IS NULL
     OR v_op.lease_until<=v_now) THEN
    RETURN 'LEASE_LOST';
  END IF;

  -- For an attached operation, the first clean broker result starts a
  -- 120-second quiet window. Keep SQL011 pending until a second fresh
  -- observation after that window; this also handles a delayed prior worker.
  IF v_has_op AND p_error IS NULL AND
     (v_op.revocation_probe_at IS NULL OR
      v_op.revocation_probe_at > v_now-INTERVAL '120 seconds') THEN
    v_finished:=devices.fn_finish_mqtt_revocation(
      p_identity,p_token,'MQTT_ADMIN_OUTCOME_UNKNOWN');
    IF NOT v_finished THEN RETURN 'LEASE_LOST'; END IF;
    SELECT retry_at INTO v_retry FROM devices.mqtt_identity
    WHERE id_mqtt_identity=p_identity AND state='REVOKE_PENDING';
    v_retry:=GREATEST(COALESCE(v_retry,v_now),
      COALESCE(v_op.revocation_probe_at,v_now)+INTERVAL '120 seconds');
    UPDATE devices.mqtt_identity SET retry_at=v_retry
    WHERE id_mqtt_identity=p_identity AND state='REVOKE_PENDING'
      AND lease_token IS NULL;
    UPDATE devices.mqtt_pairing_operation SET
      status='RECONCILIATION_REQUIRED',lease_token=NULL,lease_until=NULL,
      revocation_probe_at=COALESCE(revocation_probe_at,v_now),
      retry_at=v_retry,last_error_code='MQTT_ADMIN_OUTCOME_UNKNOWN'
    WHERE id_mqtt_pairing_operation=v_op.id_mqtt_pairing_operation
      AND status='REVOKING' AND lease_token=p_token;
    GET DIAGNOSTICS v_count=ROW_COUNT;
    RETURN CASE WHEN v_count=1 THEN 'RETRY_SCHEDULED' ELSE 'LEASE_LOST' END;
  END IF;

  -- Call the established SQL011 procedure for identity lease fencing,
  -- exponential retries and append-only mqtt_identity_event history.
  v_finished:=devices.fn_finish_mqtt_revocation(p_identity,p_token,p_error);
  IF NOT v_finished THEN RETURN 'LEASE_LOST'; END IF;
  IF NOT v_has_op THEN RETURN 'REVOKED'; END IF;

  IF p_error IS NULL THEN
    INSERT INTO devices.mqtt_pairing_revocation_attestation(
      id_mqtt_pairing_operation,broker_username,broker_client_id,
      broker_role_name,outcome,observed_at
    ) VALUES (v_op.id_mqtt_pairing_operation,v_op.broker_username,
      v_op.broker_client_id,v_op.broker_role_name,p_outcome,v_now);
    UPDATE devices.mqtt_pairing_operation SET status='REVOKED',revoked_at=v_now,
      lease_token=NULL,lease_until=NULL,retry_at=NULL,last_error_code=NULL
    WHERE id_mqtt_pairing_operation=v_op.id_mqtt_pairing_operation
      AND status='REVOKING' AND lease_token=p_token AND lease_until>v_now;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MQTT_IDENTITY_PAIRING_FINISH_FENCED';
    END IF;
    DELETE FROM devices.mqtt_preparation_secret
      WHERE id_mqtt_pairing_operation=v_op.id_mqtt_pairing_operation;
    RETURN 'REVOKED';
  END IF;

  v_retry:=v_identity.retry_at;
  v_retry:=GREATEST(COALESCE(v_retry,v_now),v_now+INTERVAL '120 seconds');
  UPDATE devices.mqtt_identity SET retry_at=v_retry
  WHERE id_mqtt_identity=p_identity AND state='REVOKE_PENDING'
    AND lease_token IS NULL;
  UPDATE devices.mqtt_pairing_operation SET status='RECONCILIATION_REQUIRED',
    lease_token=NULL,lease_until=NULL,retry_at=v_retry,last_error_code=p_error,
    revocation_probe_at=NULL
  WHERE id_mqtt_pairing_operation=v_op.id_mqtt_pairing_operation
    AND status='REVOKING' AND lease_token=p_token;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MQTT_IDENTITY_PAIRING_RETRY_FENCED';
  END IF;
  RETURN 'RETRY_SCHEDULED';
END $$;
REVOKE ALL ON FUNCTION devices.fn_finish_mqtt_revocation_evidenced(UUID,UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_finish_mqtt_revocation_evidenced(UUID,UUID,TEXT,TEXT)
  TO smarthome_mqtt_revoke;

COMMENT ON FUNCTION devices.fn_claim_mqtt_pairing_revocation(INTEGER) IS
  'Claims one unbound operation after durable session cancellation/expiry or uncertainty. It never retries prepare/enable and never infers broker success.';
COMMENT ON FUNCTION devices.fn_finish_mqtt_pairing_revocation(UUID,UUID,TEXT,TEXT) IS
  'Fenced completion for an unbound operation. REVOKED requires exact broker absence or disabled state with zero observed connections.';
COMMENT ON FUNCTION devices.fn_claim_mqtt_revocation_with_binding() IS
  'Adapter over the SQL011 identity revocation queue; mirrors the same lease into the attached pairing operation when present.';
COMMENT ON FUNCTION devices.fn_finish_mqtt_revocation_evidenced(UUID,UUID,TEXT,TEXT) IS
  'Finishes the existing SQL011 identity queue and attached operation atomically after isolated worker evidence.';

-- The deployment login may use only the evidenced wrappers. The legacy
-- procedures remain callable by their SECURITY DEFINER owners and wrappers.
REVOKE EXECUTE ON FUNCTION devices.fn_claim_mqtt_revocation()
  FROM smarthome_mqtt_revoke;
REVOKE EXECUTE ON FUNCTION devices.fn_finish_mqtt_revocation(UUID,UUID,TEXT)
  FROM smarthome_mqtt_revoke;
