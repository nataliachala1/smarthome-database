-- ============================================================
-- ROLLBACK — RLS config
-- ============================================================

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

