-- ============================================================
-- RLS — devices schema
-- File: 03_dcl/02_policies/002_rls_devices.sql
--
-- Protected tables:
--   devices.device
--   devices.smart_device
--   devices.device_schedule
--   devices.device_telemetry_raw
--
-- devices.device_type is a global catalog and needs no RLS.
--
-- Functional roles:
--   OWNER
--   MEMBER
--   GUEST
--
-- Technical role:
--   smarthome_ingest
--
-- There are no DELETE policies.
-- ============================================================


-- ============================================================
-- devices.device
-- ============================================================

ALTER TABLE devices.device
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- SELECT — application
--
-- OWNER:
--   can also see DEACTIVATED devices in order to
--   manage/reactivate them.
--
-- MEMBER/GUEST:
--   only ACTIVE devices of ACTIVE homes.
-- ------------------------------------------------------------

CREATE POLICY device_app_select_policy
ON devices.device
FOR SELECT
TO smarthome_runtime_app
USING (

    homes.fn_is_home_owner(id_home)

    OR

    (
        status = 'ACTIVE'
        AND deleted_at IS NULL

        AND homes.fn_is_home_active(id_home)

        AND homes.fn_is_home_member(
            id_home,
            ARRAY['MEMBER', 'GUEST']::TEXT[]
        )
    )
);


-- ------------------------------------------------------------
-- INSERT — application
--
-- OWNER only.
--
-- A new device:
--   - belongs to an ACTIVE home;
--   - starts ACTIVE;
--   - starts OFFLINE;
--   - does not invent a current power value;
--   - is not created deleted.
-- ------------------------------------------------------------

CREATE POLICY device_app_insert_policy
ON devices.device
FOR INSERT
TO smarthome_runtime_app
WITH CHECK (

    homes.fn_can_manage_home(id_home)

    AND status = 'ACTIVE'

    AND connectivity_status = 'OFFLINE'

    AND is_on = FALSE

    AND current_power_w IS NULL

    AND deleted_at IS NULL
);


-- ------------------------------------------------------------
-- UPDATE — application
--
-- OWNER:
--   manages the configuration.
--
-- MEMBER:
--   can control is_on but cannot change the configuration.
--
-- GUEST:
--   cannot update.
-- ------------------------------------------------------------

CREATE POLICY device_app_update_policy
ON devices.device
FOR UPDATE
TO smarthome_runtime_app
USING (

    -- The OWNER can manage even a DEACTIVATED device,
    -- as long as the home is operational.
    homes.fn_can_manage_home(id_home)

    OR

    -- MEMBER only on operational devices.
    (
        status = 'ACTIVE'
        AND deleted_at IS NULL

        AND homes.fn_is_home_active(id_home)

        AND homes.fn_is_home_member(
            id_home,
            ARRAY['MEMBER']::TEXT[]
        )
    )
)
WITH CHECK (
    devices.fn_device_app_update_allowed(
        id_device,
        id_home,
        name,
        status,
        connectivity_status,
        is_on,
        transport_type,
        messaging_protocol,
        deleted_at
    )
);


-- ------------------------------------------------------------
-- SELECT — ingest
--
-- The MQTT flow needs to locate operational devices.
-- It does not depend on OWNER/MEMBER/GUEST.
-- ------------------------------------------------------------

CREATE POLICY device_ingest_select_policy
ON devices.device
FOR SELECT
TO smarthome_ingest
USING (
    status = 'ACTIVE'
    AND deleted_at IS NULL
);


-- ------------------------------------------------------------
-- UPDATE — ingest
--
-- The GRANT physically limits the columns to:
--   connectivity_status
--   is_on
--   current_power_w
--   updated_at
--
-- Therefore, even with this policy the technical role cannot
-- change the home, name, status, etc.
-- ------------------------------------------------------------

