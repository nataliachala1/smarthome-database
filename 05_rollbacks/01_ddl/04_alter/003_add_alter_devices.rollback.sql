ALTER TABLE devices.device_telemetry_raw DROP CONSTRAINT IF EXISTS fk_device_telemetry_raw_device;
ALTER TABLE devices.device_schedule DROP CONSTRAINT IF EXISTS fk_device_schedule_device;
ALTER TABLE devices.smart_device DROP CONSTRAINT IF EXISTS fk_smart_device_device;
ALTER TABLE devices.device
  DROP CONSTRAINT IF EXISTS uq_device_id_home,
  DROP CONSTRAINT IF EXISTS fk_device_type;
