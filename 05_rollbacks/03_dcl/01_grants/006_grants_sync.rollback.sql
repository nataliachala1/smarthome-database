REVOKE SELECT, INSERT, UPDATE ON TABLE sync.backup FROM smarthome_admin;
REVOKE SELECT ON TABLE sync.backup FROM smarthome_runtime_app;
REVOKE USAGE ON SCHEMA sync FROM smarthome_admin, smarthome_runtime_app;
