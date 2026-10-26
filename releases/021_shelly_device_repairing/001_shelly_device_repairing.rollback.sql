-- HU16: rollback de revinculacion de dispositivos.
-- No elimina dispositivos ni registros historicos.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM devices.device
    WHERE manufacturer_device_id IS NOT NULL
    GROUP BY lower(manufacturer_device_id)
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION
      'Cannot rollback device repairing: duplicate manufacturer IDs exist';
  END IF;
END;
$$;

ALTER TABLE devices.device
  ADD CONSTRAINT uq_device_manufacturer_id
  UNIQUE (manufacturer_device_id);

CREATE UNIQUE INDEX uq_device_manufacturer_id_ci
  ON devices.device (lower(manufacturer_device_id))
  WHERE manufacturer_device_id IS NOT NULL;

-- Preserve the previously existing active-only index.

-- Restore the original pairing function.
CREATE OR REPLACE FUNCTION devices.fn_claim_pairing_identity(
  p_session_id UUID,
  p_manufacturer_device_id TEXT,
  p_model_code TEXT,
  p_firmware_version TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, devices, homes, auth
AS $$
DECLARE
  v_session devices.device_pairing_session%ROWTYPE;
BEGIN
  SELECT * INTO v_session
  FROM devices.device_pairing_session
  WHERE id_device_pairing_session = p_session_id
  FOR UPDATE;

  IF NOT FOUND OR v_session.id_user <> auth.fn_current_user_id()
    OR NOT homes.fn_can_manage_home(v_session.id_home)
    OR v_session.status <> 'PENDING'
    OR v_session.expires_at <= CURRENT_TIMESTAMP THEN
    RETURN FALSE;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(lower(p_manufacturer_device_id), 0));

  IF EXISTS (
    SELECT 1 FROM devices.device d
    WHERE lower(d.manufacturer_device_id) = lower(p_manufacturer_device_id)
  ) OR EXISTS (
    SELECT 1 FROM devices.device_pairing_session s
    WHERE lower(s.manufacturer_device_id) = lower(p_manufacturer_device_id)
      AND s.id_device_pairing_session <> p_session_id
      AND s.status IN ('DEVICE_IDENTIFIED', 'WAITING_FOR_MQTT', 'CONNECTED')
      AND s.expires_at > CURRENT_TIMESTAMP
  ) THEN
    RETURN FALSE;
  END IF;

  UPDATE devices.device_pairing_session
  SET manufacturer_device_id = p_manufacturer_device_id,
      model_code = p_model_code,
      firmware_version = p_firmware_version,
      identity_reported_at = CURRENT_TIMESTAMP,
      status = 'DEVICE_IDENTIFIED'
  WHERE id_device_pairing_session = p_session_id;
  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_claim_pairing_identity(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_claim_pairing_identity(UUID, TEXT, TEXT, TEXT) TO smarthome_runtime_app;