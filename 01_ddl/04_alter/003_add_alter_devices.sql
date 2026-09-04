ALTER TABLE devices.device
  ADD CONSTRAINT fk_device_type
    FOREIGN KEY (id_device_type) REFERENCES devices.device_type(id_device_type),
  ADD CONSTRAINT uq_device_id_home
    UNIQUE (id_device, id_home);

ALTER TABLE devices.smart_device
  ADD CONSTRAINT fk_smart_device_device
  FOREIGN KEY (id_device) REFERENCES devices.device(id_device);

ALTER TABLE devices.device_schedule
  ADD CONSTRAINT fk_device_schedule_device
  FOREIGN KEY (id_device) REFERENCES devices.device(id_device);

ALTER TABLE devices.device_telemetry_raw
  ADD CONSTRAINT fk_device_telemetry_raw_device
  FOREIGN KEY (id_device) REFERENCES devices.device(id_device);
