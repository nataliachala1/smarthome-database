-- ============================================================
-- Devices: last seen timestamp for MQTT/offline detection
-- ============================================================

ALTER TABLE devices.device
ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ NULL;

GRANT SELECT (last_seen_at)
ON devices.device
TO smarthome_app;

GRANT SELECT (last_seen_at), UPDATE (last_seen_at)
ON devices.device
TO smarthome_ingest;

CREATE INDEX IF NOT EXISTS idx_device_connectivity_last_seen
ON devices.device (connectivity_status, last_seen_at)
WHERE status = 'ACTIVE'
  AND deleted_at IS NULL;