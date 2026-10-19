-- Additive HU16 / BD-04 / BD-05. Existing changesets remain unchanged.
CREATE FUNCTION consumption.fn_can_read_detail(p_home_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, homes
AS $$
  SELECT homes.fn_is_home_owner(p_home_id)
    OR (homes.fn_is_home_active(p_home_id)
        AND homes.fn_is_home_member(p_home_id, ARRAY['MEMBER']::TEXT[]));
$$;
REVOKE ALL ON FUNCTION consumption.fn_can_read_detail(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION consumption.fn_can_read_detail(UUID) TO smarthome_app;

-- Narrow history metadata: does not change device SELECT/control policies.
CREATE FUNCTION consumption.fn_history_devices(p_home_id UUID, p_device_ids UUID[])
RETURNS TABLE(id_device UUID, name TEXT, manufacturer_device_id TEXT)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, consumption, devices
AS $$
  SELECT d.id_device, d.name::TEXT, d.manufacturer_device_id::TEXT
  FROM devices.device d
  WHERE consumption.fn_can_read_detail(p_home_id)
    AND d.id_home = p_home_id AND d.id_device = ANY(p_device_ids);
$$;
REVOKE ALL ON FUNCTION consumption.fn_history_devices(UUID, UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION consumption.fn_history_devices(UUID, UUID[]) TO smarthome_app;

-- Aggregate-only contract approved for GUEST; no raw readings or device metadata.
CREATE FUNCTION consumption.fn_basic_home_consumption(p_home_id UUID, p_from TIMESTAMPTZ, p_to TIMESTAMPTZ)
RETURNS TABLE(total_energy_delta_kwh NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, consumption, homes
AS $$
  SELECT COALESCE(SUM(c.energy_delta_kwh), 0)
  FROM consumption.consumption c
  WHERE c.id_home = p_home_id
    AND (p_from IS NULL OR c.read_at >= p_from)
    AND (p_to IS NULL OR c.read_at <= p_to)
  HAVING homes.fn_is_home_active(p_home_id)
    AND homes.fn_is_home_member(p_home_id, ARRAY['OWNER', 'MEMBER', 'GUEST']::TEXT[])
    AND (p_from IS NULL OR p_to IS NULL OR p_from <= p_to);
$$;
REVOKE ALL ON FUNCTION consumption.fn_basic_home_consumption(UUID, TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION consumption.fn_basic_home_consumption(UUID, TIMESTAMPTZ, TIMESTAMPTZ) TO smarthome_app;

ALTER POLICY consumption_app_select_policy ON consumption.consumption
USING (consumption.fn_can_read_detail(id_home));
ALTER POLICY consumption_metric_app_select_policy ON consumption.consumption_metric
USING (consumption.fn_can_read_detail(id_home));
