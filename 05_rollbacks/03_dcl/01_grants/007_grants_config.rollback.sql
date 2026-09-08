REVOKE UPDATE ON TABLE config.user_preference FROM smarthome_admin;
REVOKE UPDATE (language, theme, date_format, time_format, currency, temperature_unit, timezone) ON TABLE config.user_preference FROM smarthome_app;
REVOKE SELECT, INSERT ON TABLE config.user_preference FROM smarthome_admin, smarthome_app;
REVOKE USAGE ON SCHEMA config FROM smarthome_admin, smarthome_app, smarthome_ingest, smarthome_worker;
