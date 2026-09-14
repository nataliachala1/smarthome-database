
REVOKE SELECT, INSERT, UPDATE ON TABLE homes.home_member FROM smarthome_admin;
REVOKE UPDATE (role, status, accepted_at, ended_at) ON TABLE homes.home_member FROM smarthome_app;
REVOKE SELECT, INSERT ON TABLE homes.home_member FROM smarthome_app;


REVOKE SELECT, INSERT, UPDATE ON TABLE homes.home FROM smarthome_admin;
REVOKE UPDATE (name, status, deleted_at) ON TABLE homes.home FROM smarthome_app;
REVOKE SELECT, INSERT ON TABLE homes.home FROM smarthome_app;
REVOKE USAGE ON SCHEMA homes FROM smarthome_admin, smarthome_app, smarthome_readonly, smarthome_ingest, smarthome_worker;
