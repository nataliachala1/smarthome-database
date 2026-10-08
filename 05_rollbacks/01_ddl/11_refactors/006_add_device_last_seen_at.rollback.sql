DROP INDEX IF EXISTS devices.idx_device_connectivity_last_seen;

REVOKE SELECT (last_seen_at)
ON devices.device
FROM smarthome_app;

REVOKE SELECT (last_seen_at), UPDATE (last_seen_at)
ON devices.device
FROM smarthome_ingest;

ALTER TABLE devices.device
DROP COLUMN IF EXISTS last_seen_at;