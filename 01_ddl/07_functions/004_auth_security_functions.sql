-- ============================================================
-- TECHNICAL SECURITY FUNCTIONS - auth
-- File: 01_ddl/07_functions/004_auth_security_functions.sql
--
-- These functions are RLS helpers.
-- Login, hashing, lockout and recovery logic belongs
-- to NestJS + Prisma.
-- ============================================================

-- ------------------------------------------------------------
-- Current user of the transaction.
--
-- Prisma/NestJS must set, inside the transaction:
--   SET LOCAL app.current_user_id = '<uuid>';
--
-- current_setting(..., true) avoids an error if the variable was not
-- defined. In that case the function returns NULL.
--
-- This function is NOT SECURITY DEFINER and stays executable
-- by PUBLIC because it reads no tables and elevates no privileges.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth.fn_current_user_id()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(
        pg_catalog.current_setting('app.current_user_id', true),
        ''
    )::UUID;
$$;

REVOKE ALL ON FUNCTION auth.fn_current_user_id() FROM PUBLIC;

COMMENT ON FUNCTION auth.fn_current_user_id()
IS 'Devuelve app.current_user_id de la transaccion actual o NULL si no existe contexto.';


-- ------------------------------------------------------------
-- Active functional user.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth.fn_is_active_user(
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, auth
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM auth."user" u
        WHERE u.id_user = p_user_id
          AND u.status = 'ACTIVE'
    );
$$;

REVOKE ALL
ON FUNCTION auth.fn_is_active_user(UUID)
FROM PUBLIC;

COMMENT ON FUNCTION auth.fn_is_active_user(UUID)
IS 'Comprueba que un usuario de Smart Home exista y se encuentre ACTIVE.';


-- ------------------------------------------------------------
-- Global SYSTEM_ADMIN role.
--
-- Expected model of the current baseline:
--   auth."user".id_role -> auth.role.id_role
--
-- The home roles OWNER/MEMBER/GUEST are NOT checked here.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION auth.fn_is_system_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, auth
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM auth."user" u
        JOIN auth.role r
          ON r.id_role = u.id_role
        WHERE u.id_user = auth.fn_current_user_id()
          AND u.status = 'ACTIVE'
          AND r.name = 'SYSTEM_ADMIN'
    );
$$;

REVOKE ALL
ON FUNCTION auth.fn_is_system_admin()
FROM PUBLIC;

COMMENT ON FUNCTION auth.fn_is_system_admin()
IS 'Comprueba si el usuario del contexto RLS posee el rol global SYSTEM_ADMIN y esta ACTIVE.';
