-- Regression test for SQL032: a SQL025 uncertain operation with NULL retry_at
-- must receive a 120-second quiet window before reconciliation can claim it.
-- Run with psql -v ON_ERROR_STOP=1 against a disposable database after SQL032.
-- This test uses only synthetic fixtures and rolls its transaction back.
\set ON_ERROR_STOP on
BEGIN;

DO $test$
DECLARE
  v_user UUID;
  v_home UUID;
  v_session UUID := gen_random_uuid();
  v_operation UUID;
  v_token_hash TEXT := repeat('b',64);
  v_prepare_token UUID;
  v_claim RECORD;
  v_status TEXT;
  v_retry_at TIMESTAMPTZ;
  v_before TIMESTAMPTZ;
BEGIN
  INSERT INTO auth."user"(name,email,password_hash,status,email_verified)
  VALUES ('SQL032 synthetic test','sql032-retry-null@example.invalid',
          'test-only-not-a-credential','ACTIVE',true)
  RETURNING id_user INTO v_user;

  INSERT INTO homes.home(created_by,name)
  VALUES (v_user,'SQL032 retry null regression fixture')
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
    'AP','WAITING_FOR_MQTT','sql032_retry_null','S4SW-001P16EU',
    'synthetic-firmware',clock_timestamp(),clock_timestamp()+interval '1 hour'
  );

  SELECT operation_id INTO v_operation
  FROM devices.fn_reserve_mqtt_pairing_operation(
    v_session,'sql032_retry_null',v_user,v_token_hash
  );
  IF v_operation IS NULL THEN
    RAISE EXCEPTION 'SQL032 regression fixture reservation failed';
  END IF;

  SELECT assigned_token INTO v_prepare_token
  FROM devices.fn_claim_mqtt_pairing_preparation(v_operation,60);
  IF v_prepare_token IS NULL THEN
    RAISE EXCEPTION 'SQL032 regression fixture preparation claim failed';
  END IF;
  IF NOT devices.fn_report_mqtt_pairing_uncertain(
    v_operation,v_prepare_token,'MQTT_ADMIN_OUTCOME_UNKNOWN'
  ) THEN
    RAISE EXCEPTION 'SQL025 uncertain transition failed';
  END IF;

  IF EXISTS (
    SELECT 1 FROM devices.mqtt_pairing_operation
    WHERE id_mqtt_pairing_operation=v_operation
      AND (status<>'RECONCILIATION_REQUIRED' OR retry_at IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'fixture did not reach RECONCILIATION_REQUIRED with NULL retry_at';
  END IF;

  v_before:=clock_timestamp();
  SELECT * INTO v_claim
  FROM devices.fn_claim_mqtt_pairing_revocation(60);
  IF FOUND THEN
    RAISE EXCEPTION 'uncertain operation was claimed before its quiet window';
  END IF;

  SELECT status,retry_at INTO v_status,v_retry_at
  FROM devices.mqtt_pairing_operation
  WHERE id_mqtt_pairing_operation=v_operation;
  IF v_status<>'RECONCILIATION_REQUIRED'
     OR v_retry_at IS NULL
     OR v_retry_at < v_before+interval '119 seconds' THEN
    RAISE EXCEPTION 'NULL retry_at did not receive a 120-second quiet window';
  END IF;

  SELECT * INTO v_claim
  FROM devices.fn_claim_mqtt_pairing_revocation(60);
  IF FOUND THEN
    RAISE EXCEPTION 'operation was claimed on an immediate subsequent poll';
  END IF;

  RAISE NOTICE 'PASS SQL032 RECONCILIATION_REQUIRED NULL retry_at waits before claim';
END
$test$;

ROLLBACK;
