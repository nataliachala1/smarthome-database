ALTER TABLE devices.device
DROP CONSTRAINT IF EXISTS ck_device_lifecycle;

ALTER TABLE devices.device
ADD CONSTRAINT ck_device_lifecycle
CHECK (
    (status = 'ACTIVE' AND deleted_at IS NULL)
    OR
    (status = 'DEACTIVATED' AND deleted_at IS NOT NULL)
);