-- HU16 / 027: lease-fenced acknowledgement of broker identity preparation.
-- This function does NOT talk to the MQTT broker or prove broker-side ACLs.
-- Only a dedicated, trusted NestJS broker-verification service may invoke it,
-- AFTER checking disabled=true, exact username/clientId/role AND actual role ACLs.
-- Never expose this role or function to the mobile API or generic DB credentials.
-- Preconditions: installed 022-026; no changes to earlier migrations.

DO $$
BEGIN
  IF to_regclass('devices.mqtt_pairing_operation') IS NULL
     OR to_regprocedure('devices.fn_claim_mqtt_pairing_preparation(uuid,integer)') IS NULL
     OR to_regprocedure('devices.fn_guard_mqtt_pairing_operation_state()') IS NULL
     OR to_regprocedure('devices.fn_confirm_mqtt_pairing_prepared(uuid,uuid,uuid,text,text,text)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'smarthome_mqtt_prepare_confirmer')
  THEN
    RAISE EXCEPTION USING ERRCODE = '55000', MESSAGE = 'MQTT_027_PREREQUISITES_NOT_MET';
  END IF;
END;
$$;

CREATE ROLE smarthome_mqtt_prepare_confirmer NOLOGIN NOINHERIT
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT USAGE ON SCHEMA devices TO smarthome_mqtt_prepare_confirmer;

-- A dedicated service submits only already-verified broker metadata.
-- These parameters bind the claimed operation to the inspected account;
-- they are NOT independently sufficient proof of broker configuration.
CREATE FUNCTION devices.fn_confirm_mqtt_pairing_prepared(
  p_operation UUID,
  p_lease_token UUID,
  p_identity UUID,
  p_broker_username TEXT,
  p_broker_client_id TEXT,
  p_broker_role_name TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_op devices.mqtt_pairing_operation%ROWTYPE;
  v_now TIMESTAMPTZ;
  v_affected BIGINT;
BEGIN
  IF p_operation IS NULL OR p_lease_token IS NULL OR p_identity IS NULL
     OR p_broker_username IS NULL OR p_broker_client_id IS NULL
     OR p_broker_role_name IS NULL
  THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'MQTT_PREPARE_CONFIRM_ARGUMENTS_INVALID';
  END IF;

  SELECT * INTO v_op
  FROM devices.mqtt_pairing_operation
  WHERE id_mqtt_pairing_operation = p_operation
  FOR UPDATE;
  v_now := clock_timestamp();

  IF NOT FOUND
     OR v_op.status <> 'PREPARING'
     OR v_op.lease_token IS DISTINCT FROM p_lease_token
     OR v_op.lease_until IS NULL OR v_op.lease_until <= v_now
     OR v_op.id_mqtt_identity IS DISTINCT FROM p_identity
     OR v_op.broker_username IS DISTINCT FROM p_broker_username
     OR v_op.broker_client_id IS DISTINCT FROM p_broker_client_id
     OR v_op.broker_role_name IS DISTINCT FROM p_broker_role_name
     OR v_op.attempt_count < 1
     OR v_op.id_device IS NOT NULL
     OR v_op.authenticated_at IS NOT NULL
     OR v_op.revoked_at IS NOT NULL
     OR v_op.revocation_requested_at IS NOT NULL
     OR NOT EXISTS (
       SELECT 1
       FROM devices.device_pairing_session ps
       JOIN auth."user" u ON u.id_user = ps.id_user AND u.status = 'ACTIVE'
       JOIN homes.home h ON h.id_home = ps.id_home
         AND h.status = 'ACTIVE' AND h.deleted_at IS NULL
       JOIN homes.home_member hm ON hm.id_home = ps.id_home
         AND hm.id_user = ps.id_user AND hm.role = 'OWNER' AND hm.status = 'ACTIVE'
       WHERE ps.id_device_pairing_session = v_op.id_device_pairing_session
         AND ps.status IN ('DEVICE_IDENTIFIED', 'WAITING_FOR_MQTT')
         AND ps.expires_at > v_now
         AND ps.model_code = 'S4SW-001P16EU'
         AND lower(ps.manufacturer_device_id) = v_op.manufacturer_device_id
     )
  THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'MQTT_PREPARE_CONFIRM_FENCE_REJECTED';
  END IF;

  -- Check deadline again at update time: external verification is not atomic with SQL.
  UPDATE devices.mqtt_pairing_operation
  SET status = 'PREPARED_DISABLED',
      lease_token = NULL,
      lease_until = NULL,
      last_error_code = NULL,
      updated_at = clock_timestamp()
  WHERE id_mqtt_pairing_operation = p_operation
    AND status = 'PREPARING'
    AND lease_token = p_lease_token
    AND lease_until > clock_timestamp()
    AND id_mqtt_identity = p_identity
    AND broker_username = p_broker_username
    AND broker_client_id = p_broker_client_id
    AND broker_role_name = p_broker_role_name;
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 1 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'MQTT_PREPARE_CONFIRM_FENCE_REJECTED';
  END IF;

  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION devices.fn_confirm_mqtt_pairing_prepared(UUID,UUID,UUID,TEXT,TEXT,TEXT)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_confirm_mqtt_pairing_prepared(UUID,UUID,UUID,TEXT,TEXT,TEXT)
  TO smarthome_mqtt_prepare_confirmer;

COMMENT ON ROLE smarthome_mqtt_prepare_confirmer IS
  'NOLOGIN: confirm one prepared-disabled pairing operation only after trusted broker inspection. No table DML and no other positive state transitions.';
COMMENT ON FUNCTION devices.fn_confirm_mqtt_pairing_prepared(UUID,UUID,UUID,TEXT,TEXT,TEXT) IS
  'Lease-fenced database transition PREPARING -> PREPARED_DISABLED. Arguments bind external inspection; function cannot attest MQTT broker state itself.';
