-- ============================================================
-- ROLLBACK — RLS identity_audit
-- Archivo:
-- 05_rollbacks/03_dcl/02_policies/
-- 007_rls_identity_audit.rollback.sql
-- ============================================================


-- ============================================================
-- identity_audit.audit_log
-- ============================================================

DROP POLICY IF EXISTS
audit_app_insert_policy
ON identity_audit.audit_log;


DROP POLICY IF EXISTS
audit_system_admin_select_policy
ON identity_audit.audit_log;




ALTER TABLE identity_audit.audit_log
DISABLE ROW LEVEL SECURITY;