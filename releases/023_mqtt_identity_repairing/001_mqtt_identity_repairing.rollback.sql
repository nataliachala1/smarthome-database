-- Do not silently discard/merge previously revoked history.
-- Once the same manufacturer_device_id has two rows, restoring the global
-- UNIQUE constraint is impossible without destructive data changes.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM devices.mqtt_identity
    GROUP BY manufacturer_device_id
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '55000',
      MESSAGE = 'MQTT_IDENTITY_REPAIRING_ROLLBACK_BLOCKED_HISTORY';
  END IF;
END;
$$;

-- Restore global uniqueness before removing the replacement index.
ALTER TABLE devices.mqtt_identity
  ADD CONSTRAINT mqtt_identity_manufacturer_device_id_key
  UNIQUE (manufacturer_device_id);

DROP INDEX devices.uq_mqtt_identity_unrevoked_manufacturer_ci;
DROP TRIGGER trg_guard_mqtt_identity_repairing ON devices.mqtt_identity;
DROP FUNCTION devices.fn_guard_mqtt_identity_repairing();
