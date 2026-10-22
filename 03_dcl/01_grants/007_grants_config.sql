GRANT USAGE ON SCHEMA config
TO smarthome_admin, smarthome_runtime_app, smarthome_ingest, smarthome_worker;

GRANT SELECT, INSERT ON TABLE config.user_preference TO smarthome_admin, smarthome_runtime_app;
GRANT UPDATE (language, theme, date_format, time_format, currency, temperature_unit, timezone) ON TABLE config.user_preference TO smarthome_runtime_app;
GRANT UPDATE ON TABLE config.user_preference TO smarthome_admin;
