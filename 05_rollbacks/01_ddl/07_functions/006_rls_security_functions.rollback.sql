-- ============================================================
-- ROLLBACK - helpers RLS auth/homes
-- ============================================================

DROP FUNCTION IF EXISTS homes.fn_self_membership_transition_allowed(
    UUID, UUID, UUID, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ
);

DROP FUNCTION IF EXISTS homes.fn_owner_membership_update_allowed(
    UUID, UUID, UUID, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ
);

DROP FUNCTION IF EXISTS homes.fn_can_create_initial_owner(UUID, UUID);
DROP FUNCTION IF EXISTS homes.fn_can_manage_home(UUID);
DROP FUNCTION IF EXISTS homes.fn_is_home_active(UUID);
DROP FUNCTION IF EXISTS homes.fn_is_home_owner(UUID);
DROP FUNCTION IF EXISTS homes.fn_is_home_member(UUID, TEXT[]);
DROP FUNCTION IF EXISTS homes.fn_has_home_membership(UUID, TEXT[]);
