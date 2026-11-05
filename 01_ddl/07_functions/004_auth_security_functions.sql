-- ============================================================
-- FUNCIONES TECNICAS DE SEGURIDAD - auth
-- Archivo: 01_ddl/07_functions/004_auth_security_functions.sql
--
-- Estas funciones son helpers para RLS.
-- La logica de login, hash, bloqueo y recuperacion pertenece
-- a NestJS + Prisma.
-- ============================================================

-- ------------------------------------------------------------
-- Usuario actual de la transaccion.
--
-- Prisma/NestJS debe establecer, dentro de la transaccion:
--   SET LOCAL app.current_user_id = '<uuid>';
--
-- current_setting(..., true) evita error si la variable no fue
-- definida. En ese caso la funcion devuelve NULL.
--
-- Esta funcion NO es SECURITY DEFINER y se mantiene ejecutable
-- por PUBLIC porque no consulta tablas ni eleva privilegios.
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
-- Usuario funcional activo.
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
-- Rol global SYSTEM_ADMIN.
--
-- Modelo esperado del baseline actual:
--   auth."user".id_role -> auth.role.id_role
--
-- Los roles de hogar OWNER/MEMBER/GUEST NO se consultan aqui.
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
