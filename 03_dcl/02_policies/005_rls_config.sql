-- ============================================================
-- RLS — Esquema config
-- Archivo: 03_dcl/02_policies/005_rls_config.sql
--
-- Tablas:
--   config.user_preference
--
-- Reglas:
--   USER -> solo su propia configuración.
--
-- No existen policies DELETE.
-- ============================================================

-- ============================================================
-- config.user_preference
-- ============================================================

ALTER TABLE config.user_preference
ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------
-- SELECT
--
-- Cada usuario consulta exclusivamente su propia configuración.
-- ------------------------------------------------------------

CREATE POLICY user_preference_select_policy
ON config.user_preference
FOR SELECT
TO smarthome_app
USING (
    id_user = auth.fn_current_user_id()
);

-- ------------------------------------------------------------
-- INSERT
--
-- Solo se puede crear una preferencia para el usuario actual.
-- UNIQUE(id_user) impide tener más de una configuración global.
-- ------------------------------------------------------------

CREATE POLICY user_preference_insert_policy
ON config.user_preference
FOR INSERT
TO smarthome_app
WITH CHECK (
    id_user = auth.fn_current_user_id()
);

-- ------------------------------------------------------------
-- UPDATE
--
-- El GRANT por columnas impide cambiar id_user y la PK.
-- ------------------------------------------------------------

CREATE POLICY user_preference_update_policy
ON config.user_preference
FOR UPDATE
TO smarthome_app
USING (
    id_user = auth.fn_current_user_id()
)
WITH CHECK (
    id_user = auth.fn_current_user_id()
);

