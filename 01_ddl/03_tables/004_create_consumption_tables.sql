-- ============================================================
-- TABLAS - consumption
-- ============================================================

CREATE TABLE IF NOT EXISTS consumption.consumption (
  id_consumption    UUID          NOT NULL DEFAULT gen_random_uuid(),
  id_device         UUID          NOT NULL,
  id_home           UUID          NOT NULL,
  power_w           NUMERIC(10,4) NOT NULL,
  energy_delta_kwh  NUMERIC(12,6) NOT NULL DEFAULT 0,
  energy_total_kwh  NUMERIC(14,6) NULL,
  voltage_v         NUMERIC(10,4) NULL,
  current_a         NUMERIC(10,4) NULL,
  frequency_hz      NUMERIC(8,4)  NULL,
  temperature_c     NUMERIC(8,4)  NULL,
  read_at           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_consumption PRIMARY KEY (id_consumption, read_at),
  CONSTRAINT ck_consumption_power CHECK (power_w >= 0),
  CONSTRAINT ck_consumption_delta CHECK (energy_delta_kwh >= 0),
  CONSTRAINT ck_consumption_total CHECK (energy_total_kwh IS NULL OR energy_total_kwh >= 0),
  CONSTRAINT ck_consumption_voltage CHECK (voltage_v IS NULL OR voltage_v >= 0),
  CONSTRAINT ck_consumption_current CHECK (current_a IS NULL OR current_a >= 0),
  CONSTRAINT ck_consumption_frequency CHECK (frequency_hz IS NULL OR frequency_hz > 0),
  CONSTRAINT ck_consumption_temperature CHECK (temperature_c IS NULL OR temperature_c BETWEEN -100 AND 200)
) PARTITION BY RANGE (read_at);

CREATE INDEX IF NOT EXISTS idx_consumption_id_device ON consumption.consumption (id_device);
CREATE INDEX IF NOT EXISTS idx_consumption_id_home ON consumption.consumption (id_home);
CREATE INDEX IF NOT EXISTS idx_consumption_read_at ON consumption.consumption (read_at);

CREATE TABLE IF NOT EXISTS consumption.consumption_default
  PARTITION OF consumption.consumption DEFAULT;

CREATE TABLE IF NOT EXISTS consumption.consumption_metric (
  id_consumption_metric UUID          NOT NULL DEFAULT gen_random_uuid(),
  id_device             UUID          NOT NULL,
  id_home               UUID          NOT NULL,
  period                VARCHAR(10)   NOT NULL,
  start_at              TIMESTAMPTZ   NOT NULL,
  end_at                TIMESTAMPTZ   NOT NULL,
  kwh_total             NUMERIC(12,6) NOT NULL DEFAULT 0,
  average_watts         NUMERIC(10,4) NULL,
  max_watts             NUMERIC(10,4) NULL,
  min_watts             NUMERIC(10,4) NULL,
  created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_consumption_metric PRIMARY KEY (id_consumption_metric),
  CONSTRAINT uq_consumption_metric UNIQUE (id_device, period, start_at),
  CONSTRAINT ck_consumption_metric_period CHECK (period IN ('hora', 'dia', 'semana', 'mes')),
  CONSTRAINT ck_consumption_metric_dates CHECK (end_at > start_at),
  CONSTRAINT ck_consumption_metric_kwh CHECK (kwh_total >= 0),
  CONSTRAINT ck_consumption_metric_watts CHECK (
    (average_watts IS NULL OR average_watts >= 0)
    AND (max_watts IS NULL OR max_watts >= 0)
    AND (min_watts IS NULL OR min_watts >= 0)
  ),
  CONSTRAINT ck_consumption_metric_max_min CHECK (
    max_watts IS NULL OR min_watts IS NULL OR max_watts >= min_watts
  )
);