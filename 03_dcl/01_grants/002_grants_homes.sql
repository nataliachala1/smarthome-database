GRANT USAGE ON SCHEMA homes
TO smarthome_admin, smarthome_app, smarthome_readonly, smarthome_ingest, smarthome_worker;

GRANT SELECT, INSERT ON TABLE homes.home TO smarthome_app;
GRANT UPDATE (name, stratum, status, deleted_at)
ON TABLE homes.home TO smarthome_app;
GRANT SELECT, INSERT, UPDATE ON TABLE homes.home TO smarthome_admin;

GRANT SELECT, INSERT ON TABLE homes.zone TO smarthome_app;
GRANT UPDATE (name, type, deleted_at)
ON TABLE homes.zone TO smarthome_app;
GRANT SELECT, INSERT, UPDATE ON TABLE homes.zone TO smarthome_admin;

GRANT SELECT, INSERT ON TABLE homes.home_member TO smarthome_app;
GRANT UPDATE (role, status, accepted_at, ended_at)
ON TABLE homes.home_member TO smarthome_app;
GRANT SELECT, INSERT, UPDATE ON TABLE homes.home_member TO smarthome_admin;

GRANT SELECT, INSERT ON TABLE homes.electricity_tariff TO smarthome_app;
GRANT UPDATE (price_per_kwh, currency, valid_from, valid_to)
ON TABLE homes.electricity_tariff TO smarthome_app;
GRANT SELECT, INSERT, UPDATE ON TABLE homes.electricity_tariff TO smarthome_admin;
