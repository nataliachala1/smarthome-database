-- Permisos de ejecución para helpers técnicos RLS.
-- Se centralizan aquí para que las policies no administren privilegios.

GRANT EXECUTE ON FUNCTION auth.fn_current_user_id() TO smarthome_app;
GRANT EXECUTE ON FUNCTION auth.fn_is_active_user(UUID) TO smarthome_app, smarthome_ingest, smarthome_worker;
GRANT EXECUTE ON FUNCTION auth.fn_is_system_admin() TO smarthome_app;

GRANT EXECUTE ON FUNCTION homes.fn_has_home_membership(UUID, TEXT[]) TO smarthome_app;
GRANT EXECUTE ON FUNCTION homes.fn_is_home_member(UUID, TEXT[]) TO smarthome_app;
GRANT EXECUTE ON FUNCTION homes.fn_is_home_owner(UUID) TO smarthome_app;
GRANT EXECUTE ON FUNCTION homes.fn_is_home_active(UUID) TO smarthome_app, smarthome_ingest, smarthome_worker;
GRANT EXECUTE ON FUNCTION homes.fn_can_manage_home(UUID) TO smarthome_app;
GRANT EXECUTE ON FUNCTION homes.fn_can_create_initial_owner(UUID, UUID) TO smarthome_app;
GRANT EXECUTE ON FUNCTION homes.fn_owner_membership_update_allowed(UUID, UUID, UUID, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ) TO smarthome_app;
GRANT EXECUTE ON FUNCTION homes.fn_self_membership_transition_allowed(UUID, UUID, UUID, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ) TO smarthome_app;

GRANT EXECUTE ON FUNCTION devices.fn_is_active_device_type(UUID) TO smarthome_app;
GRANT EXECUTE ON FUNCTION devices.fn_is_device_owner(UUID) TO smarthome_app;
GRANT EXECUTE ON FUNCTION devices.fn_can_view_device(UUID, TEXT[]) TO smarthome_app;
GRANT EXECUTE ON FUNCTION devices.fn_can_manage_device(UUID) TO smarthome_app;
GRANT EXECUTE ON FUNCTION devices.fn_device_app_update_allowed(UUID, UUID, UUID, TEXT, TEXT, BOOLEAN, TEXT, TEXT, TIMESTAMPTZ) TO smarthome_app;
GRANT EXECUTE ON FUNCTION devices.fn_is_ingestable_device(UUID) TO smarthome_ingest;
GRANT EXECUTE ON FUNCTION devices.fn_device_belongs_to_home(UUID, UUID) TO smarthome_ingest, smarthome_worker;

GRANT EXECUTE ON FUNCTION notifications.fn_recipient_has_home_role(UUID, UUID, TEXT[], TEXT[]) TO smarthome_ingest, smarthome_worker;
GRANT EXECUTE ON FUNCTION notifications.fn_can_generate_alert(UUID, UUID, UUID, TEXT) TO smarthome_ingest;
GRANT EXECUTE ON FUNCTION notifications.fn_notification_status_transition_allowed(UUID, UUID, TEXT) TO smarthome_app;
