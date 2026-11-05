CREATE INDEX IF NOT EXISTS idx_audit_created_at
  ON identity_audit.audit_log(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_user_created_at
  ON identity_audit.audit_log(id_user, created_at DESC)
  WHERE id_user IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_audit_home_created_at
  ON identity_audit.audit_log(id_home, created_at DESC)
  WHERE id_home IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_audit_action_created_at
  ON identity_audit.audit_log(action, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_failures
  ON identity_audit.audit_log(created_at DESC)
  WHERE result = 'FAILURE';