CREATE POLICY device_ingest_update_policy
ON devices.device
FOR UPDATE
TO smarthome_ingest
USING (
    status = 'ACTIVE'
    AND deleted_at IS NULL
)
WITH CHECK (
    status = 'ACTIVE'
    AND deleted_at IS NULL
);


-- ============================================================
-- devices.smart_device
-- ============================================================

ALTER TABLE devices.smart_device
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- SELECT — application
--
-- The OWNER can read metadata even if the device is
-- DEACTIVATED.
--
-- MEMBER/GUEST only read metadata of operational devices.
-- ------------------------------------------------------------

CREATE POLICY smart_device_app_select_policy
ON devices.smart_device
FOR SELECT
TO smarthome_runtime_app
USING (

    devices.fn_is_device_owner(id_device)

    OR

    devices.fn_can_view_device(
        id_device,
        ARRAY['MEMBER', 'GUEST']::TEXT[]
    )
);


-- ------------------------------------------------------------
-- INSERT — OWNER only
-- ------------------------------------------------------------

CREATE POLICY smart_device_app_insert_policy
ON devices.smart_device
FOR INSERT
TO smarthome_runtime_app
WITH CHECK (
    devices.fn_can_manage_device(id_device)
);


-- ------------------------------------------------------------
-- UPDATE — OWNER only
-- ------------------------------------------------------------

CREATE POLICY smart_device_app_update_policy
ON devices.smart_device
FOR UPDATE
TO smarthome_runtime_app
USING (
    devices.fn_can_manage_device(id_device)
)
WITH CHECK (
    devices.fn_can_manage_device(id_device)
);


-- ------------------------------------------------------------
-- SELECT — ingest
--
-- The MQTT module can read technical metadata only
-- of operational devices.
-- ------------------------------------------------------------

CREATE POLICY smart_device_ingest_select_policy
ON devices.smart_device
FOR SELECT
TO smarthome_ingest
USING (
    devices.fn_is_ingestable_device(id_device)
);


-- ============================================================
-- devices.device_schedule
-- ============================================================

ALTER TABLE devices.device_schedule
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- SELECT
--
-- OWNER:
--   reads every schedule, including disabled ones.
--
-- MEMBER:
--   reads only the active schedules of the device.
--
-- GUEST:
--   does not need to read automatic configuration.
-- ------------------------------------------------------------

CREATE POLICY device_schedule_select_policy
ON devices.device_schedule
FOR SELECT
TO smarthome_runtime_app
USING (

    devices.fn_is_device_owner(id_device)

    OR

    (
        is_active = TRUE
        AND deleted_at IS NULL

        AND devices.fn_can_view_device(
            id_device,
            ARRAY['MEMBER']::TEXT[]
        )
    )
);


-- ------------------------------------------------------------
-- INSERT — OWNER only
-- ------------------------------------------------------------

CREATE POLICY device_schedule_insert_policy
ON devices.device_schedule
FOR INSERT
TO smarthome_runtime_app
WITH CHECK (
    devices.fn_can_manage_device(id_device)
    AND deleted_at IS NULL
);


-- ------------------------------------------------------------
-- UPDATE — OWNER only
--
-- Allows enabling/disabling and soft delete.
-- ------------------------------------------------------------

CREATE POLICY device_schedule_update_policy
ON devices.device_schedule
FOR UPDATE
TO smarthome_runtime_app
USING (
    devices.fn_can_manage_device(id_device)
)
WITH CHECK (
    devices.fn_can_manage_device(id_device)
);


-- ============================================================
-- devices.device_telemetry_raw
-- ============================================================

ALTER TABLE devices.device_telemetry_raw
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- INSERT — MQTT ingest
--
-- Raw telemetry is append-only.
-- id_device must belong to an operational device.
-- ------------------------------------------------------------

CREATE POLICY telemetry_raw_ingest_insert_policy
ON devices.device_telemetry_raw
FOR INSERT
TO smarthome_ingest
WITH CHECK (
    devices.fn_is_ingestable_device(id_device)
);