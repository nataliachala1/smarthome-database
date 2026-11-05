ALTER TABLE auth."user"
DROP CONSTRAINT IF EXISTS ck_user_session_version;

ALTER TABLE auth."user"
DROP COLUMN IF EXISTS session_version;