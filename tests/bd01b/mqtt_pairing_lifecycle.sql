-- BD-01B synthetic lifecycle regression.
-- Run only on a disposable PostgreSQL database after all Liquibase changesets.
-- No broker, Flespi, device, or real credential is used. The calls representing
-- broker inspection/authentication/revocation are contract fixtures only; this
-- SQL test cannot prove real Mosquitto identity or Shelly RPC provenance.
-- The transaction is rolled back after asserting reserve -> prepare -> bootstrap
-- -> enable -> RPC candidate -> auth state -> revocation.
\set ON_ERROR_STOP on
BEGIN;

DO $bd01_flow$
DECLARE
  v_user UUID;
  v_home UUID;
  v_session UUID := gen_random_uuid();
  v_operation UUID;
  v_identity UUID;
  v_username TEXT;
  v_client_id TEXT;
  v_role_name TEXT;
  v_token_hash TEXT := repeat('b', 64);
  v_prepare_token UUID;
  v_enable_token UUID;
  v_revoke_token UUID;
  v_rpc_id UUID;
  v_result BOOLEAN;
  v_finish TEXT;
  v_claim RECORD;
  v_bootstrap RECORD;
  v_status TEXT;
BEGIN
  INSERT INTO auth."user"(name,email,password_hash,status,email_verified)
  VALUES ('BD01B synthetic lifecycle','bd01b-lifecycle@example.invalid',
          'synthetic-test-only-not-a-credential','ACTIVE',true)
  RETURNING id_user INTO v_user;

  INSERT INTO homes.home(created_by,name)
  VALUES (v_user,'BD01B synthetic lifecycle fixture')
  RETURNING id_home INTO v_home;

  INSERT INTO homes.home_member(
    id_home,id_user,role,status,invited_by,accepted_at
  ) VALUES (v_home,v_user,'OWNER','ACTIVE',NULL,clock_timestamp());

  INSERT INTO devices.device_pairing_session(
    id_device_pairing_session,id_home,id_user,request_key_hash,token_hash,
    method,status,manufacturer_device_id,model_code,firmware_version,
    identity_reported_at,expires_at
  ) VALUES (
    v_session,v_home,v_user,repeat('a',64),v_token_hash,
    'AP','WAITING_FOR_MQTT','bd01b_flow_synthetic','S4SW-001P16EU',
    'synthetic-firmware',clock_timestamp(),clock_timestamp()+interval '1 hour'
  );

  SELECT operation_id,identity_id,username,client_id,role_name
    INTO v_operation,v_identity,v_username,v_client_id,v_role_name
  FROM devices.fn_reserve_mqtt_pairing_operation(
    v_session,'home/devices/bd01b_flow_synthetic',v_user,v_token_hash
  );
  IF v_operation IS NULL OR v_identity IS NULL OR v_username IS NULL
     OR v_client_id IS NULL OR v_role_name IS NULL THEN
    RAISE EXCEPTION 'BD01B synthetic reservation failed';
  END IF;

  SELECT assigned_token INTO v_prepare_token
  FROM devices.fn_claim_mqtt_pairing_preparation(v_operation,60);
  IF v_prepare_token IS NULL THEN
    RAISE EXCEPTION 'BD01B synthetic preparation claim failed';
  END IF;

  IF NOT devices.fn_insert_mqtt_preparation_secret_if_absent(
    v_operation,v_prepare_token,1::smallint,'synthetic-test-key','0123456789ABCDEF',
    repeat('A',58),repeat('B',22)
  ) THEN
    RAISE EXCEPTION 'BD01B synthetic encrypted envelope insert failed';
  END IF;

  SELECT devices.fn_confirm_mqtt_pairing_prepared(
    v_operation,v_prepare_token,v_identity,v_username,v_client_id,v_role_name
  ) INTO v_result;
  IF v_result IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'BD01B synthetic prepared-disabled confirmation failed';
  END IF;

  SELECT * INTO v_bootstrap
  FROM devices.fn_get_authorized_mqtt_bootstrap(v_operation,v_user,v_token_hash);
  IF NOT FOUND OR v_bootstrap.operation_id IS DISTINCT FROM v_operation
     OR v_bootstrap.identity_id IS DISTINCT FROM v_identity
     OR v_bootstrap.ciphertext IS DISTINCT FROM repeat('A',58) THEN
    RAISE EXCEPTION 'BD01B synthetic authorized bootstrap failed';
  END IF;

  SELECT devices.fn_request_mqtt_enable(v_operation,v_user,v_token_hash)
    INTO v_result;
  IF v_result IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'BD01B synthetic enable request failed';
  END IF;
  SELECT lease_token INTO v_enable_token
  FROM devices.fn_claim_mqtt_enable(v_operation,60);
  IF v_enable_token IS NULL THEN
    RAISE EXCEPTION 'BD01B synthetic enable claim failed';
  END IF;
  SELECT devices.fn_confirm_mqtt_enabled(
    v_operation,v_enable_token,v_username,v_client_id,v_role_name
  ) INTO v_result;
  IF v_result IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'BD01B synthetic enable confirmation failed';
  END IF;

  SELECT rpc_id INTO v_rpc_id
  FROM devices.fn_issue_mqtt_rpc_challenge(v_operation);
  IF v_rpc_id IS NULL OR NOT devices.fn_consume_mqtt_rpc_candidate(v_operation,v_rpc_id) THEN
    RAISE EXCEPTION 'BD01B synthetic RPC candidate lifecycle failed';
  END IF;
  SELECT devices.fn_confirm_mqtt_broker_authentication(
    v_operation,v_rpc_id,v_username,v_client_id,v_role_name
  ) INTO v_result;
  IF v_result IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'BD01B synthetic authenticated transition failed';
  END IF;

  SELECT status INTO v_status FROM devices.mqtt_pairing_operation
  WHERE id_mqtt_pairing_operation=v_operation;
  IF v_status <> 'AUTH_VERIFIED' OR NOT EXISTS (
    SELECT 1 FROM devices.device_pairing_session
    WHERE id_device_pairing_session=v_session AND status='CONNECTED'
  ) THEN
    RAISE EXCEPTION 'BD01B synthetic authenticated state mismatch';
  END IF;

  -- Cancellation is a legitimate terminal session transition and starts the
  -- normal fail-closed revocation worker path.
  UPDATE devices.device_pairing_session
  SET status='CANCELLED',cancelled_at=clock_timestamp()
  WHERE id_device_pairing_session=v_session AND status='CONNECTED';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BD01B synthetic session cancellation failed';
  END IF;

  SELECT lease_token INTO v_revoke_token
  FROM devices.fn_claim_mqtt_pairing_revocation(60);
  IF v_revoke_token IS NULL THEN
    RAISE EXCEPTION 'BD01B synthetic revocation claim failed';
  END IF;
  SELECT devices.fn_finish_mqtt_pairing_revocation(
    v_operation,v_revoke_token,'IDENTITY_ABSENT',NULL
  ) INTO v_finish;
  IF v_finish <> 'RETRY_SCHEDULED' THEN
    RAISE EXCEPTION 'BD01B synthetic first absence observation was not quarantined: %',v_finish;
  END IF;

  -- Exercise the real 120-second safety quiet window rather than mutating its
  -- timestamp. This deliberate delay is part of the destructive-free test.
  PERFORM pg_sleep(121);

  SELECT lease_token INTO v_revoke_token
  FROM devices.fn_claim_mqtt_pairing_revocation(60);
  IF v_revoke_token IS NULL THEN
    RAISE EXCEPTION 'BD01B synthetic second revocation claim failed';
  END IF;
  SELECT devices.fn_finish_mqtt_pairing_revocation(
    v_operation,v_revoke_token,'IDENTITY_ABSENT',NULL
  ) INTO v_finish;
  IF v_finish <> 'REVOKED' THEN
    RAISE EXCEPTION 'BD01B synthetic revocation did not finish: %',v_finish;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM devices.mqtt_pairing_operation
    WHERE id_mqtt_pairing_operation=v_operation AND status='REVOKED'
      AND revoked_at IS NOT NULL
  ) OR EXISTS (
    SELECT 1 FROM devices.mqtt_preparation_secret
    WHERE id_mqtt_pairing_operation=v_operation
  ) OR NOT EXISTS (
    SELECT 1 FROM devices.mqtt_pairing_revocation_attestation
    WHERE id_mqtt_pairing_operation=v_operation AND outcome='IDENTITY_ABSENT'
  ) THEN
    RAISE EXCEPTION 'BD01B synthetic revocation final assertions failed';
  END IF;

  RAISE NOTICE 'PASS BD01B synthetic pairing lifecycle; broker observations are fixtures only';
END
$bd01_flow$;

ROLLBACK;
