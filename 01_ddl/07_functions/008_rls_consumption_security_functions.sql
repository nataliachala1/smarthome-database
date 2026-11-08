-- ============================================================
-- RLS HELPERS - consumption
-- File: 01_ddl/07_functions/008_rls_consumption_security_functions.sql
-- ============================================================

-- ------------------------------------------------------------
-- Guarantees that the given device really belongs
-- to the given home.
--
-- Used as a second safeguard together with the composite FKs
-- of the consumption/notifications model.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION devices.fn_device_belongs_to_home(
    p_device_id UUID,
    p_home_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, devices
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM devices.device d
        WHERE d.id_device = p_device_id
          AND d.id_home = p_home_id
    );
$$;

REVOKE ALL
ON FUNCTION devices.fn_device_belongs_to_home(UUID, UUID)
FROM PUBLIC;

COMMENT ON FUNCTION devices.fn_device_belongs_to_home(UUID, UUID)
IS 'Comprueba la pertenencia exacta de un dispositivo a un hogar.';
