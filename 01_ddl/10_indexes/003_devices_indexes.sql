CREATE INDEX IF NOT EXISTS idx_device_home_status
  ON devices.device(id_home, status);

CREATE INDEX IF NOT EXISTS idx_device_zone_status
  ON devices.device(id_zone, status);

CREATE INDEX IF NOT EXISTS idx_device_type_active
  ON devices.device_type(id_device_type)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_device_schedule_device_active
  ON devices.device_schedule(id_device, time_of_day)
  WHERE is_active = TRUE AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_device_telemetry_raw_device_captured
  ON devices.device_telemetry_raw(id_device, captured_at DESC);
