-- ============================================================
-- Align device lifecycle with current SmartHome scope.
--
-- ACTIVE:
--   deleted_at must be NULL.
--
-- DEACTIVATED:
--   deleted_at NULL     -> inactive device.
--   deleted_at NOT NULL -> soft-deleted device.
-- ============================================================

ALTER TABLE devices.device
DROP CONSTRAINT IF EXISTS ck_device_lifecycle;

ALTER TABLE devices.device
ADD CONSTRAINT ck_device_lifecycle
CHECK (
    (status = 'ACTIVE' AND deleted_at IS NULL)
    OR
    status = 'DEACTIVATED'
);