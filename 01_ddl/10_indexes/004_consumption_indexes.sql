-- Los índices simples del parent se crean junto con la tabla.
CREATE INDEX IF NOT EXISTS idx_consumption_home_read_at
  ON consumption.consumption(id_home, read_at DESC);

CREATE INDEX IF NOT EXISTS idx_consumption_device_read_at
  ON consumption.consumption(id_device, read_at DESC);

CREATE INDEX IF NOT EXISTS idx_consumption_metric_home_period_start
  ON consumption.consumption_metric(id_home, period, start_at DESC);

CREATE INDEX IF NOT EXISTS idx_recommendation_home_status
  ON consumption.recommendation(id_home, status, created_at DESC)
  WHERE deleted_at IS NULL;
