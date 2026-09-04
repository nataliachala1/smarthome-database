GRANT USAGE ON SCHEMA sync TO smarthome_admin, smarthome_app;
GRANT SELECT ON TABLE sync.backup TO smarthome_app;
GRANT SELECT, INSERT, UPDATE ON TABLE sync.backup TO smarthome_admin;
