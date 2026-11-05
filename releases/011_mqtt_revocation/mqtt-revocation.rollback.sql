-- Never discard identity references or outstanding revocations during rollback.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM devices.mqtt_identity) THEN
    RAISE EXCEPTION 'MQTT_IDENTITY_ROLLBACK_REQUIRES_EMPTY_REGISTRY';
  END IF;
END;
$$;
DROP TRIGGER trg_device_mqtt_revocation ON devices.device;
DROP FUNCTION devices.fn_mqtt_identity_device_update();
DROP FUNCTION devices.fn_register_mqtt_identity(UUID, UUID, TEXT);
DROP FUNCTION devices.fn_claim_mqtt_revocation();
DROP FUNCTION devices.fn_finish_mqtt_revocation(UUID, UUID, TEXT);
DROP TABLE devices.mqtt_identity;
-- Keep the NOLOGIN roles: a deployment may have assigned login memberships.
-- They retain no function/table privileges introduced by this migration.
