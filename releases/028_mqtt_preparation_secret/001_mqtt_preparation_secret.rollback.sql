-- SOLO laboratorio y previa revision. NUNCA borrar secretos cifrados activos.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM devices.mqtt_preparation_secret) THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'MQTT_028_ROLLBACK_BLOCKED_NONEMPTY_SECRET_STORE';
  END IF;
END;
$$;
DROP FUNCTION devices.fn_insert_mqtt_preparation_secret_if_absent(
  UUID, UUID, SMALLINT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION devices.fn_load_mqtt_preparation_secret(UUID, UUID);
DROP TABLE devices.mqtt_preparation_secret;
REVOKE USAGE ON SCHEMA devices FROM smarthome_mqtt_secret_worker;
DROP ROLE smarthome_mqtt_secret_worker;
