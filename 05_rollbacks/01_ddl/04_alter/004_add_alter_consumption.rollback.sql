ALTER TABLE consumption.recommendation
  DROP CONSTRAINT IF EXISTS fk_recommendation_device_home,
  DROP CONSTRAINT IF EXISTS fk_recommendation_home;
ALTER TABLE consumption.consumption_metric DROP CONSTRAINT IF EXISTS fk_consumption_metric_device_home;
ALTER TABLE consumption.consumption DROP CONSTRAINT IF EXISTS fk_consumption_device_home;
