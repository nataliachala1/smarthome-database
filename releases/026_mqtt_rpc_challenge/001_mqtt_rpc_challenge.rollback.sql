-- Fail-closed rollback: no issued challenges may be erased, including consumed/expired ones.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM devices.mqtt_rpc_challenge) THEN
    RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='MQTT_026_ROLLBACK_BLOCKED_BY_RPC_HISTORY';
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION devices.fn_issue_mqtt_rpc_challenge(UUID) FROM smarthome_mqtt_rpc_worker;
REVOKE EXECUTE ON FUNCTION devices.fn_consume_mqtt_rpc_candidate(UUID,UUID) FROM smarthome_mqtt_rpc_worker;
DROP FUNCTION devices.fn_consume_mqtt_rpc_candidate(UUID,UUID);
DROP FUNCTION devices.fn_issue_mqtt_rpc_challenge(UUID);
DROP TRIGGER trg_guard_mqtt_rpc_challenge ON devices.mqtt_rpc_challenge;
DROP FUNCTION devices.fn_guard_mqtt_rpc_challenge();
DROP TABLE devices.mqtt_rpc_challenge;
REVOKE USAGE ON SCHEMA devices FROM smarthome_mqtt_rpc_worker;
DROP ROLE smarthome_mqtt_rpc_worker;
