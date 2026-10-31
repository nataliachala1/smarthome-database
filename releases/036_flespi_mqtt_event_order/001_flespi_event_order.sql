-- SQL036: allow the MQTT ingestion role to compare Shelly origin timestamps.
-- SQL035 already enforces unique (id_device,event_key) and RLS.
-- No broad table SELECT grant, no changes to the consumption table or roles.
GRANT SELECT (device_event_ts)
    ON TABLE consumption.mqtt_ingest_dedup
    TO smarthome_ingest;

-- Supports latest-origin-timestamp lookups for a single active device.
CREATE INDEX idx_mqtt_ingest_dedup_device_event_ts
    ON consumption.mqtt_ingest_dedup (id_device, device_event_ts DESC);
