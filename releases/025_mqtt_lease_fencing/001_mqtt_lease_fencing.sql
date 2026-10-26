-- HU16/HU11 025: lease-fenced SECURITY DEFINER operations (fail-closed).
-- Prerequisites: hardened 022, 023, 024. No MQTT broker calls; no success states.
-- Worker roles have EXECUTE only. Database owners/superusers remain trusted DBA.
DO $$
BEGIN
  IF to_regclass('devices.mqtt_pairing_operation') IS NULL
     OR to_regclass('devices.mqtt_pairing_state_event') IS NULL
     OR to_regprocedure('devices.fn_reserve_mqtt_pairing_operation(uuid,text,uuid,text)') IS NULL
     OR to_regprocedure('devices.fn_claim_mqtt_pairing_preparation(uuid,integer)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM devices.mqtt_pairing_operation WHERE status <> 'RESERVED')
  THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='MQTT_025_PREREQUISITES_OR_UNTRACKED_STATE';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='smarthome_mqtt_lease_worker') THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='MQTT_025_ROLE_ALREADY_EXISTS_REVIEW_FIRST';
  END IF;
END;
$$;

CREATE ROLE smarthome_mqtt_lease_worker NOLOGIN NOINHERIT
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT USAGE ON SCHEMA devices TO smarthome_mqtt_lease_worker;

-- Claim is for FIRST PREPARATION ONLY. An expired active lease must be
-- quarantined, NOT reclaimed and blindly retried at Mosquitto: its external
-- effect could have succeeded after our application lost its response.
CREATE FUNCTION devices.fn_claim_mqtt_pairing_preparation(
  p_operation UUID, p_lease_seconds INTEGER DEFAULT 60
)
RETURNS TABLE(operation_id UUID, assigned_token UUID,
  expires_at TIMESTAMPTZ, attempt_number INTEGER)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_op devices.mqtt_pairing_operation%ROWTYPE;
  v_token UUID;
  v_expires TIMESTAMPTZ;
  v_now TIMESTAMPTZ;
