ALTER TABLE devices.device
  ADD CONSTRAINT fk_device_home
    FOREIGN KEY (id_home) REFERENCES homes.home(id_home),
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
