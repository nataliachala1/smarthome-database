-- Add LAN-first pairing without changing the already released 019 changeset.
ALTER TABLE devices.device_pairing_session
  DROP CONSTRAINT ck_device_pairing_session_method;

ALTER TABLE devices.device_pairing_session
  ADD CONSTRAINT ck_device_pairing_session_method
  CHECK (method IN ('AP', 'LAN', 'BLE'));

COMMENT ON CONSTRAINT ck_device_pairing_session_method
  ON devices.device_pairing_session IS
  'BLE remains unavailable until a native hardware proof of concept is validated.';
