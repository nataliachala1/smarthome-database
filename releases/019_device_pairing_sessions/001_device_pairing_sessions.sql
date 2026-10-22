-- Additive HU16 pairing foundation. Tokens are hashed by the API; Wi-Fi and
-- MQTT credentials are deliberately absent from this table.
DO $$
BEGIN
  IF EXISTS (
    SELECT lower(manufacturer_device_id)
    FROM devices.device
    WHERE manufacturer_device_id IS NOT NULL
    GROUP BY lower(manufacturer_device_id)
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'duplicate manufacturer device IDs differ only by case; resolve them before pairing migration';
  END IF;
END;
$$;

CREATE UNIQUE INDEX uq_device_manufacturer_id_ci
  ON devices.device (lower(manufacturer_device_id))
  WHERE manufacturer_device_id IS NOT NULL;

CREATE TABLE devices.device_pairing_session (
  id_device_pairing_session UUID NOT NULL DEFAULT gen_random_uuid(),
  id_home UUID NOT NULL,
  id_user UUID NOT NULL,
  request_key_hash CHAR(64) NOT NULL,
  token_hash CHAR(64) NOT NULL,
  method VARCHAR(10) NOT NULL,
  status VARCHAR(24) NOT NULL DEFAULT 'PENDING',
  manufacturer_device_id VARCHAR(100) NULL,
  model_code VARCHAR(100) NULL,
  firmware_version VARCHAR(100) NULL,
  identity_reported_at TIMESTAMPTZ NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  completed_device_id UUID NULL,
  failure_code VARCHAR(64) NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  cancelled_at TIMESTAMPTZ NULL,
  CONSTRAINT pk_device_pairing_session PRIMARY KEY (id_device_pairing_session),
  CONSTRAINT fk_device_pairing_session_home FOREIGN KEY (id_home)
    REFERENCES homes.home(id_home) ON DELETE NO ACTION,
  CONSTRAINT fk_device_pairing_session_user FOREIGN KEY (id_user)
    REFERENCES auth."user"(id_user) ON DELETE NO ACTION,
  CONSTRAINT fk_device_pairing_session_device FOREIGN KEY (completed_device_id)
    REFERENCES devices.device(id_device) ON DELETE NO ACTION,
  CONSTRAINT uq_device_pairing_session_request UNIQUE (id_home, id_user, request_key_hash),
  CONSTRAINT uq_device_pairing_session_token UNIQUE (token_hash),
  CONSTRAINT ck_device_pairing_session_hashes CHECK (
    request_key_hash ~ '^[0-9a-f]{64}$' AND token_hash ~ '^[0-9a-f]{64}$'
  ),
  CONSTRAINT ck_device_pairing_session_method CHECK (method IN ('AP', 'BLE')),
  CONSTRAINT ck_device_pairing_session_status CHECK (
    status IN ('PENDING', 'DEVICE_IDENTIFIED', 'WAITING_FOR_MQTT', 'CONNECTED',
      'COMPLETED', 'EXPIRED', 'CANCELLED', 'FAILED')
  ),
  CONSTRAINT ck_device_pairing_session_identity CHECK (
    (status NOT IN ('DEVICE_IDENTIFIED', 'WAITING_FOR_MQTT', 'CONNECTED', 'COMPLETED')
      OR (manufacturer_device_id IS NOT NULL AND model_code IS NOT NULL AND identity_reported_at IS NOT NULL))
  ),
  CONSTRAINT ck_device_pairing_session_completed_device CHECK (
    (status = 'COMPLETED' AND completed_device_id IS NOT NULL)
    OR (status <> 'COMPLETED' AND completed_device_id IS NULL)
  ),
  CONSTRAINT ck_device_pairing_session_failure CHECK (
    (status = 'FAILED' AND failure_code IS NOT NULL)
    OR (status <> 'FAILED' AND failure_code IS NULL)
  )
);

CREATE INDEX idx_device_pairing_session_expiry
  ON devices.device_pairing_session (expires_at)
  WHERE status IN ('PENDING', 'DEVICE_IDENTIFIED', 'WAITING_FOR_MQTT', 'CONNECTED');

CREATE TRIGGER trg_device_pairing_session_updated_at
BEFORE UPDATE ON devices.device_pairing_session
FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

CREATE FUNCTION devices.fn_guard_pairing_session_transition()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog, devices
AS $$
BEGIN
  IF NEW.id_home IS DISTINCT FROM OLD.id_home
    OR NEW.id_user IS DISTINCT FROM OLD.id_user
    OR NEW.request_key_hash IS DISTINCT FROM OLD.request_key_hash
    OR NEW.token_hash IS DISTINCT FROM OLD.token_hash
    OR NEW.method IS DISTINCT FROM OLD.method
    OR NEW.expires_at IS DISTINCT FROM OLD.expires_at
    OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'pairing session identity fields are immutable' USING ERRCODE = '23514';
  END IF;

  IF NEW.status = OLD.status THEN
    RAISE EXCEPTION 'pairing session state must advance' USING ERRCODE = '23514';
  END IF;

  IF NOT (
    (OLD.status = 'PENDING' AND NEW.status IN ('DEVICE_IDENTIFIED', 'EXPIRED', 'CANCELLED', 'FAILED'))
    OR (OLD.status = 'DEVICE_IDENTIFIED' AND NEW.status IN ('WAITING_FOR_MQTT', 'EXPIRED', 'CANCELLED', 'FAILED'))
    OR (OLD.status = 'WAITING_FOR_MQTT' AND NEW.status IN ('CONNECTED', 'EXPIRED', 'CANCELLED', 'FAILED'))
    OR (OLD.status = 'CONNECTED' AND NEW.status IN ('COMPLETED', 'CANCELLED', 'EXPIRED', 'FAILED'))
  ) THEN
    RAISE EXCEPTION 'invalid pairing session state transition: % -> %', OLD.status, NEW.status
      USING ERRCODE = '23514';
  END IF;

  IF OLD.manufacturer_device_id IS NOT NULL
    AND NEW.status NOT IN ('CANCELLED', 'EXPIRED')
    AND (NEW.manufacturer_device_id IS DISTINCT FROM OLD.manufacturer_device_id
      OR NEW.model_code IS DISTINCT FROM OLD.model_code
      OR NEW.firmware_version IS DISTINCT FROM OLD.firmware_version
      OR NEW.identity_reported_at IS DISTINCT FROM OLD.identity_reported_at) THEN
    RAISE EXCEPTION 'reported Shelly identity is immutable for this session' USING ERRCODE = '23514';
  END IF;

  IF NEW.status = 'COMPLETED' AND OLD.status <> 'CONNECTED' THEN
    RAISE EXCEPTION 'pairing cannot complete before authenticated broker connection' USING ERRCODE = '23514';
  END IF;
  IF NEW.status = 'COMPLETED' AND NOT EXISTS (
    SELECT 1 FROM devices.device d
    WHERE d.id_device = NEW.completed_device_id
      AND d.id_home = NEW.id_home
      AND d.manufacturer_device_id = NEW.manufacturer_device_id
      AND d.status = 'ACTIVE' AND d.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'completed device does not match the reported Shelly identity' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_guard_pairing_session_transition() FROM PUBLIC;

CREATE TRIGGER trg_device_pairing_session_state_guard
BEFORE UPDATE ON devices.device_pairing_session
FOR EACH ROW EXECUTE FUNCTION devices.fn_guard_pairing_session_transition();

ALTER TABLE devices.device_pairing_session ENABLE ROW LEVEL SECURITY;

CREATE POLICY device_pairing_session_app_select
ON devices.device_pairing_session FOR SELECT TO smarthome_runtime_app
USING (id_user = auth.fn_current_user_id() AND homes.fn_can_manage_home(id_home));

CREATE POLICY device_pairing_session_app_insert
ON devices.device_pairing_session FOR INSERT TO smarthome_runtime_app
WITH CHECK (id_user = auth.fn_current_user_id() AND homes.fn_can_manage_home(id_home));

CREATE POLICY device_pairing_session_app_update
ON devices.device_pairing_session FOR UPDATE TO smarthome_runtime_app
USING (id_user = auth.fn_current_user_id() AND homes.fn_can_manage_home(id_home))
WITH CHECK (id_user = auth.fn_current_user_id() AND homes.fn_can_manage_home(id_home));

GRANT SELECT, INSERT, UPDATE ON devices.device_pairing_session TO smarthome_runtime_app;
GRANT SELECT ON devices.device_pairing_session TO smarthome_admin;

COMMENT ON TABLE devices.device_pairing_session IS
  'Short-lived OWNER pairing sessions. Identity reported by mobile is not proof of possession; completion requires a later authenticated broker handshake.';

-- Claim the identity atomically. The lock expires with the transaction, and
-- expired session rows do not reserve an ID indefinitely.
CREATE FUNCTION devices.fn_claim_pairing_identity(
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
