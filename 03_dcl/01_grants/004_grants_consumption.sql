GRANT USAGE ON SCHEMA consumption
TO smarthome_admin, smarthome_app, smarthome_readonly, smarthome_ingest, smarthome_worker;

GRANT SELECT ON TABLE consumption.consumption TO smarthome_app;
GRANT INSERT ON TABLE consumption.consumption TO smarthome_ingest;
GRANT SELECT (id_device, energy_total_kwh, read_at)
ON TABLE consumption.consumption TO smarthome_ingest;
GRANT SELECT ON TABLE consumption.consumption TO smarthome_worker;
GRANT SELECT, INSERT ON TABLE consumption.consumption TO smarthome_admin;

GRANT SELECT ON TABLE consumption.consumption_metric TO smarthome_app;
GRANT SELECT, INSERT ON TABLE consumption.consumption_metric TO smarthome_worker;
GRANT UPDATE (kwh_total, total_cost, average_watts, max_watts, min_watts)
ON TABLE consumption.consumption_metric TO smarthome_worker;
GRANT SELECT, INSERT, UPDATE ON TABLE consumption.consumption_metric TO smarthome_admin;

REVOKE ALL ON FUNCTION consumption.fn_ensure_consumption_partitions(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION consumption.fn_ensure_consumption_partitions(INT)
TO smarthome_admin, smarthome_worker;
