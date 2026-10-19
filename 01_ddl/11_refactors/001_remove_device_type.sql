-- ============================================================
-- REMOVE DEVICE TYPE
--
-- El catálogo devices.device_type dejó de formar parte del
-- modelo vigente. La identidad técnica del dispositivo se
-- obtiene mediante manufacturer/model/integration metadata.
-- ============================================================


-- ============================================================
-- 1. Policies que dependen de id_device_type
-- ============================================================

DROP POLICY IF EXISTS device_app_insert_policy
ON devices.device;

DROP POLICY IF EXISTS device_app_update_policy
ON devices.device;


-- ============================================================
-- 2. Helpers RLS antiguos
-- ============================================================

DROP FUNCTION IF EXISTS devices.fn_device_app_update_allowed(
    UUID,
    UUID,
    UUID,
    TEXT,
    TEXT,
    BOOLEAN,
    TEXT,
    TEXT,
    TIMESTAMPTZ
);

DROP FUNCTION IF EXISTS devices.fn_is_active_device_type(UUID);


-- ============================================================
-- 3. Eliminar FK y columna antigua
-- ============================================================

ALTER TABLE devices.device
DROP CONSTRAINT IF EXISTS fk_device_type;

ALTER TABLE devices.device
DROP COLUMN IF EXISTS id_device_type;


-- ============================================================
-- 4. Eliminar catálogo obsoleto
-- ============================================================

DROP TABLE IF EXISTS devices.device_type;


-- ============================================================
-- 5. Nueva función de autorización UPDATE
-- ============================================================

CREATE OR REPLACE FUNCTION devices.fn_device_app_update_allowed(
    p_device_id UUID,
    p_home_id UUID,
    p_name TEXT,
    p_status TEXT,
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

    -- El dispositivo nunca puede trasladarse a otro hogar
    -- mediante una actualización normal.
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

        IF p_status = 'ACTIVE'
           AND p_deleted_at IS NOT NULL THEN
            RETURN FALSE;
        END IF;

        IF p_status NOT IN ('ACTIVE', 'DEACTIVATED') THEN
            RETURN FALSE;
        END IF;

        RETURN TRUE;
    END IF;

    -- ========================================================
    -- MEMBER
    -- Solamente control ON/OFF.
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
           AND p_transport_type IS NOT DISTINCT FROM v_old.transport_type
           AND p_messaging_protocol IS NOT DISTINCT FROM v_old.messaging_protocol
           AND p_deleted_at IS NOT DISTINCT FROM v_old.deleted_at
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
    BOOLEAN,
    TEXT,
    TEXT,
    TIMESTAMPTZ
)
TO smarthome_app;


-- ============================================================
-- 6. Nueva policy INSERT
-- ============================================================

CREATE POLICY device_app_insert_policy
ON devices.device
FOR INSERT
TO smarthome_app
WITH CHECK (
    homes.fn_can_manage_home(id_home)

    AND status = 'ACTIVE'
    AND connectivity_status = 'OFFLINE'
    AND is_on = FALSE
    AND current_power_w IS NULL
    AND deleted_at IS NULL
);


-- ============================================================
-- 7. Nueva policy UPDATE
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
        is_on,
        transport_type,
        messaging_protocol,
        deleted_at
    )
);


-- ============================================================
-- 8. Permisos finales
-- ============================================================

GRANT UPDATE (
    name,
    status,
    is_on,
    transport_type,
    messaging_protocol,
    deleted_at
)
ON TABLE devices.device
TO smarthome_app;