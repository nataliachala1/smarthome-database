REVOKE SELECT, INSERT ON TABLE identity_audit.audit_log FROM smarthome_admin;
REVOKE SELECT, INSERT ON TABLE identity_audit.audit_log FROM smarthome_runtime_app;
REVOKE USAGE ON SCHEMA identity_audit FROM smarthome_admin, smarthome_runtime_app;
