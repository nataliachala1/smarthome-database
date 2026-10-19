-- ============================================================
-- ROLLBACK - RESTORE DEVICE TYPE
-- ============================================================

DROP POLICY IF EXISTS device_app_insert_policy
ON devices.device;

DROP POLICY IF EXISTS device_app_update_policy
ON devices.device;

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
-- Restaurar catálogo
-- ============================================================

CREATE TABLE IF NOT EXISTS devices.device_type (
    id_device_type UUID         NOT NULL DEFAULT gen_random_uuid(),
    name           VARCHAR(100) NOT NULL,
    description    TEXT         NULL,
    icon           VARCHAR(100) NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    deleted_at     TIMESTAMPTZ  NULL,

    CONSTRAINT pk_device_type
        PRIMARY KEY (id_device_type),

    CONSTRAINT uq_device_type_name
        UNIQUE (name)
);


INSERT INTO devices.device_type (
    name,
    description,
    icon
)
VALUES
    (
        'Otro',
        'Dispositivo genérico no clasificado',
        'device'
    )
ON CONFLICT (name) DO NOTHING;


CREATE INDEX IF NOT EXISTS idx_device_type_active
ON devices.device_type(id_device_type)
WHERE deleted_at IS NULL;


DROP TRIGGER IF EXISTS trg_device_type_updated_at
ON devices.device_type;

CREATE TRIGGER trg_device_type_updated_at
BEFORE UPDATE ON devices.device_type
FOR EACH ROW
EXECUTE FUNCTION public.fn_set_updated_at();


-- ============================================================
-- Restaurar columna
-- ============================================================

ALTER TABLE devices.device
ADD COLUMN IF NOT EXISTS id_device_type UUID;


UPDATE devices.device d
SET id_device_type = dt.id_device_type
FROM devices.device_type dt
WHERE dt.name = 'Otro'
  AND d.id_device_type IS NULL;


ALTER TABLE devices.device
ALTER COLUMN id_device_type SET NOT NULL;


ALTER TABLE devices.device
ADD CONSTRAINT fk_device_type
FOREIGN KEY (id_device_type)
REFERENCES devices.device_type(id_device_type);


-- ============================================================
-- Helper device type
-- ============================================================

CREATE OR REPLACE FUNCTION devices.fn_is_active_device_type(
    p_device_type_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, devices
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM devices.device_type dt
        WHERE dt.id_device_type = p_device_type_id
          AND dt.deleted_at IS NULL
    );
$$;

REVOKE ALL
ON FUNCTION devices.fn_is_active_device_type(UUID)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION devices.fn_is_active_device_type(UUID)
TO smarthome_app;


-- ============================================================
-- Restaurar helper UPDATE anterior
-- ============================================================

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

    IF p_home_id <> v_old.id_home THEN
        RETURN FALSE;
    END IF;

    IF homes.fn_can_manage_home(v_old.id_home) THEN

        IF NOT devices.fn_is_active_device_type(p_device_type_id)
           OR p_name IS NULL
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


GRANT EXECUTE
ON FUNCTION devices.fn_device_app_update_allowed(
    UUID,
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
-- Restaurar policies
-- ============================================================

CREATE POLICY device_app_insert_policy
ON devices.device
FOR INSERT
TO smarthome_app
WITH CHECK (
    homes.fn_can_manage_home(id_home)

    AND devices.fn_is_active_device_type(id_device_type)

    AND status = 'ACTIVE'
    AND connectivity_status = 'OFFLINE'
    AND is_on = FALSE
    AND current_power_w IS NULL
    AND deleted_at IS NULL
);


CREATE POLICY device_app_update_policy
ON devices.device
FOR UPDATE
TO smarthome_app
USING (
    homes.fn_can_manage_home(id_home)

    OR (
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
        id_device_type,
        name,
        status,
        is_on,
        transport_type,
        messaging_protocol,
        deleted_at
    )
);


-- ============================================================
-- Restaurar grants
-- ============================================================

GRANT SELECT
ON TABLE devices.device_type
TO smarthome_admin, smarthome_app, smarthome_readonly;

GRANT UPDATE (
    id_device_type,
    name,
    status,
    is_on,
    transport_type,
    messaging_protocol,
    deleted_at
)
ON TABLE devices.device
TO smarthome_app;