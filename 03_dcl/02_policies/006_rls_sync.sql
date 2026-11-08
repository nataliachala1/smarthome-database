-- ============================================================
-- RLS — sync schema
-- File: 03_dcl/02_policies/006_rls_sync.sql
--
-- Protected table:
--   sync.backup
--
-- sync.backup only holds backup metadata.
-- Actual backups/restores belong to the
-- infrastructure/PostgreSQL.
--
-- Functional access:
--   SYSTEM_ADMIN -> SELECT
--   USER         -> no access
--
-- Writes:
--   smarthome_admin through a technical process.
--
-- There are no INSERT/UPDATE/DELETE policies for smarthome_runtime_app.
-- ============================================================


-- ============================================================
-- sync.backup
-- ============================================================

ALTER TABLE sync.backup
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- SELECT — application
--
-- smarthome_runtime_app is used by different functional users,
-- but only a global SYSTEM_ADMIN user can read
-- backup metadata.
--
-- The policy does not depend on id_user because a SYSTEM_ADMIN must
-- be able to read every backup:
--
--   automatic
--   manual
--   completed
--   failed
--   in progress
--
-- ------------------------------------------------------------

CREATE POLICY backup_system_admin_select_policy
ON sync.backup
FOR SELECT
TO smarthome_runtime_app
USING (
    auth.fn_is_system_admin()
);