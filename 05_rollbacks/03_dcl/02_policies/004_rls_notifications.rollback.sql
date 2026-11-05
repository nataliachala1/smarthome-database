-- ============================================================
-- ROLLBACK — RLS notifications
-- ============================================================


-- ============================================================
-- notification
-- ============================================================

DROP POLICY IF EXISTS
notification_worker_insert_policy
ON notifications.notification;

DROP POLICY IF EXISTS
notification_ingest_insert_policy
ON notifications.notification;

DROP POLICY IF EXISTS
notification_app_update_policy
ON notifications.notification;

DROP POLICY IF EXISTS
notification_app_select_policy
ON notifications.notification;


ALTER TABLE notifications.notification
DISABLE ROW LEVEL SECURITY;


-- ============================================================
-- alert
-- ============================================================

DROP POLICY IF EXISTS
alert_ingest_insert_policy
ON notifications.alert;


ALTER TABLE notifications.alert
DISABLE ROW LEVEL SECURITY;


-- ============================================================
-- alert_rule
-- ============================================================

DROP POLICY IF EXISTS
alert_rule_ingest_select_policy
ON notifications.alert_rule;

DROP POLICY IF EXISTS
alert_rule_app_update_policy
ON notifications.alert_rule;

DROP POLICY IF EXISTS
alert_rule_app_insert_policy
ON notifications.alert_rule;

DROP POLICY IF EXISTS
alert_rule_app_select_policy
ON notifications.alert_rule;


ALTER TABLE notifications.alert_rule
DISABLE ROW LEVEL SECURITY;


-- ============================================================
-- Helpers
-- ============================================================

