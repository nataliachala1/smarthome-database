ALTER TABLE identity_audit.audit_log
  DROP CONSTRAINT IF EXISTS fk_audit_log_home,
  DROP CONSTRAINT IF EXISTS fk_audit_log_user;
