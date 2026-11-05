-- SQL037: align the lease-worker database privileges with its reviewed SQL API.
-- Quarantine remains available to a separately reviewed reconciliation path;
-- the preparation lease worker has no adapter for this state transition.
DO $bd01$
BEGIN
  IF to_regprocedure('devices.fn_quarantine_expired_mqtt_pairing_lease(uuid)') IS NULL THEN
    RAISE EXCEPTION 'BD037_REQUIRED_FUNCTION_MISSING';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE rolname = 'smarthome_mqtt_lease_worker'
  ) THEN
    RAISE EXCEPTION 'BD037_REQUIRED_ROLE_MISSING';
  END IF;
END
$bd01$;

REVOKE ALL ON FUNCTION devices.fn_quarantine_expired_mqtt_pairing_lease(uuid)
  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION devices.fn_quarantine_expired_mqtt_pairing_lease(uuid)
  FROM smarthome_mqtt_lease_worker;

COMMENT ON ROLE smarthome_mqtt_lease_worker IS
  'NOLOGIN: preparation and enable lease operations plus uncertainty reporting only; no quarantine or broker-success assertion.';
