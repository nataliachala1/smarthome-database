-- Refuse destructive rollback after this reservation table has real state.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM devices.mqtt_pairing_operation) THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'MQTT_PAIRING_ROLLBACK_BLOCKED_NONEMPTY';
  END IF;
END;
$$;
DROP FUNCTION devices.fn_reserve_mqtt_pairing_operation(UUID, TEXT, UUID, TEXT);
DROP TABLE devices.mqtt_pairing_operation;
DROP FUNCTION devices.fn_guard_mqtt_pairing_operation_binding();

-- Fail safely if a login has already been attached or other dependencies exist.
REVOKE USAGE ON SCHEMA devices FROM smarthome_mqtt_reserver;
DROP ROLE smarthome_mqtt_reserver;
