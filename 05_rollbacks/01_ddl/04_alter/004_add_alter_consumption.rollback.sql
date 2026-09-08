ALTER TABLE consumption.consumption_metric DROP CONSTRAINT IF EXISTS fk_consumption_metric_device_home;
ALTER TABLE consumption.consumption DROP CONSTRAINT IF EXISTS fk_consumption_device_home;
