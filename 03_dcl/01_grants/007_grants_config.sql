GRANT USAGE ON SCHEMA config
TO smarthome_admin, smarthome_app, smarthome_ingest, smarthome_worker;

GRANT SELECT, INSERT ON TABLE config.user_preference TO smarthome_admin, smarthome_app;
GRANT UPDATE ON TABLE config.user_preference TO smarthome_admin;
