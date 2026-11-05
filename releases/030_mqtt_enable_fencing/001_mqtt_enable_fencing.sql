-- SmartHome 030: fase de activación MQTT delimitada por token y lease.
-- No cambia SQL019..029. Nunca prueba conexión ni concede acceso al cliente HTTP.
-- Aplicar solo tras vista previa Liquibase y respaldo; no se aplica al instalar el parche.
DO $$ BEGIN
  IF to_regclass('devices.mqtt_pairing_operation') IS NULL OR
     to_regclass('devices.mqtt_preparation_secret') IS NULL OR
     to_regclass('devices.mqtt_broker_auth_attestation') IS NULL OR
     to_regprocedure('devices.fn_report_mqtt_pairing_uncertain(uuid,uuid,text)') IS NULL OR
     to_regprocedure('devices.fn_request_mqtt_enable(uuid,uuid,text)') IS NOT NULL OR
     NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='smarthome_mqtt_lease_worker')
  THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='MQTT_030_PREREQUISITES_NOT_MET';
  END IF;
END $$;

-- Solo el proceso de pairing que autenticó un OWNER puede solicitar la activación.
-- El rol SQL025 no tiene SELECT/DML en estas tablas. El token hash procede de
-- SHA256 del X-Pairing-Token en NestJS; nunca exponer esta función a HTTP directo.
CREATE FUNCTION devices.fn_request_mqtt_enable(
  p_operation UUID, p_actor UUID, p_token_hash TEXT
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_op devices.mqtt_pairing_operation%ROWTYPE; v_now TIMESTAMPTZ;
BEGIN
  IF p_operation IS NULL OR p_actor IS NULL OR p_token_hash IS NULL
     OR p_token_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='MQTT_ENABLE_REQUEST_INVALID';
  END IF;
  SELECT * INTO v_op FROM devices.mqtt_pairing_operation
    WHERE id_mqtt_pairing_operation=p_operation FOR UPDATE;
  v_now := clock_timestamp();
  IF NOT FOUND OR v_op.status <> 'PREPARED_DISABLED'
     OR v_op.lease_token IS NOT NULL OR v_op.lease_until IS NOT NULL
     OR v_op.authenticated_at IS NOT NULL OR v_op.id_device IS NOT NULL
     OR v_op.revocation_requested_at IS NOT NULL
     OR NOT EXISTS (SELECT 1 FROM devices.mqtt_preparation_secret s
                   WHERE s.id_mqtt_pairing_operation=p_operation)
     OR NOT EXISTS (
       SELECT 1 FROM devices.device_pairing_session ps
         JOIN auth."user" u ON u.id_user=ps.id_user AND u.status='ACTIVE'
         JOIN homes.home h ON h.id_home=ps.id_home AND h.status='ACTIVE'
                                  AND h.deleted_at IS NULL
         JOIN homes.home_member hm ON hm.id_home=ps.id_home AND hm.id_user=ps.id_user
                                  AND hm.role='OWNER' AND hm.status='ACTIVE'
       WHERE ps.id_device_pairing_session=v_op.id_device_pairing_session
         AND ps.id_user=p_actor AND ps.token_hash::text=p_token_hash
         AND ps.status IN ('DEVICE_IDENTIFIED','WAITING_FOR_MQTT')
         AND ps.expires_at>v_now AND ps.model_code='S4SW-001P16EU'
         AND lower(ps.manufacturer_device_id)=v_op.manufacturer_device_id
     ) THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_ENABLE_NOT_AUTHORIZED';
  END IF;
  -- Mantener la sesión WAITING_FOR_MQTT incluso si el móvil ya la avanzó.
  UPDATE devices.device_pairing_session SET status='WAITING_FOR_MQTT'
    WHERE id_device_pairing_session=v_op.id_device_pairing_session
      AND status='DEVICE_IDENTIFIED' AND expires_at>clock_timestamp();
  UPDATE devices.mqtt_pairing_operation SET status='ENABLE_PENDING',
      retry_at=NULL, last_error_code=NULL
    WHERE id_mqtt_pairing_operation=p_operation AND status='PREPARED_DISABLED';
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_ENABLE_STATE_CHANGED';
  END IF;
  RETURN TRUE;
END $$;
REVOKE ALL ON FUNCTION devices.fn_request_mqtt_enable(uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_request_mqtt_enable(uuid,uuid,text)
  TO smarthome_mqtt_lease_worker;

-- Reclamar UNA sola activación; timeouts no permiten volver a reclamar.
CREATE FUNCTION devices.fn_claim_mqtt_enable(p_operation UUID,p_seconds INTEGER DEFAULT 60)
RETURNS TABLE(operation_id UUID, lease_token UUID, lease_until TIMESTAMPTZ,
  identity_id UUID, username TEXT,client_id TEXT,role_name TEXT)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_op devices.mqtt_pairing_operation%ROWTYPE;
        v_now TIMESTAMPTZ; v_token UUID; v_until TIMESTAMPTZ;
BEGIN
  IF p_operation IS NULL OR p_seconds IS NULL OR p_seconds NOT BETWEEN 30 AND 120 THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='MQTT_ENABLE_LEASE_INVALID';
  END IF;
  SELECT * INTO v_op FROM devices.mqtt_pairing_operation
    WHERE id_mqtt_pairing_operation=p_operation FOR UPDATE;
  v_now:=clock_timestamp();
  IF NOT FOUND OR v_op.status <> 'ENABLE_PENDING'
     OR v_op.lease_token IS NOT NULL OR v_op.lease_until IS NOT NULL
     OR v_op.authenticated_at IS NOT NULL OR v_op.id_device IS NOT NULL
     OR v_op.revocation_requested_at IS NOT NULL
     OR v_op.attempt_count >= 2147483647
     OR NOT EXISTS (
       SELECT 1 FROM devices.device_pairing_session ps
         JOIN auth."user" u ON u.id_user=ps.id_user AND u.status='ACTIVE'
         JOIN homes.home h ON h.id_home=ps.id_home AND h.status='ACTIVE'
                                 AND h.deleted_at IS NULL
         JOIN homes.home_member hm ON hm.id_home=ps.id_home AND hm.id_user=ps.id_user
                                  AND hm.role='OWNER' AND hm.status='ACTIVE'
       WHERE ps.id_device_pairing_session=v_op.id_device_pairing_session
         AND ps.status='WAITING_FOR_MQTT' AND ps.expires_at>v_now
         AND ps.model_code='S4SW-001P16EU'
         AND lower(ps.manufacturer_device_id)=v_op.manufacturer_device_id
     ) THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_ENABLE_NOT_CLAIMABLE';
  END IF;
  v_token:=gen_random_uuid(); v_until:=v_now+make_interval(secs=>p_seconds);
  UPDATE devices.mqtt_pairing_operation
  SET status='ENABLING',lease_token=v_token,lease_until=v_until,
      attempt_count=v_op.attempt_count+1
  WHERE id_mqtt_pairing_operation=p_operation AND status='ENABLE_PENDING';
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MQTT_ENABLE_STATE_CHANGED'; END IF;
  RETURN QUERY SELECT p_operation,v_token,v_until,v_op.id_mqtt_identity,v_op.broker_username::text,
    v_op.broker_client_id::text,v_op.broker_role_name::text;
END $$;
REVOKE ALL ON FUNCTION devices.fn_claim_mqtt_enable(uuid,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_claim_mqtt_enable(uuid,integer)
  TO smarthome_mqtt_lease_worker;

-- El broker debe haberse consultado y verificado fuera de PostgreSQL.
-- Confirma solo estado AWAITING_AUTH, nunca AUTH_VERIFIED/CONNECTED.
CREATE FUNCTION devices.fn_confirm_mqtt_enabled(
  p_operation UUID,p_token UUID,p_username TEXT,p_client_id TEXT,p_role_name TEXT
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_op devices.mqtt_pairing_operation%ROWTYPE;
        v_count INTEGER; v_now TIMESTAMPTZ;
BEGIN
  IF p_operation IS NULL OR p_token IS NULL OR p_username IS NULL
     OR p_client_id IS NULL OR p_role_name IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='MQTT_ENABLE_CONFIRM_ARGUMENT_INVALID';
  END IF;
  SELECT * INTO v_op FROM devices.mqtt_pairing_operation
    WHERE id_mqtt_pairing_operation=p_operation FOR UPDATE;
  v_now:=clock_timestamp();
  IF NOT FOUND OR v_op.status<>'ENABLING'
     OR v_op.lease_token IS DISTINCT FROM p_token
     OR v_op.lease_until IS NULL OR v_op.lease_until<=v_now
     OR v_op.broker_username IS DISTINCT FROM p_username
     OR v_op.broker_client_id IS DISTINCT FROM p_client_id
     OR v_op.broker_role_name IS DISTINCT FROM p_role_name
     OR v_op.authenticated_at IS NOT NULL OR v_op.id_device IS NOT NULL
     OR v_op.revocation_requested_at IS NOT NULL
     OR NOT EXISTS (
       SELECT 1 FROM devices.device_pairing_session ps
         JOIN auth."user" u ON u.id_user=ps.id_user AND u.status='ACTIVE'
         JOIN homes.home h ON h.id_home=ps.id_home AND h.status='ACTIVE'
                                  AND h.deleted_at IS NULL
         JOIN homes.home_member hm ON hm.id_home=ps.id_home AND hm.id_user=ps.id_user
                                  AND hm.role='OWNER' AND hm.status='ACTIVE'
       WHERE ps.id_device_pairing_session=v_op.id_device_pairing_session
         AND ps.status='WAITING_FOR_MQTT' AND ps.expires_at>v_now
         AND lower(ps.manufacturer_device_id)=v_op.manufacturer_device_id
     ) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MQTT_ENABLE_CONFIRM_FENCE_REJECTED';
  END IF;
  UPDATE devices.mqtt_pairing_operation
    SET status='AWAITING_AUTH',lease_token=NULL,lease_until=NULL,
        retry_at=NULL,last_error_code=NULL
    WHERE id_mqtt_pairing_operation=p_operation AND status='ENABLING'
      AND lease_token=p_token AND lease_until>clock_timestamp();
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MQTT_ENABLE_CONFIRM_FENCE_REJECTED';
  END IF;
  RETURN TRUE;
END $$;
REVOKE ALL ON FUNCTION devices.fn_confirm_mqtt_enabled(uuid,uuid,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_confirm_mqtt_enabled(uuid,uuid,text,text,text)
  TO smarthome_mqtt_lease_worker;

COMMENT ON FUNCTION devices.fn_confirm_mqtt_enabled(uuid,uuid,text,text,text) IS
 'Solo confirmación estructural de enableClient verificada fuera de SQL. NO es prueba MQTT autenticada.';
