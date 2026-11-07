-- ============================================================
-- RLS — notifications schema
-- File: 03_dcl/02_policies/004_rls_notifications.sql
--
-- Tables:
--   notifications.alert_rule
--   notifications.alert
--   notifications.notification
--
-- Rules:
--
-- alert_rule:
--   OWNER -> read/configure.
--
-- alert:
--   system/ingest -> generate.
--
-- notification:
--   each user -> reads only their own.
--   ingest -> ALERT.
--   worker -> SYSTEM.
--
-- There are no DELETE policies.
-- ============================================================


-- ============================================================
-- notifications.alert_rule
-- ============================================================

ALTER TABLE notifications.alert_rule
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- SELECT — application
--
-- A threshold rule is operational configuration.
-- The OWNER can read it even if the device is
-- deactivated.
-- ------------------------------------------------------------

CREATE POLICY alert_rule_app_select_policy
ON notifications.alert_rule
FOR SELECT
TO smarthome_runtime_app
USING (
    devices.fn_is_device_owner(id_device)
);


-- ------------------------------------------------------------
-- INSERT — application
--
-- OWNER only and an operational home.
-- ------------------------------------------------------------

CREATE POLICY alert_rule_app_insert_policy
ON notifications.alert_rule
FOR INSERT
TO smarthome_runtime_app
WITH CHECK (
    devices.fn_can_manage_device(id_device)
    AND deleted_at IS NULL
);


-- ------------------------------------------------------------
-- UPDATE — application
--
-- OWNER only.
--
-- The column-level GRANT prevents changing id_device.
-- Allows enabling/disabling or soft deleting the rule.
-- ------------------------------------------------------------

CREATE POLICY alert_rule_app_update_policy
ON notifications.alert_rule
FOR UPDATE
TO smarthome_runtime_app
USING (
    devices.fn_can_manage_device(id_device)
)
WITH CHECK (
    devices.fn_can_manage_device(id_device)
);


-- ------------------------------------------------------------
-- SELECT — ingest
--
-- Only active, non-deleted rules of devices
-- that belong to operational homes.
-- ------------------------------------------------------------

CREATE POLICY alert_rule_ingest_select_policy
ON notifications.alert_rule
FOR SELECT
TO smarthome_ingest
USING (
    active = TRUE
    AND deleted_at IS NULL

    AND EXISTS (
        SELECT 1
        FROM devices.device d
        WHERE d.id_device = alert_rule.id_device
          AND d.status = 'ACTIVE'
          AND d.deleted_at IS NULL
          AND homes.fn_is_home_active(d.id_home)
    )
);



-- ============================================================
-- notifications.alert
-- ============================================================

ALTER TABLE notifications.alert
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- INSERT — ingest
--
-- No WITH CHECK(TRUE).
--
-- Validates:
--   alert type
--   rule when applicable
--   device
--   home
--   operational home
-- ------------------------------------------------------------

CREATE POLICY alert_ingest_insert_policy
ON notifications.alert
FOR INSERT
TO smarthome_ingest
WITH CHECK (
    notifications.fn_can_generate_alert(
        id_alert_rule,
        id_device,
        id_home,
        alert_type
    )
);



-- ============================================================
-- notifications.notification
-- ============================================================

ALTER TABLE notifications.notification
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- SELECT — user
--
-- Each user sees only their own notifications.
--
-- Current home membership is not checked because a
-- historical notification must keep belonging to the user
-- even if they later leave the home.
-- ------------------------------------------------------------

CREATE POLICY notification_app_select_policy
ON notifications.notification
FOR SELECT
TO smarthome_runtime_app
USING (
    id_user = auth.fn_current_user_id()
);


-- ------------------------------------------------------------
-- UPDATE — user
--
-- The GRANT physically limits the UPDATE to:
--   status
--   updated_at
--
-- Arbitrary transitions are also prevented.
-- ------------------------------------------------------------

CREATE POLICY notification_app_update_policy
ON notifications.notification
FOR UPDATE
TO smarthome_runtime_app
USING (
    id_user = auth.fn_current_user_id()
)
WITH CHECK (
    notifications.fn_notification_status_transition_allowed(
        id_notification,
        id_user,
        status
    )
);


-- ------------------------------------------------------------
-- INSERT — ingest
--
-- Alerts from the IoT flow.
--
-- OWNER / MEMBER / GUEST can be recipients.
-- The composite FK guarantees that:
--
-- notification.alert
-- notification.home
-- notification.device
--
-- belong to the same context.
-- ------------------------------------------------------------

CREATE POLICY notification_ingest_insert_policy
ON notifications.notification
FOR INSERT
TO smarthome_ingest
WITH CHECK (

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


-- ------------------------------------------------------------
-- INSERT — worker
--
-- SYSTEM
--   can be global for a user or scoped to a home.
-- ------------------------------------------------------------

CREATE POLICY notification_worker_insert_policy
ON notifications.notification
FOR INSERT
TO smarthome_worker
WITH CHECK (
    id_alert IS NULL
    AND type = 'SYSTEM'
    AND auth.fn_is_active_user(id_user)
    AND (
        (
            id_home IS NULL
            AND id_device IS NULL
        )
        OR
        (
            id_home IS NOT NULL
            AND notifications.fn_recipient_has_home_role(
                id_user,
                id_home,
                ARRAY[
                    'OWNER',
                    'MEMBER',
                    'GUEST'
                ]::TEXT[],
                ARRAY[
                    'PENDING',
                    'ACTIVE'
                ]::TEXT[]
            )
            AND (
                id_device IS NULL
                OR devices.fn_device_belongs_to_home(id_device, id_home)
            )
        )
    )
);