-- Rollback of SQL030: remove the MQTT enable fencing functions.
-- Rows already moved to ENABLE_PENDING/WAITING_FOR_MQTT keep their state;
-- review them manually before re-running SQL030.
DROP FUNCTION IF EXISTS devices.fn_confirm_mqtt_enabled(uuid, uuid, text, text, text);
DROP FUNCTION IF EXISTS devices.fn_claim_mqtt_enable(uuid, integer);
DROP FUNCTION IF EXISTS devices.fn_request_mqtt_enable(uuid, uuid, text);
