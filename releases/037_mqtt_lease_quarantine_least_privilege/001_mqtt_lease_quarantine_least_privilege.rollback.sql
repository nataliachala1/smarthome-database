-- Rollback of SQL037: restore the lease-worker privilege and role comment
-- exactly as SQL025 defined them.
GRANT EXECUTE ON FUNCTION devices.fn_quarantine_expired_mqtt_pairing_lease(uuid)
  TO smarthome_mqtt_lease_worker;

COMMENT ON ROLE smarthome_mqtt_lease_worker IS
  'NOLOGIN: first preparation claim and uncertain/expired lease quarantine only. No table DML, no broker success assertions.';
