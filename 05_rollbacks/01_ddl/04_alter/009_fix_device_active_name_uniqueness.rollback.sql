DROP INDEX IF EXISTS devices.uq_device_name;

ALTER TABLE devices.device
ADD CONSTRAINT uq_device_name
UNIQUE (id_home, name);