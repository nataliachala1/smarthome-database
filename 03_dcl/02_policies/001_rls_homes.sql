-- ============================================================
-- RLS — Esquema homes
-- Archivo: 03_dcl/02_policies/001_rls_homes.sql
--
-- Modelo:
--   homes.home
--   homes.home_member
--
-- Fuente de autorización contextual:
--   homes.home_member
--
-- Roles:
--   OWNER
--   MEMBER
--   GUEST
--
-- No existen policies DELETE.
-- ============================================================


-- ============================================================
-- homes.home
-- ============================================================

ALTER TABLE homes.home
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- SELECT
--
-- ACTIVE:
--   OWNER / MEMBER / GUEST pueden consultar.
--
-- PENDING:
--   El usuario invitado puede consultar la información básica
--   del hogar necesaria para decidir si acepta la invitación.
--
-- No filtramos deleted_at aquí porque el OWNER debe poder
-- recuperar/reactivar un hogar DEACTIVATED.
-- ------------------------------------------------------------

CREATE POLICY home_select_policy
ON homes.home
FOR SELECT
TO smarthome_app
USING (
    homes.fn_is_home_owner(id_home)
    OR (
        homes.fn_is_home_active(id_home)
        AND homes.fn_has_home_membership(id_home, ARRAY['PENDING', 'ACTIVE']::TEXT[])
    )
);


-- ------------------------------------------------------------
-- INSERT
--
-- El usuario autenticado solo puede crear hogares cuyo
-- created_by sea él mismo.
-- ------------------------------------------------------------

CREATE POLICY home_insert_policy
ON homes.home
FOR INSERT
TO smarthome_app
WITH CHECK (
    created_by = auth.fn_current_user_id()
    AND auth.fn_is_active_user(created_by)
    AND status = 'ACTIVE'
    AND deleted_at IS NULL
);


-- ------------------------------------------------------------
-- UPDATE
--
-- Solo OWNER activo.
--
-- No exigimos home.status = ACTIVE en USING porque el OWNER
-- debe poder reactivar un hogar DEACTIVATED.
-- ------------------------------------------------------------

CREATE POLICY home_update_policy
ON homes.home
FOR UPDATE
TO smarthome_app
USING (
    homes.fn_is_home_owner(id_home)
)
WITH CHECK (
    homes.fn_is_home_owner(id_home)
);

-- ------------------------------------------------------------
-- UPDATE
--
-- Únicamente OWNER.
-- Incluye soft delete de zona.
-- ------------------------------------------------------------

-- ============================================================
-- homes.home_member
-- ============================================================

ALTER TABLE homes.home_member
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- SELECT
--
-- El OWNER puede consultar todas las membresías de su hogar.
--
-- Cada usuario puede consultar su propia membresía en cualquier
-- estado, incluido PENDING para poder aceptar una invitación.
--
-- MEMBER/GUEST no obtienen automáticamente el listado completo
-- de miembros del hogar.
-- ------------------------------------------------------------

CREATE POLICY home_member_select_policy
ON homes.home_member
FOR SELECT
TO smarthome_app
USING (
    (id_user = auth.fn_current_user_id()
     AND auth.fn_is_active_user(auth.fn_current_user_id()))

    OR

    homes.fn_is_home_owner(id_home)
);


-- ------------------------------------------------------------
-- INSERT
--
-- Caso A:
--   crear la membresía OWNER inicial después de registrar
--   un hogar.
--
-- Caso B:
--   OWNER invita MEMBER/GUEST en estado PENDING.
-- ------------------------------------------------------------

CREATE POLICY home_member_insert_policy
ON homes.home_member
FOR INSERT
TO smarthome_app
WITH CHECK (

    -- OWNER inicial
    (
        role = 'OWNER'
        AND status = 'ACTIVE'
        AND id_user = auth.fn_current_user_id()
        AND invited_by IS NULL
        AND accepted_at IS NOT NULL
        AND ended_at IS NULL
        AND homes.fn_can_create_initial_owner(
            id_home,
            id_user
        )
    )

    OR

    -- Invitación de MEMBER/GUEST
    (
        homes.fn_can_manage_home(id_home)

        AND role IN ('MEMBER', 'GUEST')
        AND status = 'PENDING'

        AND invited_by = auth.fn_current_user_id()

        AND accepted_at IS NULL
        AND ended_at IS NULL

        AND id_user <> auth.fn_current_user_id()
    )
);


-- ------------------------------------------------------------
-- UPDATE
--
-- Caso A:
-- OWNER:
--   - cambia MEMBER <-> GUEST;
--   - revoca PENDING;
--   - revoca ACTIVE.
--
-- Caso B:
-- El propio MEMBER/GUEST:
--   - acepta PENDING;
--   - rechaza PENDING;
--   - abandona ACTIVE.
--
-- La membresía OWNER no puede modificarse mediante esta
-- operación genérica.
-- ------------------------------------------------------------

CREATE POLICY home_member_update_policy
ON homes.home_member
FOR UPDATE
TO smarthome_app
USING (

    (
        homes.fn_can_manage_home(id_home)
        AND role IN ('MEMBER', 'GUEST')
        AND status IN ('PENDING', 'ACTIVE')
    )

    OR

    (
        id_user = auth.fn_current_user_id()
        AND role IN ('MEMBER', 'GUEST')
        AND status IN ('PENDING', 'ACTIVE')
    )
)
WITH CHECK (

    homes.fn_owner_membership_update_allowed(
        id_home_member,
        id_home,
        id_user,
        role,
        status,
        accepted_at,
        ended_at
    )

    OR

    homes.fn_self_membership_transition_allowed(
        id_home_member,
        id_home,
        id_user,
        role,
        status,
        accepted_at,
        ended_at
    )
);