GRANT USAGE ON SCHEMA identity_audit TO smarthome_admin, smarthome_runtime_app;
GRANT SELECT, INSERT ON TABLE identity_audit.audit_log TO smarthome_runtime_app;
GRANT SELECT, INSERT ON TABLE identity_audit.audit_log TO smarthome_admin;
