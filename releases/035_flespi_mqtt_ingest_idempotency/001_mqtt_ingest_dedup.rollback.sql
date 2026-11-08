-- SQL035: explicitly destructive operation; it loses the history of
-- processed identities. Do not roll back an active DEV environment without a backup.
DROP TABLE IF EXISTS consumption.mqtt_ingest_dedup;
