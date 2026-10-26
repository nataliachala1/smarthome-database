-- Fail-closed rollback. No historical state events may be discarded.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM devices.mqtt_pairing_state_event)
     OR EXISTS (
       SELECT 1 FROM devices.mqtt_pairing_operation WHERE status <> 'RESERVED'
     ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'MQTT_024_ROLLBACK_BLOCKED_STATE_HISTORY';
  END IF;
END;
$$;

DROP TRIGGER trg_audit_mqtt_pairing_operation_state ON devices.mqtt_pairing_operation;
DROP FUNCTION devices.fn_audit_mqtt_pairing_operation_state();
DROP TRIGGER trg_guard_mqtt_pairing_operation_state ON devices.mqtt_pairing_operation;
DROP FUNCTION devices.fn_guard_mqtt_pairing_operation_state();
DROP TRIGGER trg_guard_mqtt_pairing_state_event ON devices.mqtt_pairing_state_event;
DROP FUNCTION devices.fn_guard_mqtt_pairing_state_event();
DROP TABLE devices.mqtt_pairing_state_event;
