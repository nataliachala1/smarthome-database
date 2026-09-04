-- ============================================================
-- TABLAS - notifications
-- ============================================================

CREATE TABLE IF NOT EXISTS notifications.alert_rule (
  id_alert_rule UUID          NOT NULL DEFAULT gen_random_uuid(),
  id_device     UUID          NOT NULL,
  rule_type     VARCHAR(20)   NOT NULL,
  limit_kwh     NUMERIC(10,4) NOT NULL,
  action        VARCHAR(20)   NOT NULL DEFAULT 'alert',
  active        BOOLEAN       NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  deleted_at    TIMESTAMPTZ   NULL,
  CONSTRAINT pk_alert_rule PRIMARY KEY (id_alert_rule),
  CONSTRAINT uq_alert_rule_device UNIQUE (id_alert_rule, id_device),
  CONSTRAINT ck_alert_rule_type CHECK (rule_type IN ('daily_threshold', 'monthly_threshold')),
  CONSTRAINT ck_alert_rule_limit CHECK (limit_kwh > 0),
  CONSTRAINT ck_alert_rule_action CHECK (action IN ('alert', 'turn_off')),
  CONSTRAINT ck_alert_rule_active_delete CHECK (deleted_at IS NULL OR active = FALSE)
);

CREATE TABLE IF NOT EXISTS notifications.alert (
  id_alert        UUID          NOT NULL DEFAULT gen_random_uuid(),
  id_alert_rule   UUID          NULL,
  id_device       UUID          NOT NULL,
  id_home         UUID          NOT NULL,
  alert_type      VARCHAR(20)   NOT NULL,
  detected_value  NUMERIC(12,6) NULL,
  limit_value     NUMERIC(10,4) NULL,
  action_executed VARCHAR(20)   NULL,
  metadata        JSONB         NOT NULL DEFAULT '{}'::JSONB,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_alert PRIMARY KEY (id_alert),
  CONSTRAINT uq_alert_context UNIQUE (id_alert, id_home, id_device),
  CONSTRAINT ck_alert_type CHECK (alert_type IN ('THRESHOLD', 'ANOMALY', 'DEVICE_EVENT')),
  CONSTRAINT ck_alert_threshold_data CHECK (
    (alert_type = 'THRESHOLD' AND id_alert_rule IS NOT NULL AND detected_value IS NOT NULL AND limit_value IS NOT NULL)
    OR (alert_type IN ('ANOMALY', 'DEVICE_EVENT') AND id_alert_rule IS NULL)
  ),
  CONSTRAINT ck_alert_metadata_object CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE TABLE IF NOT EXISTS notifications.notification (
  id_notification UUID         NOT NULL DEFAULT gen_random_uuid(),
  id_user         UUID         NOT NULL,
  id_alert        UUID         NULL,
  id_home         UUID         NULL,
  id_device       UUID         NULL,
  type            VARCHAR(30)  NOT NULL,
  title           VARCHAR(200) NOT NULL,
  message         TEXT         NOT NULL,
  status          VARCHAR(10)  NOT NULL DEFAULT 'UNREAD',
  priority        VARCHAR(10)  NOT NULL DEFAULT 'media',
  channel         VARCHAR(20)  NOT NULL DEFAULT 'IN_APP',
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_notification PRIMARY KEY (id_notification),
  CONSTRAINT ck_notification_type CHECK (type IN ('ALERT', 'RECOMMENDATION', 'SYSTEM')),
  CONSTRAINT ck_notification_status CHECK (status IN ('UNREAD', 'READ', 'DISMISSED')),
  CONSTRAINT ck_notification_priority CHECK (priority IN ('alta', 'media', 'baja')),
  CONSTRAINT ck_notification_channel CHECK (channel IN ('IN_APP')),
  CONSTRAINT ck_notification_device_context CHECK (id_device IS NULL OR id_home IS NOT NULL),
  CONSTRAINT ck_notification_alert_context CHECK (
    (type = 'ALERT' AND id_alert IS NOT NULL AND id_home IS NOT NULL AND id_device IS NOT NULL)
    OR (type = 'RECOMMENDATION' AND id_alert IS NULL AND id_home IS NOT NULL)
    OR (type = 'SYSTEM' AND id_alert IS NULL)
  )
);
