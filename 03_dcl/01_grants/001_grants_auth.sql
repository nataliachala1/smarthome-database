GRANT USAGE ON SCHEMA auth
TO smarthome_admin, smarthome_app, smarthome_readonly, smarthome_ingest, smarthome_worker;

GRANT SELECT ON TABLE auth.role
TO smarthome_admin, smarthome_app, smarthome_readonly;

GRANT SELECT ON TABLE auth."user"
TO smarthome_admin, smarthome_app;
GRANT INSERT, UPDATE ON TABLE auth."user" TO smarthome_admin;
GRANT INSERT (name, email, password_hash)
ON TABLE auth."user" TO smarthome_app;
GRANT UPDATE (
  name, email, password_hash, status, email_verified,
  failed_login_attempts, locked_until, last_login_at, deactivated_at
)
ON TABLE auth."user" TO smarthome_app;

GRANT SELECT ON TABLE auth.recovery_token
TO smarthome_admin, smarthome_app;
GRANT INSERT, UPDATE ON TABLE auth.recovery_token TO smarthome_admin;
GRANT INSERT (id_user, token_hash, type, expires_at)
ON TABLE auth.recovery_token TO smarthome_app;
GRANT UPDATE (used_at)
ON TABLE auth.recovery_token TO smarthome_app;
