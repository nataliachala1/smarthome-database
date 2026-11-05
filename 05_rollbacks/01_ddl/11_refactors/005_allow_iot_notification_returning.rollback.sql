DROP POLICY IF EXISTS notification_ingest_select_policy
ON notifications.notification;

REVOKE SELECT (
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
FROM smarthome_ingest;