-- ============================================================
-- Add session version to auth.user.
-- Used to invalidate previously issued sessions/JWTs.
-- ============================================================

ALTER TABLE auth."user"
ADD COLUMN IF NOT EXISTS session_version
INTEGER NOT NULL DEFAULT 0;

ALTER TABLE auth."user"
DROP CONSTRAINT IF EXISTS ck_user_session_version;

ALTER TABLE auth."user"
ADD CONSTRAINT ck_user_session_version
CHECK (session_version >= 0);