BEGIN
  IF p_operation IS NULL OR p_lease_seconds IS NULL
     OR p_lease_seconds NOT BETWEEN 1 AND 300 THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='MQTT_LEASE_CLAIM_ARGUMENTS_INVALID';
  END IF;

  SELECT * INTO v_op FROM devices.mqtt_pairing_operation
    WHERE id_mqtt_pairing_operation = p_operation FOR UPDATE;
  v_now := clock_timestamp();

  IF NOT FOUND OR v_op.status <> 'RESERVED'
     OR v_op.lease_token IS NOT NULL OR v_op.lease_until IS NOT NULL
     OR (v_op.retry_at IS NOT NULL AND v_op.retry_at > v_now)
     OR NOT EXISTS (
       SELECT 1 FROM devices.device_pairing_session ps
       JOIN auth."user" u ON u.id_user = ps.id_user AND u.status='ACTIVE'
       JOIN homes.home h ON h.id_home = ps.id_home
          AND h.status='ACTIVE' AND h.deleted_at IS NULL
       JOIN homes.home_member hm ON hm.id_home=ps.id_home
          AND hm.id_user=ps.id_user AND hm.role='OWNER' AND hm.status='ACTIVE'
       WHERE ps.id_device_pairing_session = v_op.id_device_pairing_session
         AND ps.status IN ('DEVICE_IDENTIFIED','WAITING_FOR_MQTT')
         AND ps.expires_at > v_now
         AND ps.model_code='S4SW-001P16EU'
         AND lower(ps.manufacturer_device_id)=v_op.manufacturer_device_id
     ) THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_LEASE_NOT_CLAIMABLE';
  END IF;

  v_token := gen_random_uuid();
  v_expires := v_now + make_interval(secs => p_lease_seconds);
  UPDATE devices.mqtt_pairing_operation
    SET status='PREPARING', lease_token=v_token, lease_until=v_expires,
        attempt_count=v_op.attempt_count+1, retry_at=NULL
  WHERE id_mqtt_pairing_operation = p_operation AND status='RESERVED';

  RETURN QUERY SELECT v_op.id_mqtt_pairing_operation, v_token,
    v_expires, v_op.attempt_count+1;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_claim_mqtt_pairing_preparation(UUID,INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_claim_mqtt_pairing_preparation(UUID,INTEGER)
  TO smarthome_mqtt_lease_worker;

-- A token-matched, unexpired worker may only report UNCERTAINTY. Positive
-- broker outcomes have NO worker API in 025 and cannot be inferred from timestamps.
CREATE FUNCTION devices.fn_report_mqtt_pairing_uncertain(
  p_operation UUID, p_lease_token UUID, p_error_code TEXT
)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_op devices.mqtt_pairing_operation%ROWTYPE;
  v_now TIMESTAMPTZ;
BEGIN
  IF p_operation IS NULL OR p_lease_token IS NULL
     OR p_error_code IS NULL OR p_error_code NOT IN (
       'MQTT_ADMIN_UNAVAILABLE', 'MQTT_ADMIN_OUTCOME_UNKNOWN',
       'MQTT_ADMIN_INVALID_RESPONSE', 'MQTT_PROVISIONING_UNEXPECTED',
       'MQTT_REVOCATION_UNEXPECTED'
     ) THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='MQTT_LEASE_REPORT_ARGUMENTS_INVALID';
  END IF;

  SELECT * INTO v_op FROM devices.mqtt_pairing_operation
    WHERE id_mqtt_pairing_operation=p_operation FOR UPDATE;
  v_now := clock_timestamp();
  IF NOT FOUND
     OR v_op.status NOT IN ('PREPARING','ENABLING','REVOKING')
     OR v_op.lease_token IS DISTINCT FROM p_lease_token
     OR v_op.lease_until IS NULL OR v_op.lease_until <= v_now THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_LEASE_FENCE_REJECTED';
  END IF;

  UPDATE devices.mqtt_pairing_operation SET
    status='RECONCILIATION_REQUIRED', lease_token=NULL, lease_until=NULL,
    retry_at=NULL, last_error_code=p_error_code
  WHERE id_mqtt_pairing_operation=p_operation
    AND status=v_op.status AND lease_token=p_lease_token AND lease_until > v_now;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_LEASE_FENCE_REJECTED';
  END IF;
  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_report_mqtt_pairing_uncertain(UUID,UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_report_mqtt_pairing_uncertain(UUID,UUID,TEXT)
  TO smarthome_mqtt_lease_worker;

-- After expiry, outcome might have succeeded in Mosquitto. We cannot
-- reclaim or mark a success; quarantine for broker reconciliation/revoke.
-- Only callable once the previous lease has expired.
CREATE FUNCTION devices.fn_quarantine_expired_mqtt_pairing_lease(p_operation UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_op devices.mqtt_pairing_operation%ROWTYPE;
  v_now TIMESTAMPTZ;
BEGIN
  IF p_operation IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='MQTT_LEASE_OPERATION_INVALID';
  END IF;
  SELECT * INTO v_op FROM devices.mqtt_pairing_operation
    WHERE id_mqtt_pairing_operation=p_operation FOR UPDATE;
  v_now := clock_timestamp();
  IF NOT FOUND OR v_op.status NOT IN ('PREPARING','ENABLING','REVOKING')
     OR v_op.lease_token IS NULL OR v_op.lease_until IS NULL
     OR v_op.lease_until > v_now THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_LEASE_NOT_EXPIRED';
  END IF;
  UPDATE devices.mqtt_pairing_operation SET
    status='RECONCILIATION_REQUIRED', lease_token=NULL, lease_until=NULL,
    retry_at=NULL, last_error_code='MQTT_ADMIN_OUTCOME_UNKNOWN'
  WHERE id_mqtt_pairing_operation=p_operation AND status=v_op.status
    AND lease_token=v_op.lease_token AND lease_until <= v_now;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_LEASE_NOT_EXPIRED';
  END IF;
  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_quarantine_expired_mqtt_pairing_lease(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_quarantine_expired_mqtt_pairing_lease(UUID)
  TO smarthome_mqtt_lease_worker;

COMMENT ON ROLE smarthome_mqtt_lease_worker IS
  'NOLOGIN: first preparation claim and uncertain/expired lease quarantine only. No table DML, no broker success assertions.';
