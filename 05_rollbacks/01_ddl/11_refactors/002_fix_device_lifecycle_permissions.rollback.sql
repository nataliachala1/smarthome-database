DROP POLICY IF EXISTS device_app_update_policy
ON devices.device;


DROP FUNCTION IF EXISTS devices.fn_device_app_update_allowed(
    UUID,
    UUID,
    TEXT,
    TEXT,
    TEXT,
    BOOLEAN,
    TEXT,
    TEXT,
    TIMESTAMPTZ
);


REVOKE UPDATE (
    connectivity_status
)
ON TABLE devices.device
FROM smarthome_app;


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

    IF p_home_id <> v_old.id_home THEN
        RETURN FALSE;
    END IF;

    IF homes.fn_can_manage_home(v_old.id_home) THEN

        IF p_name IS NULL
           OR pg_catalog.btrim(p_name) = '' THEN
            RETURN FALSE;
        END IF;

        IF p_status = 'ACTIVE'
           AND p_deleted_at IS NOT NULL THEN
            RETURN FALSE;
        END IF;

        IF p_status NOT IN (
            'ACTIVE',
            'DEACTIVATED'
        ) THEN
            RETURN FALSE;
        END IF;

        RETURN TRUE;
    END IF;

    IF v_old.status = 'ACTIVE'
       AND v_old.deleted_at IS NULL
       AND homes.fn_is_home_active(v_old.id_home)
       AND homes.fn_is_home_member(
           v_old.id_home,
           ARRAY['MEMBER']::TEXT[]
       ) THEN

        RETURN p_name IS NOT DISTINCT FROM v_old.name
           AND p_status IS NOT DISTINCT FROM v_old.status
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