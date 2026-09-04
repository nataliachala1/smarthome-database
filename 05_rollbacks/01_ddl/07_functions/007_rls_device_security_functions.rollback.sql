-- ============================================================
-- ROLLBACK - helpers RLS devices
-- ============================================================

DROP FUNCTION IF EXISTS devices.fn_device_app_update_allowed(
    UUID, UUID, UUID, UUID, TEXT, TEXT, BOOLEAN, TEXT, TEXT, TIMESTAMPTZ
);
DROP FUNCTION IF EXISTS devices.fn_is_ingestable_device(UUID);
DROP FUNCTION IF EXISTS devices.fn_can_manage_device(UUID);
DROP FUNCTION IF EXISTS devices.fn_can_view_device(UUID, TEXT[]);
DROP FUNCTION IF EXISTS devices.fn_is_device_owner(UUID);
DROP FUNCTION IF EXISTS devices.fn_is_active_device_type(UUID);
DROP FUNCTION IF EXISTS devices.fn_is_active_zone(UUID, UUID);
