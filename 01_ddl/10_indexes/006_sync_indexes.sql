CREATE INDEX IF NOT EXISTS idx_backup_status_created
  ON sync.backup(status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_backup_user_created
  ON sync.backup(id_user, created_at DESC)
  WHERE id_user IS NOT NULL;
