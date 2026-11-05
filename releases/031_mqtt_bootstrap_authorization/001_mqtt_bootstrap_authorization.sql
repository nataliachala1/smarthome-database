-- SmartHome SQL031: recuperacion autorizada del sobre cifrado YA preparado.
-- No contiene plaintext, contrasenas, claves, DML directo por runtime ni habilitacion MQTT.
-- SOLO con JWT OWNER validado en NestJS + hash del X-Pairing-Token.
DO $$ BEGIN
 IF to_regclass('devices.mqtt_preparation_secret') IS NULL
    OR to_regprocedure('devices.fn_load_mqtt_preparation_secret(uuid,uuid)') IS NULL
    OR to_regprocedure('devices.fn_request_mqtt_enable(uuid,uuid,text)') IS NULL
    OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='smarthome_mqtt_secret_worker')
    OR to_regprocedure('devices.fn_get_authorized_mqtt_bootstrap(uuid,uuid,text)') IS NOT NULL
 THEN RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='MQTT_031_PREREQUISITES_NOT_MET'; END IF;
END $$;

-- Solo almacena metadatos de entregas, no tokens ni secretos. No acceso cliente.
CREATE TABLE devices.mqtt_bootstrap_delivery_audit (
  id_mqtt_pairing_operation uuid PRIMARY KEY
     REFERENCES devices.mqtt_pairing_operation(id_mqtt_pairing_operation) ON DELETE RESTRICT,
  delivery_count integer NOT NULL DEFAULT 0 CHECK (delivery_count BETWEEN 0 AND 3),
  first_delivered_at timestamptz,
  last_delivered_at timestamptz,
  CONSTRAINT ck_bootstrap_delivery_dates CHECK (
    (delivery_count=0 AND first_delivered_at IS NULL AND last_delivered_at IS NULL)
    OR (delivery_count>0 AND first_delivered_at IS NOT NULL AND last_delivered_at IS NOT NULL)
  )
);
REVOKE ALL ON devices.mqtt_bootstrap_delivery_audit FROM PUBLIC;
ALTER TABLE devices.mqtt_bootstrap_delivery_audit ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE devices.mqtt_bootstrap_delivery_audit IS
  'Maximo tres lecturas autorizadas de sobre cifrado durante sesion activa. Nunca almacena tokens, JWT, CA privada ni password.';

CREATE FUNCTION devices.fn_get_authorized_mqtt_bootstrap(
  p_operation uuid, p_actor uuid, p_token_hash text
) RETURNS TABLE(operation_id uuid, identity_id uuid, manufacturer_device_id text,
  broker_username text, broker_client_id text, topic_scope text,
  format_version smallint, key_id text, nonce text, ciphertext text, auth_tag text,
  expires_at timestamptz)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE v_op devices.mqtt_pairing_operation%ROWTYPE;
        v_session devices.device_pairing_session%ROWTYPE;
        v_count integer;
        v_now timestamptz;
BEGIN
  IF p_operation IS NULL OR p_actor IS NULL OR p_token_hash IS NULL OR
     p_token_hash !~ '^[a-f0-9]{64}$' THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='MQTT_BOOTSTRAP_INVALID_ARGS';
  END IF;
  SELECT * INTO v_op FROM devices.mqtt_pairing_operation
    WHERE id_mqtt_pairing_operation=p_operation FOR UPDATE;
  v_now:=clock_timestamp();
  IF NOT FOUND OR v_op.status <> 'PREPARED_DISABLED' OR
     v_op.id_device IS NOT NULL OR v_op.authenticated_at IS NOT NULL OR
     v_op.lease_token IS NOT NULL OR v_op.lease_until IS NOT NULL OR
     v_op.revocation_requested_at IS NOT NULL OR v_op.revoked_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_BOOTSTRAP_OPERATION_UNAVAILABLE';
  END IF;
  SELECT * INTO v_session FROM devices.device_pairing_session
    WHERE id_device_pairing_session=v_op.id_device_pairing_session FOR SHARE;
  IF NOT FOUND OR v_session.id_user IS DISTINCT FROM p_actor OR
     v_session.token_hash::text IS DISTINCT FROM p_token_hash OR
     v_session.status NOT IN ('DEVICE_IDENTIFIED','WAITING_FOR_MQTT') OR
     v_session.expires_at <= v_now OR
     v_session.model_code IS DISTINCT FROM 'S4SW-001P16EU' OR
     lower(v_session.manufacturer_device_id) IS DISTINCT FROM v_op.manufacturer_device_id OR
     NOT EXISTS (SELECT 1 FROM auth."user" u
       JOIN homes.home_member hm ON hm.id_user=u.id_user
       JOIN homes.home h ON h.id_home=hm.id_home
       WHERE u.id_user=p_actor AND u.status='ACTIVE'
         AND hm.id_home=v_session.id_home AND hm.status='ACTIVE' AND hm.role='OWNER'
         AND h.status='ACTIVE' AND h.deleted_at IS NULL) THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_BOOTSTRAP_SESSION_UNAUTHORIZED';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM devices.mqtt_preparation_secret s
      WHERE s.id_mqtt_pairing_operation=p_operation) THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_BOOTSTRAP_SECRET_MISSING';
  END IF;
  -- Auditar el acceso EN LA MISMA transaccion y limitar recuperaciones.
  INSERT INTO devices.mqtt_bootstrap_delivery_audit(id_mqtt_pairing_operation,delivery_count,
      first_delivered_at,last_delivered_at) VALUES(p_operation,1,v_now,v_now)
    ON CONFLICT(id_mqtt_pairing_operation) DO UPDATE SET
      delivery_count=devices.mqtt_bootstrap_delivery_audit.delivery_count+1,
      last_delivered_at=v_now
    WHERE devices.mqtt_bootstrap_delivery_audit.delivery_count<3
    RETURNING delivery_count INTO v_count;
  IF v_count IS NULL OR v_count NOT BETWEEN 1 AND 3 THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_BOOTSTRAP_DELIVERY_LIMIT';
  END IF;
  RETURN QUERY SELECT v_op.id_mqtt_pairing_operation, v_op.id_mqtt_identity,
    v_op.manufacturer_device_id::text, v_op.broker_username::text,
    v_op.broker_client_id::text,v_op.topic_scope::text,
    s.format_version,s.key_id::text,s.nonce::text,s.ciphertext::text,s.auth_tag::text,
    v_session.expires_at
  FROM devices.mqtt_preparation_secret s
  WHERE s.id_mqtt_pairing_operation=p_operation;
END $$;
REVOKE ALL ON FUNCTION devices.fn_get_authorized_mqtt_bootstrap(uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_get_authorized_mqtt_bootstrap(uuid,uuid,text)
  TO smarthome_mqtt_secret_worker;
COMMENT ON FUNCTION devices.fn_get_authorized_mqtt_bootstrap(uuid,uuid,text) IS
  'Devuelve SOLO sobre AES-GCM con fencing de OWNER + token y 3 lecturas maximas. TLS/red confiable son obligacion del backend/mobile.';
