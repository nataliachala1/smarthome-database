-- Do not erase revocation evidence or reopen an identity after it was revoked.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM devices.mqtt_pairing_revocation_attestation)
     OR EXISTS (
       SELECT 1 FROM devices.mqtt_pairing_state_event
       WHERE to_status IN ('REVOKE_PENDING','REVOKING','REVOKED')
     ) THEN
    RAISE EXCEPTION USING ERRCODE='55000',
      MESSAGE='MQTT_032_ROLLBACK_REQUIRES_REVOCATION_HISTORY_REVIEW';
  END IF;
END $$;

-- Restore the SQL011 contract used before SQL032 wrapped its calls.
GRANT EXECUTE ON FUNCTION devices.fn_claim_mqtt_revocation(),
  devices.fn_finish_mqtt_revocation(UUID,UUID,TEXT)
  TO smarthome_mqtt_revoke;

DROP TRIGGER trg_guard_mqtt_pairing_revoked_evidence ON devices.mqtt_pairing_operation;
DROP FUNCTION devices.fn_guard_mqtt_pairing_revoked_evidence();
DROP TRIGGER trg_guard_mqtt_pairing_revocation_attestation
  ON devices.mqtt_pairing_revocation_attestation;
DROP FUNCTION devices.fn_guard_mqtt_pairing_revocation_attestation();
DROP FUNCTION devices.fn_finish_mqtt_revocation_evidenced(UUID,UUID,TEXT,TEXT);
DROP FUNCTION devices.fn_claim_mqtt_revocation_with_binding();
DROP FUNCTION devices.fn_finish_mqtt_pairing_revocation(UUID,UUID,TEXT,TEXT);
DROP FUNCTION devices.fn_claim_mqtt_pairing_revocation(INTEGER);
ALTER TABLE devices.mqtt_pairing_operation DROP COLUMN revocation_probe_at;
DROP TABLE devices.mqtt_pairing_revocation_attestation;
