-- ============================================================
-- HELPERS RLS - devices
-- Archivo: 01_ddl/07_functions/007_rls_device_security_functions.sql
-- ============================================================

-- ------------------------------------------------------------
-- device_type es un catalogo global. En el baseline actual no
-- se presupone una columna de soft delete en el catalogo.
-- ------------------------------------------------------------
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

REVOKE ALL ON FUNCTION devices.fn_is_active_device_type(UUID) FROM PUBLIC;


-- ------------------------------------------------------------
-- OWNER del hogar al que pertenece el dispositivo.
-- Puede reconocer tambien dispositivos DEACTIVATED para tareas
-- administrativas/reactivacion.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION devices.fn_is_device_owner(
    p_device_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, devices, homes
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM devices.device d
        WHERE d.id_device = p_device_id
          AND homes.fn_is_home_owner(d.id_home)
    );
$$;

REVOKE ALL ON FUNCTION devices.fn_is_device_owner(UUID) FROM PUBLIC;


-- ------------------------------------------------------------
-- Dispositivo visible para roles de hogar indicados.
-- MEMBER/GUEST solo deben atravesar este helper sobre devices
-- operativos de hogares operativos.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION devices.fn_can_view_device(
    p_device_id UUID,
    p_roles TEXT[]
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, devices, homes
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM devices.device d
        WHERE d.id_device = p_device_id
          AND d.status = 'ACTIVE'
          AND d.deleted_at IS NULL
          AND homes.fn_is_home_active(d.id_home)
          AND homes.fn_is_home_member(d.id_home, p_roles)
    );
$$;

REVOKE ALL ON FUNCTION devices.fn_can_view_device(UUID, TEXT[]) FROM PUBLIC;


-- ------------------------------------------------------------
-- El usuario actual puede administrar el dispositivo si es
-- OWNER de un hogar operativo.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION devices.fn_can_manage_device(
    p_device_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, devices, homes
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM devices.device d
        WHERE d.id_device = p_device_id
          AND homes.fn_can_manage_home(d.id_home)
    );
$$;

REVOKE ALL ON FUNCTION devices.fn_can_manage_device(UUID) FROM PUBLIC;


-- ------------------------------------------------------------
-- Dispositivo valido para recibir/procesar telemetria.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION devices.fn_is_ingestable_device(
    p_device_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, devices, homes
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM devices.device d
        WHERE d.id_device = p_device_id
          AND d.status = 'ACTIVE'
          AND d.deleted_at IS NULL
          AND homes.fn_is_home_active(d.id_home)
    );
$$;

REVOKE ALL ON FUNCTION devices.fn_is_ingestable_device(UUID) FROM PUBLIC;


-- ------------------------------------------------------------
-- Valida el UPDATE propuesto por smarthome_app.
--
-- OWNER:
--   puede modificar configuracion y ciclo de vida, pero no
--   mover el dispositivo a otro hogar.
--
-- MEMBER:
--   solo puede cambiar is_on; el GRANT por columnas y esta
--   funcion bloquean cambios de configuracion.
-- ------------------------------------------------------------
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

    -- id_home no puede cambiar por esta operacion.
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

       -- Ciclo de vida coherente.
       IF p_status = 'ACTIVE' AND p_deleted_at IS NOT NULL THEN
           RETURN FALSE;
       END IF;

       IF p_status = 'DEACTIVATED' AND p_deleted_at IS NULL THEN
           RETURN FALSE;
       END IF;

       IF p_status NOT IN ('ACTIVE', 'DEACTIVATED') THEN
           RETURN FALSE;
       END IF;

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
