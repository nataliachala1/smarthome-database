ALTER TABLE auth.recovery_token DROP CONSTRAINT IF EXISTS fk_recovery_token_user;
ALTER TABLE auth."user" DROP CONSTRAINT IF EXISTS fk_user_role;
