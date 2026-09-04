-- ============================================================
-- ROLLBACK — RLS devices
-- ============================================================


-- ============================================================
-- devices.device_telemetry_raw
-- ============================================================

DROP POLICY IF EXISTS
telemetry_raw_ingest_insert_policy
ON devices.device_telemetry_raw;


ALTER TABLE devices.device_telemetry_raw
DISABLE ROW LEVEL SECURITY;


-- ============================================================
-- devices.device_schedule
-- ============================================================

DROP POLICY IF EXISTS
device_schedule_update_policy
ON devices.device_schedule;

DROP POLICY IF EXISTS
device_schedule_insert_policy
ON devices.device_schedule;

DROP POLICY IF EXISTS
device_schedule_select_policy
ON devices.device_schedule;


ALTER TABLE devices.device_schedule
DISABLE ROW LEVEL SECURITY;


-- ============================================================
-- devices.smart_device
-- ============================================================

DROP POLICY IF EXISTS
smart_device_ingest_select_policy
ON devices.smart_device;

DROP POLICY IF EXISTS
smart_device_app_update_policy
ON devices.smart_device;

DROP POLICY IF EXISTS
smart_device_app_insert_policy
ON devices.smart_device;

DROP POLICY IF EXISTS
smart_device_app_select_policy
ON devices.smart_device;


ALTER TABLE devices.smart_device
DISABLE ROW LEVEL SECURITY;


-- ============================================================
-- devices.device
-- ============================================================

DROP POLICY IF EXISTS
device_ingest_update_policy
ON devices.device;

DROP POLICY IF EXISTS
device_ingest_select_policy
ON devices.device;

DROP POLICY IF EXISTS
device_app_update_policy
ON devices.device;

DROP POLICY IF EXISTS
device_app_insert_policy
ON devices.device;

DROP POLICY IF EXISTS
device_app_select_policy
ON devices.device;


ALTER TABLE devices.device
DISABLE ROW LEVEL SECURITY;


-- ============================================================
-- EXECUTE helpers
-- ============================================================

