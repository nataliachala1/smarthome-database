-- ============================================================
-- ROLLBACK - helpers RLS notifications
-- ============================================================

DROP FUNCTION IF EXISTS notifications.fn_notification_status_transition_allowed(
    UUID, UUID, TEXT
);
DROP FUNCTION IF EXISTS notifications.fn_can_generate_alert(
    UUID, UUID, UUID, TEXT
);
DROP FUNCTION IF EXISTS notifications.fn_recipient_has_home_role(
    UUID, UUID, TEXT[], TEXT[]
);
