DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM devices.device_pairing_session) THEN
    RAISE EXCEPTION 'pairing session history exists; preserve it before rolling back HU16 pairing';
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS trg_device_pairing_session_updated_at ON devices.device_pairing_session;
DROP TRIGGER IF EXISTS trg_device_pairing_session_state_guard ON devices.device_pairing_session;
DROP FUNCTION IF EXISTS devices.fn_guard_pairing_session_transition();
DROP FUNCTION IF EXISTS devices.fn_claim_pairing_identity(UUID, TEXT, TEXT, TEXT);
DROP POLICY IF EXISTS device_pairing_session_app_update ON devices.device_pairing_session;
DROP POLICY IF EXISTS device_pairing_session_app_insert ON devices.device_pairing_session;
DROP POLICY IF EXISTS device_pairing_session_app_select ON devices.device_pairing_session;
DROP TABLE IF EXISTS devices.device_pairing_session;
DROP INDEX IF EXISTS devices.uq_device_manufacturer_id_ci;
