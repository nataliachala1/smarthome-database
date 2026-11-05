-- ============================================================
-- ROLLBACK — RLS sync
-- Archivo:
-- 05_rollbacks/03_dcl/02_policies/006_rls_sync.rollback.sql
-- ============================================================


DROP POLICY IF EXISTS
backup_system_admin_select_policy
ON sync.backup;




ALTER TABLE sync.backup
DISABLE ROW LEVEL SECURITY;