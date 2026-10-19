-- ============================================================
-- IoT ingestion: ALERT notification INSERT ... RETURNING
-- ============================================================

GRANT SELECT (
    id_notification,
    id_user,
    id_alert,
    id_home,
    id_device,
    type,
    title,
    message,
    status,
    priority,
    channel,
    created_at,
    updated_at
)
ON notifications.notification
TO smarthome_ingest;


CREATE POLICY notification_ingest_select_policy
ON notifications.notification
FOR SELECT
TO smarthome_ingest
USING (
    type = 'ALERT'

    AND id_alert IS NOT NULL
    AND id_home IS NOT NULL
    AND id_device IS NOT NULL

    AND auth.fn_is_active_user(id_user)

    AND notifications.fn_recipient_has_home_role(
        id_user,
        id_home,
        ARRAY[
            'OWNER',
            'MEMBER',
            'GUEST'
        ]::TEXT[],
        ARRAY['ACTIVE']::TEXT[]
    )
);