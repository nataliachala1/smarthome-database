-- ============================================================
-- RLS — Esquema identity_audit
-- Archivo:
-- 03_dcl/02_policies/007_rls_identity_audit.sql
--
-- Tabla:
--   identity_audit.audit_log
--
-- Reglas:
--
-- INSERT:
--   NestJS puede registrar eventos semánticos.
--
-- SELECT:
--   únicamente usuarios globales SYSTEM_ADMIN.
--
-- UPDATE:
--   prohibido.
--
-- DELETE:
--   prohibido.
--
-- actor_type:
--   USER
--   SYSTEM
--   INFRASTRUCTURE
--
-- Los eventos INFRASTRUCTURE no se insertan mediante
-- smarthome_app; pertenecen al flujo técnico administrativo.
-- ============================================================


-- ============================================================
-- identity_audit.audit_log
-- ============================================================

ALTER TABLE identity_audit.audit_log
ENABLE ROW LEVEL SECURITY;



-- ============================================================
-- SELECT — SYSTEM_ADMIN
--
-- smarthome_app es la conexión utilizada por NestJS.
-- El rol PostgreSQL no distingue usuarios funcionales;
-- auth.fn_is_system_admin() resuelve si el usuario actual
-- posee el rol global SYSTEM_ADMIN.
--
-- USER normal:
--   SELECT -> 0 filas.
--
-- SYSTEM_ADMIN:
--   SELECT -> todos los eventos permitidos.
-- ============================================================

CREATE POLICY audit_system_admin_select_policy
ON identity_audit.audit_log
FOR SELECT
TO smarthome_app
USING (
    auth.fn_is_system_admin()
);


-- ============================================================
-- INSERT — NestJS
--
-- Caso A — USER autenticado
--
--   app.current_user_id existe
--   y debe coincidir con audit_log.id_user.
--
--
-- Caso B — autenticación todavía no completada
--
--   app.current_user_id = NULL
--   únicamente se permiten eventos del módulo AUTH.
--
-- Esto permite registrar, por ejemplo:
--
--   AUTH_LOGIN_FAILED
--   AUTH_ACCOUNT_LOCKED
--   AUTH_PASSWORD_RECOVERY_REQUESTED
--   AUTH_PASSWORD_RECOVERY_COMPLETED
--
--
-- Caso C — evento SYSTEM
--
--   actor_type = SYSTEM
--   id_user debe ser NULL.
--
--
-- INFRASTRUCTURE no se permite mediante smarthome_app.
-- ============================================================

CREATE POLICY audit_app_insert_policy
ON identity_audit.audit_log
FOR INSERT
TO smarthome_app
WITH CHECK (

    -- ========================================================
    -- EVENTO DE USUARIO
    -- ========================================================

    (
        actor_type = 'USER'

        AND (

            -- Usuario autenticado:
            -- el actor almacenado debe ser el usuario actual.
            (
                auth.fn_current_user_id() IS NOT NULL

                AND id_user = auth.fn_current_user_id()
            )

            OR

            -- Usuario todavía no autenticado:
            -- únicamente eventos relacionados con AUTH.
            (
                auth.fn_current_user_id() IS NULL

                AND module = 'AUTH'
            )
        )
    )


    OR


    -- ========================================================
    -- EVENTO GENERADO POR EL SISTEMA
    -- ========================================================

    (
        actor_type = 'SYSTEM'

        AND id_user IS NULL
    )
);