-- Fail-closed rollback. Do not remove a transition function while operations
-- may have passed through it; even REVOKED operations retain audit history.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM devices.mqtt_pairing_operation) THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'MQTT_027_ROLLBACK_BLOCKED_BY_PAIRING_HISTORY';
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION devices.fn_confirm_mqtt_pairing_prepared(UUID,UUID,UUID,TEXT,TEXT,TEXT)
  FROM smarthome_mqtt_prepare_confirmer;
DROP FUNCTION devices.fn_confirm_mqtt_pairing_prepared(UUID,UUID,UUID,TEXT,TEXT,TEXT);
REVOKE USAGE ON SCHEMA devices FROM smarthome_mqtt_prepare_confirmer;
DROP ROLE smarthome_mqtt_prepare_confirmer;
