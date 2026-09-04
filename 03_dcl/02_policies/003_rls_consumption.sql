-- ============================================================
-- RLS — Esquema consumption
-- Archivo: 03_dcl/02_policies/003_rls_consumption.sql
--
-- Tablas:
--   consumption.consumption
--   consumption.consumption_metric
--   consumption.recommendation
--
-- Reglas funcionales:
--
-- Consumo/reportes:
--   OWNER  -> SELECT
--   MEMBER -> SELECT
--   GUEST  -> SELECT
--
-- Recomendaciones:
--   OWNER  -> SELECT
--   MEMBER -> SELECT
--   GUEST  -> NO
--
-- Escritura de lecturas:
--   smarthome_ingest
--
-- Agregados/recomendaciones:
--   smarthome_worker
--
-- No existen policies DELETE.
-- ============================================================


-- ============================================================
-- consumption.consumption
-- ============================================================

ALTER TABLE consumption.consumption
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- SELECT — usuario
--
-- OWNER:
-- Puede conservar acceso a históricos incluso si el hogar
-- fue desactivado.
--
-- MEMBER/GUEST:
-- Solo sobre hogares actualmente operativos.
-- ------------------------------------------------------------

CREATE POLICY consumption_app_select_policy
ON consumption.consumption
FOR SELECT
TO smarthome_app
USING (

    homes.fn_is_home_owner(id_home)

    OR

    (
        homes.fn_is_home_active(id_home)

        AND homes.fn_is_home_member(
            id_home,
            ARRAY['MEMBER', 'GUEST']::TEXT[]
        )
    )
);


-- ------------------------------------------------------------
-- SELECT — ingesta
--
-- Necesario para obtener la última lectura del dispositivo
-- y calcular energy_delta_kwh.
--
-- El GRANT ya limita las columnas visibles a:
--   id_device
--   energy_total_kwh
--   read_at
-- ------------------------------------------------------------

CREATE POLICY consumption_ingest_select_policy
ON consumption.consumption
FOR SELECT
TO smarthome_ingest
USING (

    devices.fn_is_ingestable_device(id_device)

    AND devices.fn_device_belongs_to_home(
        id_device,
        id_home
    )
);


-- ------------------------------------------------------------
-- INSERT — ingesta
--
-- Solo acepta lecturas cuyo dispositivo:
--   - existe;
--   - está operativo para ingesta;
--   - pertenece exactamente al id_home indicado.
--
-- La FK compuesta actúa además como segunda protección.
-- ------------------------------------------------------------

CREATE POLICY consumption_ingest_insert_policy
ON consumption.consumption
FOR INSERT
TO smarthome_ingest
WITH CHECK (

    devices.fn_is_ingestable_device(id_device)

    AND devices.fn_device_belongs_to_home(
        id_device,
        id_home
    )
);


-- ------------------------------------------------------------
-- SELECT — worker
--
-- El worker genera agregados de todos los hogares.
-- Es un rol técnico NOBYPASSRLS con permisos específicos.
-- ------------------------------------------------------------

CREATE POLICY consumption_worker_select_policy
ON consumption.consumption
FOR SELECT
TO smarthome_worker
USING (TRUE);



-- ============================================================
-- consumption.consumption_metric
-- ============================================================

ALTER TABLE consumption.consumption_metric
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- SELECT — usuario
--
-- Misma regla de históricos que consumption.consumption.
-- ------------------------------------------------------------

CREATE POLICY consumption_metric_app_select_policy
ON consumption.consumption_metric
FOR SELECT
TO smarthome_app
USING (

    homes.fn_is_home_owner(id_home)

    OR

    (
        homes.fn_is_home_active(id_home)

        AND homes.fn_is_home_member(
            id_home,
            ARRAY['MEMBER', 'GUEST']::TEXT[]
        )
    )
);


-- ------------------------------------------------------------
-- SELECT — worker
-- ------------------------------------------------------------

CREATE POLICY consumption_metric_worker_select_policy
ON consumption.consumption_metric
FOR SELECT
TO smarthome_worker
USING (TRUE);


-- ------------------------------------------------------------
-- INSERT — worker
--
-- No puede crear una métrica con dispositivo y hogar
-- incompatibles.
-- ------------------------------------------------------------

CREATE POLICY consumption_metric_worker_insert_policy
ON consumption.consumption_metric
FOR INSERT
TO smarthome_worker
WITH CHECK (

    devices.fn_device_belongs_to_home(
        id_device,
        id_home
    )
);


-- ------------------------------------------------------------
-- UPDATE — worker
--
-- El GRANT por columnas impide modificar identidad, periodo
-- y fechas del agregado.
-- ------------------------------------------------------------

CREATE POLICY consumption_metric_worker_update_policy
ON consumption.consumption_metric
FOR UPDATE
TO smarthome_worker
USING (TRUE)
WITH CHECK (

    devices.fn_device_belongs_to_home(
        id_device,
        id_home
    )
);



-- ============================================================
-- consumption.recommendation
-- ============================================================

ALTER TABLE consumption.recommendation
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- SELECT — usuario
--
-- Según SRS v2.0:
--   OWNER / MEMBER
--
-- GUEST no consulta recomendaciones.
-- ------------------------------------------------------------

CREATE POLICY recommendation_app_select_policy
ON consumption.recommendation
FOR SELECT
TO smarthome_app
USING (

    deleted_at IS NULL

    AND homes.fn_is_home_active(id_home)

    AND homes.fn_is_home_member(
        id_home,
        ARRAY['OWNER', 'MEMBER']::TEXT[]
    )
);


-- ------------------------------------------------------------
-- SELECT — worker
-- ------------------------------------------------------------

CREATE POLICY recommendation_worker_select_policy
ON consumption.recommendation
FOR SELECT
TO smarthome_worker
USING (TRUE);


-- ------------------------------------------------------------
-- INSERT — worker
--
-- Recomendación general:
--   id_device = NULL
--
-- Recomendación por dispositivo:
--   el dispositivo debe pertenecer al hogar.
--
-- No se generan recomendaciones nuevas para hogares
-- desactivados.
-- ------------------------------------------------------------

CREATE POLICY recommendation_worker_insert_policy
ON consumption.recommendation
FOR INSERT
TO smarthome_worker
WITH CHECK (

    homes.fn_is_home_active(id_home)

    AND deleted_at IS NULL

    AND (
        id_device IS NULL

        OR

        devices.fn_device_belongs_to_home(
            id_device,
            id_home
        )
    )
);


-- ------------------------------------------------------------
-- UPDATE — worker
--
-- El worker puede actualizar contenido/estado técnico,
-- pero el GRANT evita cambiar id_home e id_device.
-- ------------------------------------------------------------

CREATE POLICY recommendation_worker_update_policy
ON consumption.recommendation
FOR UPDATE
TO smarthome_worker
USING (TRUE)
WITH CHECK (

    id_device IS NULL

    OR

    devices.fn_device_belongs_to_home(
        id_device,
        id_home
    )
);