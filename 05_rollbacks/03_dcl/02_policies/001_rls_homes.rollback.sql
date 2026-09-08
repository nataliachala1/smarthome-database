-- ============================================================
-- ROLLBACK — RLS homes
-- ============================================================


-- ============================================================
-- homes.home_member
-- ============================================================

DROP POLICY IF EXISTS
home_member_update_policy
ON homes.home_member;

DROP POLICY IF EXISTS
home_member_insert_policy
ON homes.home_member;

DROP POLICY IF EXISTS
home_member_select_policy
ON homes.home_member;


ALTER TABLE homes.home_member
DISABLE ROW LEVEL SECURITY;


-- ============================================================
-- homes.home
-- ============================================================

DROP POLICY IF EXISTS
home_update_policy
ON homes.home;

DROP POLICY IF EXISTS
home_insert_policy
ON homes.home;

DROP POLICY IF EXISTS
home_select_policy
ON homes.home;


ALTER TABLE homes.home
DISABLE ROW LEVEL SECURITY;


-- ============================================================
-- EXECUTE helpers
-- ============================================================

