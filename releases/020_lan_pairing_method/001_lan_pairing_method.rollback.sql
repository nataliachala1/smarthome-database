DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM devices.device_pairing_session WHERE method = 'LAN'
  ) THEN
    RAISE EXCEPTION 'LAN pairing sessions exist; preserve history and use a forward migration instead of rollback';
  END IF;
END;
$$;

ALTER TABLE devices.device_pairing_session
  DROP CONSTRAINT ck_device_pairing_session_method;

ALTER TABLE devices.device_pairing_session
  ADD CONSTRAINT ck_device_pairing_session_method
  CHECK (method IN ('AP', 'BLE'));
