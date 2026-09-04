GRANT USAGE ON SCHEMA devices
TO smarthome_admin, smarthome_app, smarthome_readonly, smarthome_ingest, smarthome_worker;

GRANT SELECT ON TABLE devices.device_type
TO smarthome_admin, smarthome_app, smarthome_readonly;

GRANT SELECT, INSERT ON TABLE devices.device TO smarthome_app;
GRANT UPDATE (id_zone, id_device_type, name, status, is_on, transport_type, messaging_protocol, deleted_at)
ON TABLE devices.device TO smarthome_app;
GRANT SELECT, INSERT, UPDATE ON TABLE devices.device TO smarthome_admin;
GRANT SELECT ON TABLE devices.device TO smarthome_ingest;
GRANT UPDATE (connectivity_status, is_on, current_power_w)
ON TABLE devices.device TO smarthome_ingest;

GRANT SELECT, INSERT ON TABLE devices.smart_device TO smarthome_app;
GRANT UPDATE (manufacturer, model, firmware_version, max_capacity_w, supports_matter)
ON TABLE devices.smart_device TO smarthome_app;
GRANT SELECT, INSERT, UPDATE ON TABLE devices.smart_device TO smarthome_admin;
GRANT SELECT ON TABLE devices.smart_device TO smarthome_ingest;

GRANT SELECT, INSERT ON TABLE devices.device_schedule TO smarthome_app;
GRANT UPDATE (action, time_of_day, days_of_week, is_active, deleted_at)
ON TABLE devices.device_schedule TO smarthome_app;
GRANT SELECT, INSERT, UPDATE ON TABLE devices.device_schedule TO smarthome_admin;

GRANT INSERT ON TABLE devices.device_telemetry_raw TO smarthome_ingest;
GRANT SELECT ON TABLE devices.device_telemetry_raw TO smarthome_admin;
