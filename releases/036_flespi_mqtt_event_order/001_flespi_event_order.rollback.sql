-- Revert only SQL036; SQL035 ledger and data are preserved.
DROP INDEX IF EXISTS consumption.idx_mqtt_ingest_dedup_device_event_ts;
REVOKE SELECT (device_event_ts)
    ON TABLE consumption.mqtt_ingest_dedup
    FROM smarthome_ingest;
