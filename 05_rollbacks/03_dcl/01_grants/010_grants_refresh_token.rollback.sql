REVOKE UPDATE (
    session_version,
    updated_at
)
ON TABLE auth."user"
FROM smarthome_app;

REVOKE SELECT, INSERT, UPDATE
ON TABLE auth.refresh_token
FROM smarthome_app;