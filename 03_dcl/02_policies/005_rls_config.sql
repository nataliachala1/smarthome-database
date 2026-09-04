-- ============================================================
-- RLS — Esquema config
-- Archivo: 03_dcl/02_policies/005_rls_config.sql
--
-- Tablas:
--   config.user_preference
--   config.home_recommendation_preference
--   config.home_notification_preference
--
-- Reglas:
--
-- user_preference:
--   USER -> solo su propia configuración.
--
-- home_recommendation_preference:
--   OWNER  -> consultar/configurar.
--   MEMBER -> consultar.
--   GUEST  -> sin acceso.
--   worker -> consultar hogares activos.
--
-- home_notification_preference:
--   OWNER -> consultar/configurar.
--   ingest/worker -> consultar hogares activos.
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
--
-- UNIQUE(id_user) impide tener más de una configuración
-- global por usuario.
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



-- ============================================================
-- config.home_recommendation_preference
-- ============================================================

ALTER TABLE config.home_recommendation_preference
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- SELECT — aplicación
--
-- OWNER y MEMBER pueden consultar el estado de recomendaciones
-- de un hogar operativo.
--
-- GUEST no participa en recomendaciones.
-- ------------------------------------------------------------

CREATE POLICY home_recommendation_preference_app_select_policy
ON config.home_recommendation_preference
FOR SELECT
TO smarthome_app
USING (

    homes.fn_is_home_active(id_home)

    AND homes.fn_is_home_member(
        id_home,
        ARRAY[
            'OWNER',
            'MEMBER'
        ]::TEXT[]
    )
);


-- ------------------------------------------------------------
-- INSERT — aplicación
--
-- Solo OWNER de un hogar ACTIVE.
-- ------------------------------------------------------------

CREATE POLICY home_recommendation_preference_app_insert_policy
ON config.home_recommendation_preference
FOR INSERT
TO smarthome_app
WITH CHECK (
    homes.fn_can_manage_home(id_home)
);


-- ------------------------------------------------------------
-- UPDATE — aplicación
--
-- Solo OWNER.
--
-- El GRANT por columnas limita la actualización a:
--   recommendations_enabled
--   recommendation_frequency
-- ------------------------------------------------------------

CREATE POLICY home_recommendation_preference_app_update_policy
ON config.home_recommendation_preference
FOR UPDATE
TO smarthome_app
USING (
    homes.fn_can_manage_home(id_home)
)
WITH CHECK (
    homes.fn_can_manage_home(id_home)
);


-- ------------------------------------------------------------
-- SELECT — worker
--
-- El worker únicamente procesa preferencias de hogares
-- actualmente activos.
-- ------------------------------------------------------------

CREATE POLICY home_recommendation_preference_worker_select_policy
ON config.home_recommendation_preference
FOR SELECT
TO smarthome_worker
USING (
    homes.fn_is_home_active(id_home)
);



-- ============================================================
-- config.home_notification_preference
-- ============================================================

ALTER TABLE config.home_notification_preference
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- SELECT — aplicación
--
-- La configuración del comportamiento de notificaciones
-- del hogar es administrada por OWNER.
--
-- MEMBER/GUEST consultan sus notificaciones en
-- notifications.notification, no esta configuración.
-- ------------------------------------------------------------

CREATE POLICY home_notification_preference_app_select_policy
ON config.home_notification_preference
FOR SELECT
TO smarthome_app
USING (
    homes.fn_can_manage_home(id_home)
);


-- ------------------------------------------------------------
-- INSERT — aplicación
--
-- Solo OWNER.
-- ------------------------------------------------------------

CREATE POLICY home_notification_preference_app_insert_policy
ON config.home_notification_preference
FOR INSERT
TO smarthome_app
WITH CHECK (
    homes.fn_can_manage_home(id_home)
);


-- ------------------------------------------------------------
-- UPDATE — aplicación
--
-- Solo OWNER.
--
-- El GRANT por columnas protege id_home y PK.
-- ------------------------------------------------------------

CREATE POLICY home_notification_preference_app_update_policy
ON config.home_notification_preference
FOR UPDATE
TO smarthome_app
USING (
    homes.fn_can_manage_home(id_home)
)
WITH CHECK (
    homes.fn_can_manage_home(id_home)
);


-- ------------------------------------------------------------
-- SELECT — ingesta MQTT
--
-- El flujo IoT consulta preferencias antes de generar
-- notificaciones derivadas de alertas.
--
-- No puede modificar configuración.
-- ------------------------------------------------------------

CREATE POLICY home_notification_preference_ingest_select_policy
ON config.home_notification_preference
FOR SELECT
TO smarthome_ingest
USING (
    homes.fn_is_home_active(id_home)
);


-- ------------------------------------------------------------
-- SELECT — worker
--
-- Utilizado para recomendaciones/eventos programados que
-- puedan generar notificaciones.
-- ------------------------------------------------------------

CREATE POLICY home_notification_preference_worker_select_policy
ON config.home_notification_preference
FOR SELECT
TO smarthome_worker
USING (
    homes.fn_is_home_active(id_home)
);