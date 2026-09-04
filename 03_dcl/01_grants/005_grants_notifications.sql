GRANT USAGE ON SCHEMA notifications
TO smarthome_admin, smarthome_app, smarthome_readonly, smarthome_ingest, smarthome_worker;

GRANT SELECT, INSERT ON TABLE notifications.alert_rule TO smarthome_app;
GRANT UPDATE (rule_type, limit_kwh, action, active, deleted_at)
ON TABLE notifications.alert_rule TO smarthome_app;
GRANT SELECT, INSERT, UPDATE ON TABLE notifications.alert_rule TO smarthome_admin;
GRANT SELECT ON TABLE notifications.alert_rule TO smarthome_ingest;

GRANT INSERT ON TABLE notifications.alert TO smarthome_ingest;
GRANT SELECT, INSERT ON TABLE notifications.alert TO smarthome_admin;

GRANT SELECT ON TABLE notifications.notification TO smarthome_app;
GRANT UPDATE (status) ON TABLE notifications.notification TO smarthome_app;
GRANT INSERT ON TABLE notifications.notification TO smarthome_ingest, smarthome_worker;
GRANT SELECT, INSERT, UPDATE ON TABLE notifications.notification TO smarthome_admin;
