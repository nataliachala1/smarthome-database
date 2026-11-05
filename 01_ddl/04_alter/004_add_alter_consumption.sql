ALTER TABLE consumption.consumption
  ADD CONSTRAINT fk_consumption_device_home
  FOREIGN KEY (id_device, id_home)
  REFERENCES devices.device(id_device, id_home);

ALTER TABLE consumption.consumption_metric
  ADD CONSTRAINT fk_consumption_metric_device_home
  FOREIGN KEY (id_device, id_home)
  REFERENCES devices.device(id_device, id_home);
