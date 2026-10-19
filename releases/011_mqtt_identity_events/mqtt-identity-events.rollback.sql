-- Never discard observations or committed transition history automatically.
-- Run transactionally, as Liquibase does; exclude concurrent event insertion.
SET LOCAL lock_timeout = '5s';
LOCK TABLE devices.mqtt_identity IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE devices.mqtt_identity_event IN ACCESS EXCLUSIVE MODE;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM devices.mqtt_identity_event) THEN
    RAISE EXCEPTION 'MQTT_IDENTITY_HISTORY_ROLLBACK_REQUIRES_EMPTY_HISTORY';
  END IF;
END;
$$;
DROP TRIGGER trg_mqtt_identity_event ON devices.mqtt_identity;
DROP FUNCTION devices.fn_capture_mqtt_identity_event();
DROP TRIGGER trg_mqtt_identity_event_append_only ON devices.mqtt_identity_event;
DROP FUNCTION devices.fn_mqtt_identity_event_append_only();
DROP TABLE devices.mqtt_identity_event;
