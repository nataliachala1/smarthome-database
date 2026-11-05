CREATE INDEX IF NOT EXISTS idx_alert_rule_device_active
  ON notifications.alert_rule(id_device)
  WHERE active = TRUE AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_alert_home_created
  ON notifications.alert(id_home, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_alert_device_created
  ON notifications.alert(id_device, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_user_status_created
  ON notifications.notification(id_user, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_home_created
  ON notifications.notification(id_home, created_at DESC)
  WHERE id_home IS NOT NULL;
