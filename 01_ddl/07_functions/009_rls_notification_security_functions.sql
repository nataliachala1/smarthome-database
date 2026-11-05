-- ============================================================
-- HELPERS RLS - notifications
-- Archivo: 01_ddl/07_functions/009_rls_notification_security_functions.sql
-- ============================================================

-- ------------------------------------------------------------
-- Comprueba que un destinatario sea usuario activo y tenga una
-- membresia del hogar con los roles/estados permitidos.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION notifications.fn_recipient_has_home_role(
    p_user_id UUID,
    p_home_id UUID,
    p_roles TEXT[],
    p_statuses TEXT[]
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, auth, homes, notifications
AS $$
    SELECT
        p_user_id IS NOT NULL
        AND p_home_id IS NOT NULL
        AND p_roles IS NOT NULL
        AND p_statuses IS NOT NULL
        AND auth.fn_is_active_user(p_user_id)
        AND EXISTS (
            SELECT 1
            FROM homes.home_member hm
            WHERE hm.id_user = p_user_id
              AND hm.id_home = p_home_id
              AND hm.role = ANY (p_roles)
              AND hm.status = ANY (p_statuses)
        );
$$;

REVOKE ALL
ON FUNCTION notifications.fn_recipient_has_home_role(
    UUID, UUID, TEXT[], TEXT[]
)
FROM PUBLIC;


-- ------------------------------------------------------------
-- Valida el contexto de una alerta antes de que el rol de
-- ingesta pueda insertarla.
--
-- Regla general:
--   * hogar operativo;
--   * dispositivo operativo;
--   * dispositivo perteneciente al hogar;
--   * si se informa una regla, debe existir, estar activa,
--     no eliminada y pertenecer al mismo dispositivo.
--
-- La evaluacion del umbral/anomalia continua en NestJS; esta
-- funcion solo protege consistencia/autorizacion de datos.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION notifications.fn_can_generate_alert(
    p_alert_rule_id UUID,
    p_device_id UUID,
    p_home_id UUID,
    p_alert_type TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, homes, devices, notifications
AS $$
BEGIN
    IF p_device_id IS NULL OR p_home_id IS NULL OR p_alert_type IS NULL THEN
        RETURN FALSE;
    END IF;

    IF p_alert_type NOT IN ('THRESHOLD', 'ANOMALY', 'DEVICE_EVENT') THEN
        RETURN FALSE;
    END IF;

    IF NOT homes.fn_is_home_active(p_home_id)
       OR NOT devices.fn_is_ingestable_device(p_device_id)
       OR NOT devices.fn_device_belongs_to_home(p_device_id, p_home_id) THEN
        RETURN FALSE;
    END IF;

    IF p_alert_type = 'THRESHOLD' THEN
        IF p_alert_rule_id IS NULL THEN
            RETURN FALSE;
        END IF;
        RETURN EXISTS (
            SELECT 1
            FROM notifications.alert_rule ar
            WHERE ar.id_alert_rule = p_alert_rule_id
              AND ar.id_device = p_device_id
              AND ar.active = TRUE
              AND ar.deleted_at IS NULL
        );
    END IF;

    RETURN p_alert_rule_id IS NULL;
END;
$$;

REVOKE ALL
ON FUNCTION notifications.fn_can_generate_alert(UUID, UUID, UUID, TEXT)
FROM PUBLIC;


-- ------------------------------------------------------------
-- Transiciones permitidas para una notificacion del propio
-- usuario:
--   UNREAD -> READ
--   UNREAD -> DISMISSED
--   READ   -> DISMISSED
--
-- Repetir el mismo estado es idempotente.
-- No permite volver a UNREAD ni modificar notificaciones ajenas.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION notifications.fn_notification_status_transition_allowed(
    p_notification_id UUID,
    p_user_id UUID,
    p_new_status TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, auth, notifications
AS $$
DECLARE
    v_old_status TEXT;
    v_old_user_id UUID;
BEGIN
    IF p_notification_id IS NULL
       OR p_user_id IS NULL
       OR p_user_id <> auth.fn_current_user_id()
       OR NOT auth.fn_is_active_user(p_user_id) THEN
        RETURN FALSE;
    END IF;

    SELECT n.id_user, n.status
      INTO v_old_user_id, v_old_status
      FROM notifications.notification n
     WHERE n.id_notification = p_notification_id;

    IF NOT FOUND OR v_old_user_id <> p_user_id THEN
        RETURN FALSE;
    END IF;

    IF p_new_status = v_old_status THEN
        RETURN p_new_status IN ('UNREAD', 'READ', 'DISMISSED');
    END IF;

    RETURN
        (v_old_status = 'UNREAD' AND p_new_status IN ('READ', 'DISMISSED'))
        OR
        (v_old_status = 'READ' AND p_new_status = 'DISMISSED');
END;
$$;

REVOKE ALL
ON FUNCTION notifications.fn_notification_status_transition_allowed(
    UUID, UUID, TEXT
)
FROM PUBLIC;
