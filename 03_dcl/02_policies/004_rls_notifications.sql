-- ============================================================
-- RLS — Esquema notifications
-- Archivo: 03_dcl/02_policies/004_rls_notifications.sql
--
-- Tablas:
--   notifications.alert_rule
--   notifications.alert
--   notifications.notification
--
-- Reglas:
--
-- alert_rule:
--   OWNER -> consultar/configurar.
--
-- alert:
--   sistema/ingest -> generar.
--
-- notification:
--   cada usuario -> consultar únicamente las propias.
--   ingest -> ALERT.
--   worker -> RECOMMENDATION / SYSTEM.
--
-- No existen policies DELETE.
-- ============================================================


-- ============================================================
-- notifications.alert_rule
-- ============================================================

ALTER TABLE notifications.alert_rule
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- SELECT — aplicación
--
-- Una regla de umbral es configuración operativa.
-- OWNER puede consultarla incluso si el dispositivo está
-- desactivado.
-- ------------------------------------------------------------

CREATE POLICY alert_rule_app_select_policy
ON notifications.alert_rule
FOR SELECT
TO smarthome_app
USING (
    devices.fn_is_device_owner(id_device)
);


-- ------------------------------------------------------------
-- INSERT — aplicación
--
-- Solo OWNER y hogar operativo.
-- ------------------------------------------------------------

CREATE POLICY alert_rule_app_insert_policy
ON notifications.alert_rule
FOR INSERT
TO smarthome_app
WITH CHECK (
    devices.fn_can_manage_device(id_device)
    AND deleted_at IS NULL
);


-- ------------------------------------------------------------
-- UPDATE — aplicación
--
-- Solo OWNER.
--
-- El GRANT por columnas impide cambiar id_device.
-- Permite activar/desactivar o hacer soft delete de la regla.
-- ------------------------------------------------------------

CREATE POLICY alert_rule_app_update_policy
ON notifications.alert_rule
FOR UPDATE
TO smarthome_app
USING (
    devices.fn_can_manage_device(id_device)
)
WITH CHECK (
    devices.fn_can_manage_device(id_device)
);


-- ------------------------------------------------------------
-- SELECT — ingesta
--
-- Solo reglas activas, no eliminadas y de dispositivos
-- pertenecientes a hogares operativos.
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
-- INSERT — ingesta
--
-- No WITH CHECK(TRUE).
--
-- Valida:
--   alert type
--   rule cuando corresponda
--   device
--   home
--   home operativo
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
-- SELECT — usuario
--
-- Cada usuario ve exclusivamente sus propias notificaciones.
--
-- No comprobamos membresía actual del hogar porque una
-- notificación histórica debe seguir perteneciendo al usuario
-- incluso si posteriormente sale del hogar.
-- ------------------------------------------------------------

CREATE POLICY notification_app_select_policy
ON notifications.notification
FOR SELECT
TO smarthome_app
USING (
    id_user = auth.fn_current_user_id()
);


-- ------------------------------------------------------------
-- UPDATE — usuario
--
-- El GRANT limita físicamente el UPDATE a:
--   status
--   updated_at
--
-- Además impedimos transiciones arbitrarias.
-- ------------------------------------------------------------

CREATE POLICY notification_app_update_policy
ON notifications.notification
FOR UPDATE
TO smarthome_app
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
-- INSERT — ingesta
--
-- Alertas del flujo IoT.
--
-- OWNER / MEMBER / GUEST pueden ser destinatarios.
-- La FK compuesta garantiza que:
--
-- notification.alert
-- notification.home
-- notification.device
--
-- pertenecen al mismo contexto.
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
-- Caso A:
--   RECOMMENDATION
--   solo OWNER / MEMBER.
--
-- Caso B:
--   SYSTEM
--   puede ser global para un usuario o contextual al hogar.
-- ------------------------------------------------------------

CREATE POLICY notification_worker_insert_policy
ON notifications.notification
FOR INSERT
TO smarthome_worker
WITH CHECK (

    id_alert IS NULL

    AND auth.fn_is_active_user(id_user)

    AND (

        -- ====================================================
        -- RECOMMENDATION
        -- ====================================================
        (
            type = 'RECOMMENDATION'

            AND id_home IS NOT NULL

            AND homes.fn_is_home_active(id_home)

            AND notifications.fn_recipient_has_home_role(
                id_user,
                id_home,
                ARRAY[
                    'OWNER',
                    'MEMBER'
                ]::TEXT[],
                ARRAY['ACTIVE']::TEXT[]
            )

            AND (
                id_device IS NULL

                OR

                devices.fn_device_belongs_to_home(
                    id_device,
                    id_home
                )
            )
        )

        OR

        -- ====================================================
        -- SYSTEM
        -- ====================================================
        (
            type = 'SYSTEM'

            AND (

                -- Notificación global dirigida a un usuario.
                (
                    id_home IS NULL
                    AND id_device IS NULL
                )

                OR

                -- Notificación contextual de un hogar.
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

                        OR

                        devices.fn_device_belongs_to_home(
                            id_device,
                            id_home
                        )
                    )
                )
            )
        )
    )
);