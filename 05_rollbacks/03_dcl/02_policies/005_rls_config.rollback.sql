-- ============================================================
-- ROLLBACK — RLS config
-- ============================================================


-- ============================================================
-- config.home_notification_preference
-- ============================================================

DROP POLICY IF EXISTS
home_notification_preference_worker_select_policy
ON config.home_notification_preference;

DROP POLICY IF EXISTS
home_notification_preference_ingest_select_policy
ON config.home_notification_preference;

DROP POLICY IF EXISTS
home_notification_preference_app_update_policy
ON config.home_notification_preference;

DROP POLICY IF EXISTS
home_notification_preference_app_insert_policy
ON config.home_notification_preference;

DROP POLICY IF EXISTS
home_notification_preference_app_select_policy
ON config.home_notification_preference;


ALTER TABLE config.home_notification_preference
DISABLE ROW LEVEL SECURITY;



-- ============================================================
-- config.home_recommendation_preference
-- ============================================================

DROP POLICY IF EXISTS
home_recommendation_preference_worker_select_policy
ON config.home_recommendation_preference;

DROP POLICY IF EXISTS
home_recommendation_preference_app_update_policy
ON config.home_recommendation_preference;

DROP POLICY IF EXISTS
home_recommendation_preference_app_insert_policy
ON config.home_recommendation_preference;

DROP POLICY IF EXISTS
home_recommendation_preference_app_select_policy
ON config.home_recommendation_preference;


ALTER TABLE config.home_recommendation_preference
DISABLE ROW LEVEL SECURITY;



-- ============================================================
-- config.user_preference
-- ============================================================

DROP POLICY IF EXISTS
user_preference_update_policy
ON config.user_preference;

DROP POLICY IF EXISTS
user_preference_insert_policy
ON config.user_preference;

DROP POLICY IF EXISTS
user_preference_select_policy
ON config.user_preference;


ALTER TABLE config.user_preference
DISABLE ROW LEVEL SECURITY;



-- ============================================================
-- Helper técnico concedido en este changeset
-- ============================================================

