-- ============================================================
-- DEVICE LIFECYCLE PERMISSIONS
--
-- smarthome_app necesita modificar connectivity_status durante
-- activate/deactivate/delete.
--
-- MEMBER puede controlar is_on, pero no debe poder modificar
-- connectivity_status ni configuración del dispositivo.
-- ============================================================


-- ============================================================
-- 1. Eliminar policy dependiente de la función anterior
-- ============================================================

DROP POLICY IF EXISTS device_app_update_policy
ON devices.device;


-- ============================================================
-- 2. Eliminar helper anterior
-- ============================================================

DROP FUNCTION IF EXISTS devices.fn_device_app_update_allowed(
    UUID,
    UUID,
    TEXT,
    TEXT,
    BOOLEAN,
    TEXT,
    TEXT,
    TIMESTAMPTZ
);


-- ============================================================
-- 3. Crear helper incluyendo connectivity_status
-- ============================================================

CREATE OR REPLACE FUNCTION devices.fn_device_app_update_allowed(
    p_device_id UUID,
    p_home_id UUID,
    p_name TEXT,
    p_status TEXT,
    p_connectivity_status TEXT,
    p_is_on BOOLEAN,
    p_transport_type TEXT,
    p_messaging_protocol TEXT,
    p_deleted_at TIMESTAMPTZ
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, devices, homes
AS $$
DECLARE
    v_old devices.device%ROWTYPE;
BEGIN
    SELECT *
      INTO v_old
      FROM devices.device d
     WHERE d.id_device = p_device_id;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- Un dispositivo no puede trasladarse de hogar mediante UPDATE.
    IF p_home_id <> v_old.id_home THEN
        RETURN FALSE;
    END IF;


    -- ========================================================
    -- OWNER
    -- ========================================================

    IF homes.fn_can_manage_home(v_old.id_home) THEN

        IF p_name IS NULL
           OR pg_catalog.btrim(p_name) = '' THEN
            RETURN FALSE;
        END IF;

        IF p_status NOT IN (
            'ACTIVE',
            'DEACTIVATED'
        ) THEN
            RETURN FALSE;
        END IF;

        IF p_connectivity_status NOT IN (
            'ONLINE',
            'OFFLINE'
        ) THEN
            RETURN FALSE;
        END IF;

        -- Un dispositivo ACTIVE no puede estar eliminado.
        IF p_status = 'ACTIVE'
           AND p_deleted_at IS NOT NULL THEN
            RETURN FALSE;
        END IF;

        -- Un dispositivo desactivado debe quedar apagado y offline.
        IF p_status = 'DEACTIVATED'
           AND (
               p_connectivity_status <> 'OFFLINE'
               OR p_is_on <> FALSE
           ) THEN
            RETURN FALSE;
        END IF;

        RETURN TRUE;
    END IF;


    -- ========================================================
    -- MEMBER
    --
    -- Puede cambiar únicamente is_on.
    -- connectivity_status y demás atributos deben permanecer
    -- exactamente iguales.
    -- ========================================================

    IF v_old.status = 'ACTIVE'
       AND v_old.deleted_at IS NULL
       AND homes.fn_is_home_active(v_old.id_home)
       AND homes.fn_is_home_member(
           v_old.id_home,
           ARRAY['MEMBER']::TEXT[]
       ) THEN

        RETURN p_name IS NOT DISTINCT FROM v_old.name
           AND p_status IS NOT DISTINCT FROM v_old.status
           AND p_connectivity_status
               IS NOT DISTINCT FROM v_old.connectivity_status
           AND p_transport_type
               IS NOT DISTINCT FROM v_old.transport_type
           AND p_messaging_protocol
               IS NOT DISTINCT FROM v_old.messaging_protocol
           AND p_deleted_at
               IS NOT DISTINCT FROM v_old.deleted_at
           AND p_is_on IS NOT NULL;
    END IF;

    RETURN FALSE;
END;
$$;


REVOKE ALL
ON FUNCTION devices.fn_device_app_update_allowed(
    UUID,
    UUID,
    TEXT,
    TEXT,
    TEXT,
    BOOLEAN,
    TEXT,
    TEXT,
    TIMESTAMPTZ
)
FROM PUBLIC;


GRANT EXECUTE
ON FUNCTION devices.fn_device_app_update_allowed(
    UUID,
    UUID,
    TEXT,
    TEXT,
    TEXT,
    BOOLEAN,
    TEXT,
    TEXT,
    TIMESTAMPTZ
)
TO smarthome_app;


-- ============================================================
-- 4. Nueva policy UPDATE
-- ============================================================

CREATE POLICY device_app_update_policy
ON devices.device
FOR UPDATE
TO smarthome_app
USING (
    homes.fn_can_manage_home(id_home)

    OR

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


-- ============================================================
-- 5. Permiso necesario para lifecycle
-- ============================================================

GRANT UPDATE (
    connectivity_status
)
ON TABLE devices.device
TO smarthome_app;