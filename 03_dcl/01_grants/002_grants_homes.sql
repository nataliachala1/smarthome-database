GRANT USAGE ON SCHEMA homes
TO smarthome_admin, smarthome_runtime_app, smarthome_readonly, smarthome_ingest, smarthome_worker;

GRANT SELECT, INSERT ON TABLE homes.home TO smarthome_runtime_app;
GRANT UPDATE (name, status, deleted_at)
ON TABLE homes.home TO smarthome_runtime_app;
GRANT SELECT, INSERT, UPDATE ON TABLE homes.home TO smarthome_admin;

GRANT SELECT, INSERT ON TABLE homes.home_member TO smarthome_runtime_app;
GRANT UPDATE (role, status, accepted_at, ended_at)
ON TABLE homes.home_member TO smarthome_runtime_app;
GRANT SELECT, INSERT, UPDATE ON TABLE homes.home_member TO smarthome_admin;
