-- ============================================================
-- RLS — identity_audit schema
-- File:
-- 03_dcl/02_policies/007_rls_identity_audit.sql
--
-- Table:
--   identity_audit.audit_log
--
-- Rules:
--
-- INSERT:
--   NestJS can record semantic events.
--
-- SELECT:
--   only global SYSTEM_ADMIN users.
--
-- UPDATE:
--   forbidden.
--
-- DELETE:
--   forbidden.
--
-- actor_type:
--   USER
--   SYSTEM
--   INFRASTRUCTURE
--
-- INFRASTRUCTURE events are not inserted through
-- smarthome_runtime_app; they belong to the technical administrative flow.
-- ============================================================


-- ============================================================
-- identity_audit.audit_log
-- ============================================================

ALTER TABLE identity_audit.audit_log
ENABLE ROW LEVEL SECURITY;



-- ============================================================
-- SELECT — SYSTEM_ADMIN
--
-- smarthome_runtime_app is the connection used by NestJS.
-- The PostgreSQL role does not distinguish functional users;
-- auth.fn_is_system_admin() resolves whether the current user
-- holds the global SYSTEM_ADMIN role.
--
-- Regular USER:
--   SELECT -> 0 rows.
--
-- SYSTEM_ADMIN:
--   SELECT -> every allowed event.
-- ============================================================

CREATE POLICY audit_system_admin_select_policy
ON identity_audit.audit_log
FOR SELECT
TO smarthome_runtime_app
USING (
    auth.fn_is_system_admin()
);


-- ============================================================
-- INSERT — NestJS
--
-- Case A — authenticated USER
--
--   app.current_user_id exists
--   and must match audit_log.id_user.
--
--
-- Case B — authentication not completed yet
--
--   app.current_user_id = NULL
--   only AUTH module events are allowed.
--
-- This allows recording, for example:
--
--   AUTH_LOGIN_FAILED
--   AUTH_ACCOUNT_LOCKED
--   AUTH_PASSWORD_RECOVERY_REQUESTED
--   AUTH_PASSWORD_RECOVERY_COMPLETED
--
--
-- Case C — SYSTEM event
--
--   actor_type = SYSTEM
--   id_user must be NULL.
--
--
-- INFRASTRUCTURE is not allowed through smarthome_runtime_app.
-- ============================================================

CREATE POLICY audit_app_insert_policy
ON identity_audit.audit_log
FOR INSERT
TO smarthome_runtime_app
WITH CHECK (

    -- ========================================================
    -- USER EVENT
    -- ========================================================

    (
        actor_type = 'USER'

        AND (

            -- Authenticated user:
            -- the stored actor must be the current user.
            (
                auth.fn_current_user_id() IS NOT NULL

                AND id_user = auth.fn_current_user_id()
            )

            OR

            -- User not authenticated yet:
            -- only AUTH-related events.
            (
                auth.fn_current_user_id() IS NULL

                AND module = 'AUTH'
            )
        )
    )


    OR


    -- ========================================================
    -- SYSTEM-GENERATED EVENT
    -- ========================================================

    (
        actor_type = 'SYSTEM'

        AND id_user IS NULL
    )
);