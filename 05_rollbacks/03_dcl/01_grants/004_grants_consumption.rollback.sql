REVOKE EXECUTE ON FUNCTION consumption.fn_ensure_consumption_partitions(INT) FROM smarthome_admin, smarthome_worker;

REVOKE SELECT, INSERT, UPDATE ON TABLE consumption.recommendation FROM smarthome_admin;
REVOKE UPDATE (title, description, estimated_savings_kwh, estimated_savings_cost, priority, status, deleted_at) ON TABLE consumption.recommendation FROM smarthome_worker;
REVOKE SELECT, INSERT ON TABLE consumption.recommendation FROM smarthome_worker;
REVOKE SELECT ON TABLE consumption.recommendation FROM smarthome_app;

REVOKE SELECT, INSERT, UPDATE ON TABLE consumption.consumption_metric FROM smarthome_admin;
REVOKE UPDATE (kwh_total, total_cost, average_watts, max_watts, min_watts) ON TABLE consumption.consumption_metric FROM smarthome_worker;
REVOKE SELECT, INSERT ON TABLE consumption.consumption_metric FROM smarthome_worker;
REVOKE SELECT ON TABLE consumption.consumption_metric FROM smarthome_app;

REVOKE SELECT, INSERT ON TABLE consumption.consumption FROM smarthome_admin;
REVOKE SELECT ON TABLE consumption.consumption FROM smarthome_worker;
REVOKE SELECT (id_device, energy_total_kwh, read_at) ON TABLE consumption.consumption FROM smarthome_ingest;
REVOKE INSERT ON TABLE consumption.consumption FROM smarthome_ingest;
REVOKE SELECT ON TABLE consumption.consumption FROM smarthome_app;
REVOKE USAGE ON SCHEMA consumption FROM smarthome_admin, smarthome_app, smarthome_readonly, smarthome_ingest, smarthome_worker;
