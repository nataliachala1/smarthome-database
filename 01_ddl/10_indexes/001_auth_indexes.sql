-- Índices adicionales de auth.
CREATE INDEX IF NOT EXISTS idx_user_status ON auth."user"(status);
CREATE INDEX IF NOT EXISTS idx_recovery_token_expires_unused
  ON auth.recovery_token(expires_at)
  WHERE used_at IS NULL;
