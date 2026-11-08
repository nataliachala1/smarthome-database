-- ============================================================
-- RLS — consumption schema
-- File: 03_dcl/02_policies/003_rls_consumption.sql
--
-- Tables:
--   consumption.consumption
--   consumption.consumption_metric
--
-- Functional rules:
--
-- Consumption/reports:
--   OWNER  -> SELECT
--   MEMBER -> SELECT
--   GUEST  -> SELECT
--
-- Writing readings:
--   smarthome_ingest
--
-- Aggregates and metrics:
--   smarthome_worker
--
-- There are no DELETE policies.
-- ============================================================


-- ============================================================
-- consumption.consumption
-- ============================================================

ALTER TABLE consumption.consumption
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- SELECT — user
--
-- OWNER:
-- Can keep access to history even if the home
-- was deactivated.
--
-- MEMBER/GUEST:
-- Only on currently operational homes.
-- ------------------------------------------------------------

CREATE POLICY consumption_app_select_policy
ON consumption.consumption
FOR SELECT
TO smarthome_runtime_app
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
-- SELECT — ingest
--
-- Needed to get the latest reading of the device
-- and compute energy_delta_kwh.
--
-- The GRANT already limits the visible columns to:
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
-- INSERT — ingest
--
-- Only accepts readings whose device:
--   - exists;
--   - is operational for ingest;
--   - belongs exactly to the given id_home.
--
-- The composite FK also acts as a second safeguard.
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
-- The worker builds aggregates for every home.
-- It is a NOBYPASSRLS technical role with specific permissions.
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
-- SELECT — user
--
-- Same history rule as consumption.consumption.
-- ------------------------------------------------------------

CREATE POLICY consumption_metric_app_select_policy
ON consumption.consumption_metric
FOR SELECT
TO smarthome_runtime_app
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
-- Cannot create a metric with a device and a home
-- that do not match.
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
-- The column-level GRANT prevents changing the identity, period
-- and dates of the aggregate.
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



