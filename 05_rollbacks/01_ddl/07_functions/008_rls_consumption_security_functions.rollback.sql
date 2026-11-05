-- ============================================================
-- ROLLBACK - helper RLS consumption
-- ============================================================

DROP FUNCTION IF EXISTS devices.fn_device_belongs_to_home(UUID, UUID);
