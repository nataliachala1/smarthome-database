CREATE OR REPLACE FUNCTION devices.fn_device_app_update_allowed(
    p_device_id UUID,
    p_home_id UUID,
    p_device_type_id UUID,
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

    -- El dispositivo no puede moverse a otro hogar.
    IF p_home_id <> v_old.id_home THEN
        RETURN FALSE;
    END IF;

    -- ========================================================
    -- OWNER
    -- ========================================================
    IF homes.fn_can_manage_home(v_old.id_home) THEN

        IF NOT devices.fn_is_active_device_type(p_device_type_id)
           OR p_name IS NULL
           OR pg_catalog.btrim(p_name) = '' THEN
            RETURN FALSE;
        END IF;

        -- ACTIVE nunca puede estar eliminado.
        IF p_status = 'ACTIVE'
           AND p_deleted_at IS NOT NULL THEN
            RETURN FALSE;
        END IF;

        -- Estados soportados por el ciclo de vida.
        IF p_status NOT IN ('ACTIVE', 'DEACTIVATED') THEN
            RETURN FALSE;
        END IF;

        -- DEACTIVATED admite:
        --   deleted_at IS NULL     -> INACTIVE
        --   deleted_at IS NOT NULL -> DELETED
        RETURN TRUE;
    END IF;

    -- ========================================================
    -- MEMBER: exclusivamente control ON/OFF
    -- ========================================================
    IF v_old.status = 'ACTIVE'
       AND v_old.deleted_at IS NULL
       AND homes.fn_is_home_active(v_old.id_home)
       AND homes.fn_is_home_member(
           v_old.id_home,
           ARRAY['MEMBER']::TEXT[]
       ) THEN

        RETURN p_device_type_id = v_old.id_device_type
           AND p_name IS NOT DISTINCT FROM v_old.name
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
    UUID, UUID, UUID, TEXT, TEXT, BOOLEAN, TEXT, TEXT, TIMESTAMPTZ
)
FROM PUBLIC;