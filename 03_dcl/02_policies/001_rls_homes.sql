-- ============================================================
-- RLS — homes schema
-- File: 03_dcl/02_policies/001_rls_homes.sql
--
-- Model:
--   homes.home
--   homes.home_member
--
-- Source of contextual authorization:
--   homes.home_member
--
-- Roles:
--   OWNER
--   MEMBER
--   GUEST
--
-- There are no DELETE policies.
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
--   OWNER / MEMBER / GUEST can read.
--
-- PENDING:
--   The invited user can read the basic home information
--   needed to decide whether to accept the invitation.
--
-- deleted_at is not filtered here because the OWNER must be able
-- to recover/reactivate a DEACTIVATED home.
-- ------------------------------------------------------------

CREATE POLICY home_select_policy
ON homes.home
FOR SELECT
TO smarthome_runtime_app
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
-- The authenticated user can only create homes whose
-- created_by is that same user.
-- ------------------------------------------------------------

CREATE POLICY home_insert_policy
ON homes.home
FOR INSERT
TO smarthome_runtime_app
WITH CHECK (
    created_by = auth.fn_current_user_id()
    AND auth.fn_is_active_user(created_by)
    AND status = 'ACTIVE'
    AND deleted_at IS NULL
);


-- ------------------------------------------------------------
-- UPDATE
--
-- Active OWNER only.
--
-- home.status = ACTIVE is not required in USING because the OWNER
-- must be able to reactivate a DEACTIVATED home.
-- ------------------------------------------------------------

CREATE POLICY home_update_policy
ON homes.home
FOR UPDATE
TO smarthome_runtime_app
USING (
    homes.fn_is_home_owner(id_home)
)
WITH CHECK (
    homes.fn_is_home_owner(id_home)
);

-- ------------------------------------------------------------
-- UPDATE
--
-- OWNER only.
-- Includes the soft delete of the home.
-- ------------------------------------------------------------

-- ============================================================
-- homes.home_member
-- ============================================================

ALTER TABLE homes.home_member
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- SELECT
--
-- The OWNER can read every membership of the home.
--
-- Each user can read their own membership in any state,
-- including PENDING so that an invitation can be accepted.
--
-- MEMBER/GUEST do not automatically get the full list
-- of home members.
-- ------------------------------------------------------------

CREATE POLICY home_member_select_policy
ON homes.home_member
FOR SELECT
TO smarthome_runtime_app
USING (
    (id_user = auth.fn_current_user_id()
     AND auth.fn_is_active_user(auth.fn_current_user_id()))

    OR

    homes.fn_is_home_owner(id_home)
);


-- ------------------------------------------------------------
-- INSERT
--
-- Case A:
--   create the initial OWNER membership after registering
--   a home.
--
-- Case B:
--   the OWNER invites a MEMBER/GUEST in PENDING state.
-- ------------------------------------------------------------

CREATE POLICY home_member_insert_policy
ON homes.home_member
FOR INSERT
TO smarthome_runtime_app
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

    -- MEMBER/GUEST invitation
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
-- Case A:
-- OWNER:
--   - switches MEMBER <-> GUEST;
--   - revokes PENDING;
--   - revokes ACTIVE.
--
-- Case B:
-- The MEMBER/GUEST themself:
--   - accepts PENDING;
--   - rejects PENDING;
--   - leaves ACTIVE.
--
-- The OWNER membership cannot be modified through this
-- generic operation.
-- ------------------------------------------------------------

CREATE POLICY home_member_update_policy
ON homes.home_member
FOR UPDATE
TO smarthome_runtime_app
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