-- ============================================================
-- RLS — config schema
-- File: 03_dcl/02_policies/005_rls_config.sql
--
-- Tables:
--   config.user_preference
--
-- Rules:
--   USER -> only their own configuration.
--
-- There are no DELETE policies.
-- ============================================================

-- ============================================================
-- config.user_preference
-- ============================================================

ALTER TABLE config.user_preference
ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------
-- SELECT
--
-- Each user reads only their own configuration.
-- ------------------------------------------------------------

CREATE POLICY user_preference_select_policy
ON config.user_preference
FOR SELECT
TO smarthome_runtime_app
USING (
    id_user = auth.fn_current_user_id()
);

-- ------------------------------------------------------------
-- INSERT
--
-- A preference can only be created for the current user.
-- UNIQUE(id_user) prevents having more than one global configuration.
-- ------------------------------------------------------------

CREATE POLICY user_preference_insert_policy
ON config.user_preference
FOR INSERT
TO smarthome_runtime_app
WITH CHECK (
    id_user = auth.fn_current_user_id()
);

-- ------------------------------------------------------------
-- UPDATE
--
-- The column-level GRANT prevents changing id_user and the PK.
-- ------------------------------------------------------------

CREATE POLICY user_preference_update_policy
ON config.user_preference
FOR UPDATE
TO smarthome_runtime_app
USING (
    id_user = auth.fn_current_user_id()
)
WITH CHECK (
    id_user = auth.fn_current_user_id()
);

