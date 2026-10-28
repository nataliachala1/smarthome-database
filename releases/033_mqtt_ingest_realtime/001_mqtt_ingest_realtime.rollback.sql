REVOKE EXECUTE ON FUNCTION
homes.fn_mqtt_realtime_recipients(UUID, UUID)
FROM smarthome_ingest;

DROP FUNCTION homes.fn_mqtt_realtime_recipients(UUID, UUID);

REVOKE SELECT (id_home)
ON consumption.consumption
FROM smarthome_ingest;