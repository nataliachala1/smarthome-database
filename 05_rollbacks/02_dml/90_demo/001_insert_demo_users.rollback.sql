-- Rollback of 02_dml/90_demo/001_insert_demo_users.sql.
-- Removes the demo home, its devices and the four demo users, including
-- data generated while testing with them. Real data is never touched:
-- every statement is restricted to the fixed demo identifiers.
-- Pairing, MQTT identity and audit rows are not deleted; if a demo user
-- produced them, remove them manually before running this rollback.

DELETE FROM consumption.consumption_metric   WHERE id_home = 'd1000000-0000-4000-8000-000000000001';
DELETE FROM consumption.consumption_default  WHERE id_home = 'd1000000-0000-4000-8000-000000000001';
DELETE FROM consumption.consumption          WHERE id_home = 'd1000000-0000-4000-8000-000000000001';
DELETE FROM consumption.mqtt_ingest_dedup    WHERE id_home = 'd1000000-0000-4000-8000-000000000001';
DELETE FROM notifications.alert              WHERE id_home = 'd1000000-0000-4000-8000-000000000001';
DELETE FROM notifications.notification
 WHERE id_home = 'd1000000-0000-4000-8000-000000000001'
    OR id_user::text LIKE 'd0000000-0000-4000-8000-00000000000_';
DELETE FROM config.home_energy_goal          WHERE id_home = 'd1000000-0000-4000-8000-000000000001';
DELETE FROM config.home_energy_tariff        WHERE id_home = 'd1000000-0000-4000-8000-000000000001';
DELETE FROM devices.device_member_permission
 WHERE id_device IN (SELECT id_device FROM devices.device
                      WHERE id_home = 'd1000000-0000-4000-8000-000000000001');
DELETE FROM devices.device_schedule
 WHERE id_device IN (SELECT id_device FROM devices.device
                      WHERE id_home = 'd1000000-0000-4000-8000-000000000001');
DELETE FROM devices.device_telemetry_raw
 WHERE id_device IN (SELECT id_device FROM devices.device
                      WHERE id_home = 'd1000000-0000-4000-8000-000000000001');
DELETE FROM devices.smart_device
 WHERE id_device IN (SELECT id_device FROM devices.device
                      WHERE id_home = 'd1000000-0000-4000-8000-000000000001');
DELETE FROM devices.device                   WHERE id_home = 'd1000000-0000-4000-8000-000000000001';
DELETE FROM homes.home_member_permission
 WHERE id_home_member IN (SELECT id_home_member FROM homes.home_member
                           WHERE id_home = 'd1000000-0000-4000-8000-000000000001');
DELETE FROM homes.home_member                WHERE id_home = 'd1000000-0000-4000-8000-000000000001';
DELETE FROM homes.home                       WHERE id_home = 'd1000000-0000-4000-8000-000000000001';
DELETE FROM config.user_preference           WHERE id_user::text LIKE 'd0000000-0000-4000-8000-00000000000_';
DELETE FROM auth.recovery_token              WHERE id_user::text LIKE 'd0000000-0000-4000-8000-00000000000_';
DELETE FROM auth.refresh_token               WHERE id_user::text LIKE 'd0000000-0000-4000-8000-00000000000_';
DELETE FROM auth."user"                      WHERE id_user::text LIKE 'd0000000-0000-4000-8000-00000000000_';
