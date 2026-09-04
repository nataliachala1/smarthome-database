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
-- homes.electricity_tariff
-- ============================================================

DROP POLICY IF EXISTS
electricity_tariff_update_policy
ON homes.electricity_tariff;

DROP POLICY IF EXISTS
electricity_tariff_insert_policy
ON homes.electricity_tariff;

DROP POLICY IF EXISTS
electricity_tariff_select_policy
ON homes.electricity_tariff;


ALTER TABLE homes.electricity_tariff
DISABLE ROW LEVEL SECURITY;


-- ============================================================
-- homes.zone
-- ============================================================

DROP POLICY IF EXISTS
zone_update_policy
ON homes.zone;

DROP POLICY IF EXISTS
zone_insert_policy
ON homes.zone;

DROP POLICY IF EXISTS
zone_select_policy
ON homes.zone;


ALTER TABLE homes.zone
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

