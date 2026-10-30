-- SQL035: operación explícitamente destructiva; pierde el historial de
-- identidades procesadas. No ejecutar rollback en DEV activo sin respaldo.
DROP TABLE IF EXISTS consumption.mqtt_ingest_dedup;
