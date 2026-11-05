ALTER TABLE devices.device
DROP CONSTRAINT uq_device_name;

CREATE UNIQUE INDEX uq_device_name
ON devices.device (id_home, name)
WHERE deleted_at IS NULL;