-- SmartHome HU16 / SQL029 (propuesta, NO ejecutada).
-- Confirmación limitada tras prueba MQTT validada por un WORKER DE CONFIANZA.
-- La BD no observa el broker; los argumentos NO son evidencia por si mismos.
-- No instalar hasta que exista la infraestructura para gestionar el nuevo rol.
-- No modifica las migraciones 019-028, ni contraseñas MQTT ni identidades.

DO $$
BEGIN
  IF to_regclass('devices.mqtt_pairing_operation') IS NULL
    OR to_regclass('devices.mqtt_rpc_challenge') IS NULL
    OR to_regclass('devices.device_pairing_session') IS NULL
    OR to_regclass('devices.mqtt_pairing_state_event') IS NULL
    OR to_regprocedure('devices.fn_consume_mqtt_rpc_candidate(uuid,uuid)') IS NULL
    OR to_regprocedure('devices.fn_register_mqtt_identity(uuid,uuid,text)') IS NULL
    OR to_regprocedure('auth.fn_current_user_id()') IS NULL
    OR to_regprocedure('devices.fn_confirm_mqtt_pairing_prepared(uuid,uuid,uuid,text,text,text)') IS NULL
    OR to_regclass('devices.mqtt_broker_auth_attestation') IS NOT NULL
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='smarthome_mqtt_auth_confirmer')
    OR EXISTS (SELECT 1 FROM devices.mqtt_pairing_operation
               WHERE status IN ('AUTH_VERIFIED','ATTACHED'))
  THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='MQTT_029_PREREQUISITES_NOT_MET';
  END IF;
END;
$$;

-- Nueva identidad de base de datos sin posibilidad de LOGIN propia.
-- NUNCA se añade este permiso a smarthome_runtime_app, smarthome_worker o
-- a los roles SQL022/025/026/027/028.
CREATE ROLE smarthome_mqtt_auth_confirmer NOLOGIN NOINHERIT
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT USAGE ON SCHEMA devices TO smarthome_mqtt_auth_confirmer;

CREATE TABLE devices.mqtt_broker_auth_attestation (
  id_mqtt_pairing_operation UUID PRIMARY KEY REFERENCES
    devices.mqtt_pairing_operation(id_mqtt_pairing_operation) ON DELETE RESTRICT,
  rpc_id UUID NOT NULL UNIQUE REFERENCES devices.mqtt_rpc_challenge(rpc_id)
    ON DELETE RESTRICT,
  observed_username VARCHAR(128) NOT NULL,
  observed_client_id VARCHAR(128) NOT NULL,
  observed_role_name VARCHAR(128) NOT NULL,
  confirmed_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT ck_mqtt_auth_observed_names CHECK (
    observed_username ~ '^[A-Za-z0-9_-]{1,128}$' AND
    observed_client_id ~ '^[A-Za-z0-9_-]{1,128}$' AND
    observed_role_name ~ '^[A-Za-z0-9_-]{1,128}$'
  )
);
ALTER TABLE devices.mqtt_broker_auth_attestation ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE devices.mqtt_broker_auth_attestation FROM PUBLIC;
COMMENT ON TABLE devices.mqtt_broker_auth_attestation IS
  'Auditoria inmutable de una comprobacion realizada fuera de PostgreSQL por un worker aislado; NO constituye por si sola prueba criptografica del broker.';

CREATE FUNCTION devices.fn_block_mqtt_auth_attestation_mutation()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path=pg_catalog,pg_temp AS $$
BEGIN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MQTT_AUTH_ATTESTATION_IMMUTABLE';
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_block_mqtt_auth_attestation_mutation() FROM PUBLIC;
CREATE TRIGGER trg_block_mqtt_auth_attestation_mutation
  BEFORE UPDATE OR DELETE ON devices.mqtt_broker_auth_attestation
  FOR EACH ROW EXECUTE FUNCTION devices.fn_block_mqtt_auth_attestation_mutation();

