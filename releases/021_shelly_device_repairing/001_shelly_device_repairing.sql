-- HU16: allow a previously soft-deleted physical device to be paired again.
-- Historical devices and their consumption records remain unchanged.

-- Protect active devices against duplicated physical identifiers.
-- This index may already exist in local development databases.
CREATE UNIQUE INDEX IF NOT EXISTS uq_device_manufacturer_active_ci
  ON devices.device (lower(manufacturer_device_id))
  WHERE manufacturer_device_id IS NOT NULL
    AND deleted_at IS NULL;

-- Remove uniqueness rules that also include soft-deleted devices.
ALTER TABLE devices.device
  DROP CONSTRAINT IF EXISTS uq_device_manufacturer_id;

DROP INDEX IF EXISTS devices.uq_device_manufacturer_id_ci;

-- A new physical-device record can now coexist with a deleted historical row.
-- Active records remain protected by uq_device_manufacturer_active_ci.
-- Allow reclaiming a physical identifier only when previous device rows
-- have been soft-deleted. Keep ownership and concurrent-session checks.
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

  IF p_manufacturer_device_id IS NULL
    OR btrim(p_manufacturer_device_id) = '' THEN
    RETURN FALSE;
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(lower(p_manufacturer_device_id), 0)
  );

  IF EXISTS (
    SELECT 1 FROM devices.device d
    WHERE lower(d.manufacturer_device_id) = lower(p_manufacturer_device_id)
      AND d.deleted_at IS NULL
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

REVOKE ALL ON FUNCTION devices.fn_claim_pairing_identity(
  UUID, TEXT, TEXT, TEXT
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION devices.fn_claim_pairing_identity(
  UUID, TEXT, TEXT, TEXT
) TO smarthome_runtime_app;
