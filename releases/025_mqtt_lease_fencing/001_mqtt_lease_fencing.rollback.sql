-- Fail closed: never erase workflow/audit history or downgrade security once
-- claims have been made. Only empty tests or unstarted RESERVED rows permit rollback.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM devices.mqtt_pairing_operation
               WHERE status <> 'RESERVED' OR attempt_count <> 0)
    OR EXISTS (SELECT 1 FROM devices.mqtt_pairing_state_event
                WHERE from_status IS NOT NULL)
  THEN
    RAISE EXCEPTION USING ERRCODE='55000',
      MESSAGE='MQTT_025_ROLLBACK_BLOCKED_BY_OPERATION_HISTORY';
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION devices.fn_claim_mqtt_pairing_preparation(UUID,INTEGER)
  FROM smarthome_mqtt_lease_worker;
REVOKE EXECUTE ON FUNCTION devices.fn_report_mqtt_pairing_uncertain(UUID,UUID,TEXT)
  FROM smarthome_mqtt_lease_worker;
REVOKE EXECUTE ON FUNCTION devices.fn_quarantine_expired_mqtt_pairing_lease(UUID)
  FROM smarthome_mqtt_lease_worker;
DROP FUNCTION devices.fn_quarantine_expired_mqtt_pairing_lease(UUID);
DROP FUNCTION devices.fn_report_mqtt_pairing_uncertain(UUID,UUID,TEXT);
DROP FUNCTION devices.fn_claim_mqtt_pairing_preparation(UUID,INTEGER);
REVOKE USAGE ON SCHEMA devices FROM smarthome_mqtt_lease_worker;
-- Only delete role if no external grants/memberships were added.
DROP ROLE smarthome_mqtt_lease_worker;
