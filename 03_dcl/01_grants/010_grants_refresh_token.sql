-- ============================================================
-- Grants required by the backend authentication/session layer.
-- ============================================================

GRANT SELECT, INSERT, UPDATE
ON TABLE auth.refresh_token
TO smarthome_app;

GRANT UPDATE (
    session_version,
    updated_at
)
ON TABLE auth."user"
TO smarthome_app;