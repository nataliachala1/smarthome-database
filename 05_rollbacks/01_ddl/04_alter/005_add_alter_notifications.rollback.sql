ALTER TABLE notifications.notification
  DROP CONSTRAINT IF EXISTS fk_notification_home,
  DROP CONSTRAINT IF EXISTS fk_notification_device_home,
  DROP CONSTRAINT IF EXISTS fk_notification_alert_context,
  DROP CONSTRAINT IF EXISTS fk_notification_user;
ALTER TABLE notifications.alert
  DROP CONSTRAINT IF EXISTS fk_alert_device_home,
  DROP CONSTRAINT IF EXISTS fk_alert_rule_device;
