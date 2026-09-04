REVOKE UPDATE (used_at) ON TABLE auth.recovery_token FROM smarthome_app;
REVOKE INSERT (id_user, token_hash, type, expires_at) ON TABLE auth.recovery_token FROM smarthome_app;
REVOKE INSERT, UPDATE ON TABLE auth.recovery_token FROM smarthome_admin;
REVOKE SELECT ON TABLE auth.recovery_token FROM smarthome_admin, smarthome_app;

REVOKE UPDATE (name, email, password_hash, status, email_verified, failed_login_attempts, locked_until, last_login_at, deactivated_at)
ON TABLE auth."user" FROM smarthome_app;
REVOKE INSERT (name, email, password_hash) ON TABLE auth."user" FROM smarthome_app;
REVOKE INSERT, UPDATE ON TABLE auth."user" FROM smarthome_admin;
REVOKE SELECT ON TABLE auth."user" FROM smarthome_admin, smarthome_app;
REVOKE SELECT ON TABLE auth.role FROM smarthome_admin, smarthome_app, smarthome_readonly;
REVOKE USAGE ON SCHEMA auth FROM smarthome_admin, smarthome_app, smarthome_readonly, smarthome_ingest, smarthome_worker;
