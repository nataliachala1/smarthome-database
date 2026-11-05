-- ============================================================
-- HELPERS RLS - auth/homes
-- Archivo: 01_ddl/07_functions/006_rls_security_functions.sql
--
-- Fuente de autorizacion contextual:
--   homes.home_member
--
-- Roles de hogar:
--   OWNER | MEMBER | GUEST
--
-- Estados de membresia:
--   PENDING | ACTIVE | REVOKED | LEFT
--
-- Todas las funciones SECURITY DEFINER fijan search_path y
-- revocan EXECUTE a PUBLIC. DCL concede EXECUTE solo a los
-- roles tecnicos que lo requieren.
-- ============================================================

-- ------------------------------------------------------------
-- ¿Existe una membresia del usuario actual en alguno de los
-- estados solicitados?
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION homes.fn_has_home_membership(
    p_home_id UUID,
    p_statuses TEXT[]
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, auth, homes
AS $$
    SELECT
        p_home_id IS NOT NULL
        AND p_statuses IS NOT NULL
        AND auth.fn_is_active_user(auth.fn_current_user_id())
        AND EXISTS (
            SELECT 1
            FROM homes.home_member hm
            WHERE hm.id_home = p_home_id
              AND hm.id_user = auth.fn_current_user_id()
              AND hm.status = ANY (p_statuses)
        );
$$;

REVOKE ALL ON FUNCTION homes.fn_has_home_membership(UUID, TEXT[]) FROM PUBLIC;


-- ------------------------------------------------------------
-- Membresia ACTIVE con uno de los roles indicados.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION homes.fn_is_home_member(
    p_home_id UUID,
    p_roles TEXT[]
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, auth, homes
AS $$
    SELECT
        p_home_id IS NOT NULL
        AND p_roles IS NOT NULL
        AND auth.fn_is_active_user(auth.fn_current_user_id())
        AND EXISTS (
            SELECT 1
            FROM homes.home_member hm
            WHERE hm.id_home = p_home_id
              AND hm.id_user = auth.fn_current_user_id()
              AND hm.status = 'ACTIVE'
              AND hm.role = ANY (p_roles)
        );
$$;

REVOKE ALL ON FUNCTION homes.fn_is_home_member(UUID, TEXT[]) FROM PUBLIC;


-- ------------------------------------------------------------
-- OWNER activo del hogar.
-- No exige que el hogar este ACTIVE porque el OWNER debe poder
-- consultar/reactivar un hogar desactivado.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION homes.fn_is_home_owner(
    p_home_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, auth, homes
AS $$
    SELECT
        p_home_id IS NOT NULL
        AND auth.fn_is_active_user(auth.fn_current_user_id())
        AND EXISTS (
            SELECT 1
            FROM homes.home_member hm
            WHERE hm.id_home = p_home_id
              AND hm.id_user = auth.fn_current_user_id()
              AND hm.role = 'OWNER'
              AND hm.status = 'ACTIVE'
        );
$$;

REVOKE ALL ON FUNCTION homes.fn_is_home_owner(UUID) FROM PUBLIC;


-- ------------------------------------------------------------
-- Hogar operativo.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION homes.fn_is_home_active(
    p_home_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, homes
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM homes.home h
        WHERE h.id_home = p_home_id
          AND h.status = 'ACTIVE'
          AND h.deleted_at IS NULL
    );
$$;

REVOKE ALL ON FUNCTION homes.fn_is_home_active(UUID) FROM PUBLIC;


-- ------------------------------------------------------------
-- OWNER + hogar operativo.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION homes.fn_can_manage_home(
    p_home_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, homes
AS $$
    SELECT
        homes.fn_is_home_owner(p_home_id)
        AND homes.fn_is_home_active(p_home_id);
$$;

REVOKE ALL ON FUNCTION homes.fn_can_manage_home(UUID) FROM PUBLIC;


-- ------------------------------------------------------------
-- Permite crear la membresia OWNER inicial inmediatamente
-- despues de registrar el hogar.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION homes.fn_can_create_initial_owner(
    p_home_id UUID,
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, auth, homes
AS $$
    SELECT
        p_home_id IS NOT NULL
        AND p_user_id IS NOT NULL
        AND p_user_id = auth.fn_current_user_id()
        AND auth.fn_is_active_user(p_user_id)
        AND EXISTS (
            SELECT 1
            FROM homes.home h
            WHERE h.id_home = p_home_id
              AND h.created_by = p_user_id
              AND h.status = 'ACTIVE'
              AND h.deleted_at IS NULL
        )
        AND NOT EXISTS (
            SELECT 1
            FROM homes.home_member hm
            WHERE hm.id_home = p_home_id
              AND hm.role = 'OWNER'
              AND hm.status = 'ACTIVE'
        );
$$;

REVOKE ALL ON FUNCTION homes.fn_can_create_initial_owner(UUID, UUID) FROM PUBLIC;


-- ------------------------------------------------------------
-- UPDATE de una membresia MEMBER/GUEST realizado por OWNER.
--
-- Permitido:
--   * mantener PENDING/ACTIVE y cambiar MEMBER <-> GUEST;
--   * PENDING/ACTIVE -> REVOKED con ended_at informado.
--
-- Nunca permite modificar una membresia OWNER.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION homes.fn_owner_membership_update_allowed(
    p_home_member_id UUID,
    p_home_id UUID,
    p_user_id UUID,
    p_new_role TEXT,
    p_new_status TEXT,
    p_new_accepted_at TIMESTAMPTZ,
    p_new_ended_at TIMESTAMPTZ
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, homes
AS $$
DECLARE
    v_old homes.home_member%ROWTYPE;
BEGIN
    IF NOT homes.fn_can_manage_home(p_home_id) THEN
        RETURN FALSE;
    END IF;

    SELECT *
      INTO v_old
      FROM homes.home_member hm
     WHERE hm.id_home_member = p_home_member_id;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    IF v_old.id_home <> p_home_id
       OR v_old.id_user <> p_user_id
       OR v_old.role NOT IN ('MEMBER', 'GUEST')
       OR v_old.status NOT IN ('PENDING', 'ACTIVE')
       OR p_new_role NOT IN ('MEMBER', 'GUEST') THEN
        RETURN FALSE;
    END IF;

    -- Cambio de rol sin alterar las fechas históricas.
    IF p_new_status = v_old.status THEN
        RETURN p_new_accepted_at IS NOT DISTINCT FROM v_old.accepted_at
           AND p_new_ended_at IS NOT DISTINCT FROM v_old.ended_at;
    END IF;

    -- Revocacion por OWNER.
    IF p_new_status = 'REVOKED' THEN
        RETURN p_new_role = v_old.role
           AND p_new_accepted_at IS NOT DISTINCT FROM v_old.accepted_at
           AND p_new_ended_at IS NOT NULL;
    END IF;

    RETURN FALSE;
END;
$$;

REVOKE ALL
ON FUNCTION homes.fn_owner_membership_update_allowed(
    UUID, UUID, UUID, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ
)
FROM PUBLIC;


-- ------------------------------------------------------------
-- Transiciones que el propio MEMBER/GUEST puede realizar.
--
--   PENDING -> ACTIVE : aceptar invitacion
--   PENDING -> LEFT   : rechazar invitacion
--   ACTIVE  -> LEFT   : abandonar hogar
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION homes.fn_self_membership_transition_allowed(
    p_home_member_id UUID,
    p_home_id UUID,
    p_user_id UUID,
    p_new_role TEXT,
    p_new_status TEXT,
    p_new_accepted_at TIMESTAMPTZ,
    p_new_ended_at TIMESTAMPTZ
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, auth, homes
AS $$
DECLARE
    v_old homes.home_member%ROWTYPE;
BEGIN
    IF p_user_id IS NULL
       OR p_user_id <> auth.fn_current_user_id()
       OR NOT auth.fn_is_active_user(p_user_id) THEN
        RETURN FALSE;
    END IF;

    SELECT *
      INTO v_old
      FROM homes.home_member hm
     WHERE hm.id_home_member = p_home_member_id;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    IF v_old.id_home <> p_home_id
       OR v_old.id_user <> p_user_id
       OR v_old.role NOT IN ('MEMBER', 'GUEST')
       OR p_new_role <> v_old.role
       OR v_old.status NOT IN ('PENDING', 'ACTIVE') THEN
        RETURN FALSE;
    END IF;

    -- Aceptar invitacion.
    IF v_old.status = 'PENDING' AND p_new_status = 'ACTIVE' THEN
        RETURN p_new_accepted_at IS NOT NULL
           AND p_new_ended_at IS NULL
           AND homes.fn_is_home_active(p_home_id);
    END IF;

    -- Rechazar invitacion pendiente.
    IF v_old.status = 'PENDING' AND p_new_status = 'LEFT' THEN
        RETURN p_new_accepted_at IS NULL
           AND p_new_ended_at IS NOT NULL;
    END IF;

    -- Abandonar una membresia activa.
    IF v_old.status = 'ACTIVE' AND p_new_status = 'LEFT' THEN
        RETURN p_new_accepted_at IS NOT DISTINCT FROM v_old.accepted_at
           AND p_new_ended_at IS NOT NULL;
    END IF;

    RETURN FALSE;
END;
$$;

REVOKE ALL
ON FUNCTION homes.fn_self_membership_transition_allowed(
    UUID, UUID, UUID, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ
)
FROM PUBLIC;
