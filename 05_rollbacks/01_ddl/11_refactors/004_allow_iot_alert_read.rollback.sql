DROP POLICY IF EXISTS alert_ingest_select_policy
ON notifications.alert;

REVOKE SELECT
ON TABLE notifications.alert
FROM smarthome_ingest;