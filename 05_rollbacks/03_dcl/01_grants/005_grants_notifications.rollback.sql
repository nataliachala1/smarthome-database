REVOKE SELECT, INSERT, UPDATE ON TABLE notifications.notification FROM smarthome_admin;
REVOKE INSERT ON TABLE notifications.notification FROM smarthome_ingest, smarthome_worker;
REVOKE UPDATE (status) ON TABLE notifications.notification FROM smarthome_app;
REVOKE SELECT ON TABLE notifications.notification FROM smarthome_app;

REVOKE SELECT, INSERT ON TABLE notifications.alert FROM smarthome_admin;
REVOKE INSERT ON TABLE notifications.alert FROM smarthome_ingest;

REVOKE SELECT ON TABLE notifications.alert_rule FROM smarthome_ingest;
REVOKE SELECT, INSERT, UPDATE ON TABLE notifications.alert_rule FROM smarthome_admin;
REVOKE UPDATE (rule_type, limit_kwh, action, active, deleted_at) ON TABLE notifications.alert_rule FROM smarthome_app;
REVOKE SELECT, INSERT ON TABLE notifications.alert_rule FROM smarthome_app;
REVOKE USAGE ON SCHEMA notifications FROM smarthome_admin, smarthome_app, smarthome_readonly, smarthome_ingest, smarthome_worker;
