REVOKE EXECUTE ON FUNCTION notifications.fn_notification_status_transition_allowed(UUID, UUID, TEXT) FROM smarthome_app;
REVOKE EXECUTE ON FUNCTION notifications.fn_can_generate_alert(UUID, UUID, UUID, TEXT) FROM smarthome_ingest;
REVOKE EXECUTE ON FUNCTION notifications.fn_recipient_has_home_role(UUID, UUID, TEXT[], TEXT[]) FROM smarthome_ingest, smarthome_worker;

REVOKE EXECUTE ON FUNCTION devices.fn_device_belongs_to_home(UUID, UUID) FROM smarthome_ingest, smarthome_worker;
REVOKE EXECUTE ON FUNCTION devices.fn_is_ingestable_device(UUID) FROM smarthome_ingest;
REVOKE EXECUTE ON FUNCTION devices.fn_device_app_update_allowed(UUID, UUID, UUID, UUID, TEXT, TEXT, BOOLEAN, TEXT, TEXT, TIMESTAMPTZ) FROM smarthome_app;
REVOKE EXECUTE ON FUNCTION devices.fn_can_manage_device(UUID) FROM smarthome_app;
REVOKE EXECUTE ON FUNCTION devices.fn_can_view_device(UUID, TEXT[]) FROM smarthome_app;
REVOKE EXECUTE ON FUNCTION devices.fn_is_device_owner(UUID) FROM smarthome_app;
REVOKE EXECUTE ON FUNCTION devices.fn_is_active_device_type(UUID) FROM smarthome_app;
REVOKE EXECUTE ON FUNCTION devices.fn_is_active_zone(UUID, UUID) FROM smarthome_app;

REVOKE EXECUTE ON FUNCTION homes.fn_self_membership_transition_allowed(UUID, UUID, UUID, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ) FROM smarthome_app;
REVOKE EXECUTE ON FUNCTION homes.fn_owner_membership_update_allowed(UUID, UUID, UUID, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ) FROM smarthome_app;
REVOKE EXECUTE ON FUNCTION homes.fn_can_create_initial_owner(UUID, UUID) FROM smarthome_app;
REVOKE EXECUTE ON FUNCTION homes.fn_can_manage_home(UUID) FROM smarthome_app;
REVOKE EXECUTE ON FUNCTION homes.fn_is_home_active(UUID) FROM smarthome_app, smarthome_ingest, smarthome_worker;
REVOKE EXECUTE ON FUNCTION homes.fn_is_home_owner(UUID) FROM smarthome_app;
REVOKE EXECUTE ON FUNCTION homes.fn_is_home_member(UUID, TEXT[]) FROM smarthome_app;
REVOKE EXECUTE ON FUNCTION homes.fn_has_home_membership(UUID, TEXT[]) FROM smarthome_app;

REVOKE EXECUTE ON FUNCTION auth.fn_is_system_admin() FROM smarthome_app;
REVOKE EXECUTE ON FUNCTION auth.fn_is_active_user(UUID) FROM smarthome_app, smarthome_ingest, smarthome_worker;
REVOKE EXECUTE ON FUNCTION auth.fn_current_user_id() FROM smarthome_app;
