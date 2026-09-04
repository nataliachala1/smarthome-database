ALTER TABLE notifications.alert
  ADD CONSTRAINT fk_alert_rule_device
    FOREIGN KEY (id_alert_rule, id_device)
    REFERENCES notifications.alert_rule(id_alert_rule, id_device),
  ADD CONSTRAINT fk_alert_device_home
    FOREIGN KEY (id_device, id_home)
    REFERENCES devices.device(id_device, id_home);

ALTER TABLE notifications.notification
  ADD CONSTRAINT fk_notification_user
    FOREIGN KEY (id_user) REFERENCES auth."user"(id_user),
  ADD CONSTRAINT fk_notification_alert_context
    FOREIGN KEY (id_alert, id_home, id_device)
    REFERENCES notifications.alert(id_alert, id_home, id_device),
  ADD CONSTRAINT fk_notification_device_home
    FOREIGN KEY (id_device, id_home)
    REFERENCES devices.device(id_device, id_home),
  ADD CONSTRAINT fk_notification_home
    FOREIGN KEY (id_home) REFERENCES homes.home(id_home);
