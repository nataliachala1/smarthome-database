-- Rollback of SQL031: remove the authorized bootstrap retrieval function and
-- its delivery audit table. Pairing operations created by SQL022-030 are kept.
DROP FUNCTION IF EXISTS devices.fn_get_authorized_mqtt_bootstrap(uuid, uuid, text);
DROP TABLE IF EXISTS devices.mqtt_bootstrap_delivery_audit;
