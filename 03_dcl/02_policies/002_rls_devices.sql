-- ============================================================
-- RLS — Esquema devices
-- Archivo: 03_dcl/02_policies/002_rls_devices.sql
--
-- Tablas protegidas:
--   devices.device
--   devices.smart_device
--   devices.device_schedule
--   devices.device_telemetry_raw
--
-- devices.device_type es un catálogo global y no necesita RLS.
--
-- Roles funcionales:
--   OWNER
--   MEMBER
--   GUEST
--
-- Rol técnico:
--   smarthome_ingest
--
-- No existen policies DELETE.
-- ============================================================


-- ============================================================
-- devices.device
-- ============================================================

ALTER TABLE devices.device
ENABLE ROW LEVEL SECURITY;



-- ------------------------------------------------------------
-- SELECT — aplicación
--
-- OWNER:
--   puede ver también dispositivos DEACTIVATED para poder
--   administrarlos/reactivarlos.
--
-- MEMBER/GUEST:
--   solo dispositivos ACTIVE de hogares ACTIVE.
-- ------------------------------------------------------------

CREATE POLICY device_app_select_policy
ON devices.device
FOR SELECT
TO smarthome_app
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
-- INSERT — aplicación
--
-- Solamente OWNER.
--
-- Un nuevo dispositivo:
--   - pertenece a hogar ACTIVE;
--   - utiliza zona ACTIVE del mismo hogar;
--   - utiliza tipo de dispositivo disponible;
--   - comienza ACTIVE;
--   - comienza OFFLINE;
--   - no inventa potencia actual;
--   - no nace eliminado.
-- ------------------------------------------------------------

CREATE POLICY device_app_insert_policy
ON devices.device
FOR INSERT
TO smarthome_app
WITH CHECK (

    homes.fn_can_manage_home(id_home)

    AND devices.fn_is_active_zone(
        id_zone,
        id_home
    )

    AND devices.fn_is_active_device_type(
        id_device_type
    )

    AND status = 'ACTIVE'

    AND connectivity_status = 'OFFLINE'

    AND is_on = FALSE

    AND current_power_w IS NULL

    AND deleted_at IS NULL
);


-- ------------------------------------------------------------
-- UPDATE — aplicación
--
-- OWNER:
--   administra configuración.
--
-- MEMBER:
--   puede controlar is_on pero no cambiar la configuración.
--
-- GUEST:
--   no puede actualizar.
-- ------------------------------------------------------------

CREATE POLICY device_app_update_policy
ON devices.device
FOR UPDATE
TO smarthome_app
USING (

    -- OWNER puede administrar incluso un device DEACTIVATED,
    -- siempre que el hogar esté operativo.
    homes.fn_can_manage_home(id_home)

    OR

    -- MEMBER solamente sobre dispositivos operativos.
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
        id_zone,
        id_device_type,
        name,
        status,
        is_on,
        transport_type,
        messaging_protocol,
        deleted_at
    )
);


-- ------------------------------------------------------------
-- SELECT — ingesta
--
-- El flujo MQTT necesita localizar dispositivos operativos.
-- No depende de OWNER/MEMBER/GUEST.
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
-- UPDATE — ingesta
--
-- El GRANT limita físicamente las columnas a:
--   connectivity_status
--   is_on
--   current_power_w
--   updated_at
--
-- Por tanto, incluso con esta policy el rol técnico no puede
-- cambiar hogar, zona, nombre, status, etc.
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
-- SELECT — aplicación
--
-- OWNER puede consultar metadata aunque el dispositivo esté
-- DEACTIVATED.
--
-- MEMBER/GUEST solo metadata de dispositivos operativos.
-- ------------------------------------------------------------

CREATE POLICY smart_device_app_select_policy
ON devices.smart_device
FOR SELECT
TO smarthome_app
USING (

    devices.fn_is_device_owner(id_device)

    OR

    devices.fn_can_view_device(
        id_device,
        ARRAY['MEMBER', 'GUEST']::TEXT[]
    )
);


-- ------------------------------------------------------------
-- INSERT — solo OWNER
-- ------------------------------------------------------------

CREATE POLICY smart_device_app_insert_policy
ON devices.smart_device
FOR INSERT
TO smarthome_app
WITH CHECK (
    devices.fn_can_manage_device(id_device)
);


-- ------------------------------------------------------------
-- UPDATE — solo OWNER
-- ------------------------------------------------------------

CREATE POLICY smart_device_app_update_policy
ON devices.smart_device
FOR UPDATE
TO smarthome_app
USING (
    devices.fn_can_manage_device(id_device)
)
WITH CHECK (
    devices.fn_can_manage_device(id_device)
);


-- ------------------------------------------------------------
-- SELECT — ingesta
--
-- El módulo MQTT puede consultar metadata técnica únicamente
-- de dispositivos operativos.
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
--   consulta todas las programaciones, incluidas desactivadas.
--
-- MEMBER:
--   consulta únicamente schedules activos del dispositivo.
--
-- GUEST:
--   no necesita consultar configuración automática.
-- ------------------------------------------------------------

CREATE POLICY device_schedule_select_policy
ON devices.device_schedule
FOR SELECT
TO smarthome_app
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
-- INSERT — solo OWNER
-- ------------------------------------------------------------

CREATE POLICY device_schedule_insert_policy
ON devices.device_schedule
FOR INSERT
TO smarthome_app
WITH CHECK (
    devices.fn_can_manage_device(id_device)
    AND deleted_at IS NULL
);


-- ------------------------------------------------------------
-- UPDATE — solo OWNER
--
-- Permite activar/desactivar y realizar soft delete.
-- ------------------------------------------------------------

CREATE POLICY device_schedule_update_policy
ON devices.device_schedule
FOR UPDATE
TO smarthome_app
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
-- INSERT — ingesta MQTT
--
-- Telemetría raw es append-only.
-- El id_device debe corresponder a un dispositivo operativo.
-- ------------------------------------------------------------

CREATE POLICY telemetry_raw_ingest_insert_policy
ON devices.device_telemetry_raw
FOR INSERT
TO smarthome_ingest
WITH CHECK (
    devices.fn_is_ingestable_device(id_device)
);