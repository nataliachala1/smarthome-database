REVOKE SELECT ON TABLE devices.device_telemetry_raw FROM smarthome_admin;
REVOKE INSERT ON TABLE devices.device_telemetry_raw FROM smarthome_ingest;

REVOKE SELECT, INSERT, UPDATE ON TABLE devices.device_schedule FROM smarthome_admin;
REVOKE UPDATE (action, time_of_day, days_of_week, is_active, deleted_at) ON TABLE devices.device_schedule FROM smarthome_app;
REVOKE SELECT, INSERT ON TABLE devices.device_schedule FROM smarthome_app;

REVOKE SELECT ON TABLE devices.smart_device FROM smarthome_ingest;
REVOKE SELECT, INSERT, UPDATE ON TABLE devices.smart_device FROM smarthome_admin;
REVOKE UPDATE (manufacturer, model, firmware_version, max_capacity_w, supports_matter) ON TABLE devices.smart_device FROM smarthome_app;
REVOKE SELECT, INSERT ON TABLE devices.smart_device FROM smarthome_app;

REVOKE UPDATE (connectivity_status, is_on, current_power_w) ON TABLE devices.device FROM smarthome_ingest;
REVOKE SELECT ON TABLE devices.device FROM smarthome_ingest;
REVOKE SELECT, INSERT, UPDATE ON TABLE devices.device FROM smarthome_admin;
REVOKE UPDATE (id_zone, id_device_type, name, status, is_on, transport_type, messaging_protocol, deleted_at) ON TABLE devices.device FROM smarthome_app;
REVOKE SELECT, INSERT ON TABLE devices.device FROM smarthome_app;

REVOKE SELECT ON TABLE devices.device_type FROM smarthome_admin, smarthome_app, smarthome_readonly;
REVOKE USAGE ON SCHEMA devices FROM smarthome_admin, smarthome_app, smarthome_readonly, smarthome_ingest, smarthome_worker;
