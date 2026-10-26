-- SmartHome HU16 SQL028 - propuesta 503.29 CON FENCING.
-- NO EJECUTAR EN PRODUCCION. Mantener separada hasta la validacion Liquibase.
-- Protege lectura e insercion con el lease_token de SQL025 (sin confiar en el runtime normal).
-- No guarda password plaintext ni material de claves. No crea roles LOGIN ni endpoints.
DO $$
BEGIN
  IF to_regclass('devices.mqtt_pairing_operation') IS NULL
     OR to_regclass('devices.mqtt_preparation_secret') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_catalog.pg_roles
                WHERE rolname = 'smarthome_mqtt_secret_worker')
  THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'MQTT_028_PREREQUISITES_NOT_MET';
  END IF;
END;
$$;

CREATE ROLE smarthome_mqtt_secret_worker NOLOGIN NOINHERIT
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT USAGE ON SCHEMA devices TO smarthome_mqtt_secret_worker;

CREATE TABLE devices.mqtt_preparation_secret (
  id_mqtt_pairing_operation UUID PRIMARY KEY
    REFERENCES devices.mqtt_pairing_operation(id_mqtt_pairing_operation) ON DELETE RESTRICT,
  format_version SMALLINT NOT NULL,
  key_id VARCHAR(64) NOT NULL,
  nonce VARCHAR(16) NOT NULL,
  ciphertext VARCHAR(58) NOT NULL,
  auth_tag VARCHAR(22) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT ck_mqtt_secret_format CHECK (format_version = 1),
  CONSTRAINT ck_mqtt_secret_key_id CHECK (key_id ~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$'),
  CONSTRAINT ck_mqtt_secret_nonce CHECK (nonce ~ '^[A-Za-z0-9_-]{16}$'),
  CONSTRAINT ck_mqtt_secret_payload CHECK (ciphertext ~ '^[A-Za-z0-9_-]{58}$'),
  CONSTRAINT ck_mqtt_secret_tag CHECK (auth_tag ~ '^[A-Za-z0-9_-]{22}$')
);
REVOKE ALL ON TABLE devices.mqtt_preparation_secret FROM PUBLIC;
ALTER TABLE devices.mqtt_preparation_secret ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE devices.mqtt_preparation_secret IS
  'Immutable AES-GCM envelope por operacion MQTT, sin plaintext ni clave. Lectura/insercion requieren lease SQL025 cercado.';

-- La lectura tambien requiere el lease ACTUAL: un worker obsoleto no puede
-- extraer contrasenas tras perder su token. Se bloquea la fila hasta fin de tx.
CREATE FUNCTION devices.fn_load_mqtt_preparation_secret(
  p_operation UUID, p_lease_token UUID
)
RETURNS TABLE(operation_id UUID, format_version SMALLINT, key_id TEXT,
  nonce TEXT, ciphertext TEXT, auth_tag TEXT)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF p_operation IS NULL OR p_lease_token IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'MQTT_SECRET_OPERATION_OR_LEASE_INVALID';
  END IF;
  PERFORM 1 FROM devices.mqtt_pairing_operation o
  WHERE o.id_mqtt_pairing_operation = p_operation
    AND o.status = 'PREPARING'
    AND o.lease_token = p_lease_token
    AND o.lease_until > clock_timestamp()
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'MQTT_SECRET_LEASE_NOT_CURRENT';
  END IF;
  RETURN QUERY
  SELECT s.id_mqtt_pairing_operation, s.format_version,
    s.key_id::text, s.nonce::text, s.ciphertext::text, s.auth_tag::text
  FROM devices.mqtt_preparation_secret s
  WHERE s.id_mqtt_pairing_operation = p_operation;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_load_mqtt_preparation_secret(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_load_mqtt_preparation_secret(UUID, UUID)
  TO smarthome_mqtt_secret_worker;

-- Lock FOR SHARE impide rotacion concurrente del lease entre la verificacion
-- y el INSERT. No guardar ni sobrescribir secretos desde un worker obsoleto.
CREATE FUNCTION devices.fn_insert_mqtt_preparation_secret_if_absent(
  p_operation UUID, p_lease_token UUID, p_format SMALLINT, p_key_id TEXT,
  p_nonce TEXT, p_ciphertext TEXT, p_tag TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_count BIGINT;
BEGIN
  IF p_operation IS NULL OR p_lease_token IS NULL
     OR p_format IS DISTINCT FROM 1 OR p_key_id IS NULL
     OR p_nonce IS NULL OR p_ciphertext IS NULL OR p_tag IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023',
      MESSAGE = 'MQTT_SECRET_ENVELOPE_ARGUMENTS_INVALID';
  END IF;

  PERFORM 1 FROM devices.mqtt_pairing_operation o
  WHERE o.id_mqtt_pairing_operation = p_operation
    AND o.status = 'PREPARING'
    AND o.lease_token = p_lease_token
    AND o.lease_until > clock_timestamp()
  FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '23514',
      MESSAGE = 'MQTT_SECRET_LEASE_NOT_CURRENT';
  END IF;

  INSERT INTO devices.mqtt_preparation_secret (
    id_mqtt_pairing_operation, format_version, key_id,
    nonce, ciphertext, auth_tag
  ) VALUES (p_operation, p_format, p_key_id,
    p_nonce, p_ciphertext, p_tag)
  ON CONFLICT (id_mqtt_pairing_operation) DO NOTHING;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count = 1;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_insert_mqtt_preparation_secret_if_absent(
  UUID, UUID, SMALLINT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_insert_mqtt_preparation_secret_if_absent(
  UUID, UUID, SMALLINT, TEXT, TEXT, TEXT, TEXT) TO smarthome_mqtt_secret_worker;

COMMENT ON ROLE smarthome_mqtt_secret_worker IS
  'NOLOGIN: SOLO leer/insertar sobres cifrados de operacion MQTT con fencing actual. Sin acceso CRUD directo ni clave AES.';