-- Los permisos de UPDATE que SQL019 otorgó a smarthome_runtime_app NO pueden
-- por si solos convertir WAITING_FOR_MQTT en CONNECTED ni cerrar COMPLETED.
-- ATTACHED es requisito para completar; evita crear un device sin asociar
-- devices.mqtt_identity y mqtt_pairing_operation al registro definitivo.
CREATE FUNCTION devices.fn_guard_mqtt_pairing_session_verified()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path=pg_catalog,pg_temp AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status = 'CONNECTED' AND NOT EXISTS (
      SELECT 1 FROM devices.mqtt_pairing_operation o
      JOIN devices.mqtt_broker_auth_attestation a
        ON a.id_mqtt_pairing_operation=o.id_mqtt_pairing_operation
      JOIN devices.mqtt_rpc_challenge c ON c.rpc_id=a.rpc_id
      WHERE o.id_device_pairing_session=NEW.id_device_pairing_session
        AND o.status IN ('AUTH_VERIFIED','ATTACHED')
        AND o.authenticated_at IS NOT NULL
        AND c.id_mqtt_pairing_operation=o.id_mqtt_pairing_operation
        AND c.consumed_at IS NOT NULL AND c.invalidated_at IS NULL
        AND lower(o.manufacturer_device_id)=lower(NEW.manufacturer_device_id)
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_SESSION_CONNECTED_REQUIRES_BROKER_ATTESTATION';
    END IF;
    IF NEW.status = 'COMPLETED' AND NOT EXISTS (
      SELECT 1 FROM devices.mqtt_pairing_operation o
      JOIN devices.mqtt_broker_auth_attestation a
        ON a.id_mqtt_pairing_operation=o.id_mqtt_pairing_operation
      WHERE o.id_device_pairing_session=NEW.id_device_pairing_session
        AND o.status='ATTACHED'
        AND o.id_device=NEW.completed_device_id
        AND o.authenticated_at IS NOT NULL
        AND lower(o.manufacturer_device_id)=lower(NEW.manufacturer_device_id)
    ) THEN
      RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MQTT_SESSION_COMPLETED_REQUIRES_ATTACHED_IDENTITY';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_guard_mqtt_pairing_session_verified() FROM PUBLIC;
CREATE TRIGGER trg_guard_mqtt_pairing_session_verified
  BEFORE UPDATE ON devices.device_pairing_session
  FOR EACH ROW EXECUTE FUNCTION devices.fn_guard_mqtt_pairing_session_verified();

-- La función solo verifica hechos SQL y registra el aval del worker aislado.
-- OBLIGACIÓN EXTERNA del worker ANTES de invocar:
--   1. broker TLS verificado + getClient autenticado/fresco;
--   2. respuesta RPC del Shelly correcta, no retenida y vinculada a rpc_id;
--   3. broker clientId/username/ACL iguales a la reserva;
--   4. sesión de propietario vigente y prueba sin resultado incierto.
-- La función NO recibe contraseñas y NO crea devices.device.
CREATE FUNCTION devices.fn_confirm_mqtt_broker_authentication(
  p_operation UUID, p_rpc_id UUID,
  p_username TEXT, p_client_id TEXT, p_role_name TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE
  v_op devices.mqtt_pairing_operation%ROWTYPE;
  v_challenge devices.mqtt_rpc_challenge%ROWTYPE;
  v_now TIMESTAMPTZ;
  v_affected INTEGER;
BEGIN
  IF p_operation IS NULL OR p_rpc_id IS NULL
    OR p_username IS NULL OR p_client_id IS NULL OR p_role_name IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='MQTT_AUTH_CONFIRM_ARGUMENTS_REQUIRED';
  END IF;

  SELECT * INTO v_op FROM devices.mqtt_pairing_operation
    WHERE id_mqtt_pairing_operation=p_operation FOR UPDATE;
  v_now := clock_timestamp();
  IF NOT FOUND
    OR v_op.status <> 'AWAITING_AUTH'
    OR v_op.authenticated_at IS NOT NULL
    OR v_op.id_device IS NOT NULL
    OR v_op.lease_token IS NOT NULL
    OR v_op.broker_username IS DISTINCT FROM p_username
    OR v_op.broker_client_id IS DISTINCT FROM p_client_id
    OR v_op.broker_role_name IS DISTINCT FROM p_role_name
    OR NOT EXISTS (
      SELECT 1 FROM devices.device_pairing_session ps
      JOIN auth."user" u ON u.id_user=ps.id_user AND u.status='ACTIVE'
      JOIN homes.home h ON h.id_home=ps.id_home AND h.status='ACTIVE'
         AND h.deleted_at IS NULL
      JOIN homes.home_member hm ON hm.id_home=ps.id_home
         AND hm.id_user=ps.id_user AND hm.role='OWNER' AND hm.status='ACTIVE'
      WHERE ps.id_device_pairing_session=v_op.id_device_pairing_session
        AND ps.status='WAITING_FOR_MQTT' AND ps.expires_at>v_now
        AND ps.model_code='S4SW-001P16EU'
        AND lower(ps.manufacturer_device_id)=v_op.manufacturer_device_id
    ) THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_AUTH_CONFIRM_FENCE_REJECTED';
  END IF;

  SELECT * INTO v_challenge FROM devices.mqtt_rpc_challenge c
    WHERE c.rpc_id=p_rpc_id AND c.id_mqtt_pairing_operation=p_operation
    FOR SHARE;
  IF NOT FOUND OR v_challenge.consumed_at IS NULL
    OR v_challenge.invalidated_at IS NOT NULL
    OR v_challenge.consumed_at < v_challenge.issued_at
    OR v_challenge.consumed_at >= v_challenge.expires_at
    OR v_challenge.consumed_at > v_now
    OR v_challenge.consumed_at < v_now - INTERVAL '30 seconds'
    OR EXISTS (SELECT 1 FROM devices.mqtt_broker_auth_attestation
                WHERE rpc_id=p_rpc_id OR id_mqtt_pairing_operation=p_operation)
  THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_AUTH_RPC_NOT_FRESH_CONSUMED';
  END IF;

  INSERT INTO devices.mqtt_broker_auth_attestation (
    id_mqtt_pairing_operation,rpc_id,observed_username,observed_client_id,
    observed_role_name,confirmed_at
  ) VALUES (p_operation,p_rpc_id,p_username,p_client_id,p_role_name,v_now);

  UPDATE devices.mqtt_pairing_operation
  SET status='AUTH_VERIFIED',authenticated_at=v_now
  WHERE id_mqtt_pairing_operation=p_operation AND status='AWAITING_AUTH'
    AND authenticated_at IS NULL AND id_device IS NULL;
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 1 THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MQTT_AUTH_OPERATION_CHANGED';
  END IF;

  UPDATE devices.device_pairing_session
  SET status='CONNECTED'
  WHERE id_device_pairing_session=v_op.id_device_pairing_session
    AND status='WAITING_FOR_MQTT' AND expires_at>clock_timestamp();
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 1 THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='MQTT_AUTH_SESSION_CHANGED';
  END IF;
  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_confirm_mqtt_broker_authentication(UUID,UUID,TEXT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_confirm_mqtt_broker_authentication(UUID,UUID,TEXT,TEXT,TEXT)
  TO smarthome_mqtt_auth_confirmer;
COMMENT ON FUNCTION devices.fn_confirm_mqtt_broker_authentication(UUID,UUID,TEXT,TEXT,TEXT) IS
  'Transaccion atomica AWAITING_AUTH -> AUTH_VERIFIED + WAITING_FOR_MQTT -> CONNECTED solo para un worker de confianza. PostgreSQL no observa ni autentica MQTT: el worker debe probarlo antes y no exponer el EXECUTE al HTTP.';


-- Completa en una sola transaccion existente de Prisma:
--   1) device se crea previamente en la misma transaccion;
--   2) esta funcion registra mqtt_identity, asocia operacion y cierra sesion;
--   3) cualquier error deshace la creacion previa de device.
-- La funcion NO confia en un userId procedente del movil. El propietario
-- proviene del contexto de RLS que establece PrismaRlsService.
CREATE FUNCTION devices.fn_finish_verified_pairing(
  p_session UUID, p_device UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE
  v_ps devices.device_pairing_session%ROWTYPE;
  v_op devices.mqtt_pairing_operation%ROWTYPE;
  v_device devices.device%ROWTYPE;
  v_count INTEGER;
BEGIN
  IF p_session IS NULL OR p_device IS NULL OR auth.fn_current_user_id() IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_FINISH_ACTOR_REQUIRED';
  END IF;
  SELECT * INTO v_ps FROM devices.device_pairing_session
  WHERE id_device_pairing_session=p_session FOR UPDATE;
  IF NOT FOUND OR v_ps.status <> 'CONNECTED' OR v_ps.expires_at<=clock_timestamp()
    OR v_ps.completed_device_id IS NOT NULL
    OR v_ps.id_user IS DISTINCT FROM auth.fn_current_user_id()
    OR NOT homes.fn_can_manage_home(v_ps.id_home)
    OR v_ps.model_code <> 'S4SW-001P16EU'
    OR v_ps.manufacturer_device_id IS NULL
  THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_FINISH_SESSION_NOT_AUTHORIZED';
  END IF;

  SELECT * INTO v_device FROM devices.device
  WHERE id_device=p_device FOR UPDATE;
  IF NOT FOUND OR v_device.id_home IS DISTINCT FROM v_ps.id_home
    OR lower(v_device.manufacturer_device_id) IS DISTINCT FROM lower(v_ps.manufacturer_device_id)
    OR v_device.status <> 'ACTIVE' OR v_device.deleted_at IS NOT NULL
    OR v_device.messaging_protocol IS DISTINCT FROM 'MQTT'
  THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_FINISH_DEVICE_MISMATCH';
  END IF;

  SELECT * INTO v_op FROM devices.mqtt_pairing_operation
  WHERE id_device_pairing_session=p_session FOR UPDATE;
  IF NOT FOUND OR v_op.status <> 'AUTH_VERIFIED' OR v_op.id_device IS NOT NULL
    OR v_op.authenticated_at IS NULL
    OR lower(v_op.manufacturer_device_id) <> lower(v_ps.manufacturer_device_id)
    OR NOT EXISTS (
      SELECT 1 FROM devices.mqtt_broker_auth_attestation a
      WHERE a.id_mqtt_pairing_operation=v_op.id_mqtt_pairing_operation
        AND a.observed_username=v_op.broker_username
        AND a.observed_client_id=v_op.broker_client_id
        AND a.observed_role_name=v_op.broker_role_name
    )
  THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_FINISH_BROKER_NOT_CONFIRMED';
  END IF;

  PERFORM devices.fn_register_mqtt_identity(
    p_device, v_op.id_mqtt_identity, v_op.manufacturer_device_id::text
  );
  UPDATE devices.mqtt_pairing_operation
    SET status='ATTACHED',id_device=p_device
    WHERE id_mqtt_pairing_operation=v_op.id_mqtt_pairing_operation
      AND status='AUTH_VERIFIED' AND id_device IS NULL;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_FINISH_OPERATION_CHANGED';
  END IF;

  UPDATE devices.device_pairing_session
    SET status='COMPLETED',completed_device_id=p_device
    WHERE id_device_pairing_session=p_session
      AND status='CONNECTED' AND expires_at>clock_timestamp();
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN
    RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='MQTT_FINISH_SESSION_CHANGED';
  END IF;
  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_finish_verified_pairing(UUID,UUID) FROM PUBLIC;
-- smarthome_runtime_app puede ejecutar SOLO esta operacion acotada, bajo contexto RLS;
-- no recibe permiso sobre mqtt_identity, pairing_operation ni attestation.
GRANT EXECUTE ON FUNCTION devices.fn_finish_verified_pairing(UUID,UUID)
  TO smarthome_runtime_app;
COMMENT ON FUNCTION devices.fn_finish_verified_pairing(UUID,UUID) IS
 'Cierre atomico con verificaciones de OWNER, operacion autenticada y auditoria. Usar dentro de la misma transaccion Prisma que crea device.';
