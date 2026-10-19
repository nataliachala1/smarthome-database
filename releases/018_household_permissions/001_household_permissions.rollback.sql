DROP FUNCTION IF EXISTS homes.fn_set_device_permissions(UUID,UUID,UUID,BOOLEAN,BOOLEAN,BOOLEAN);
DROP FUNCTION IF EXISTS homes.fn_get_device_permissions(UUID,UUID,UUID);
DROP FUNCTION IF EXISTS homes.fn_set_member_permissions(UUID,UUID,BOOLEAN,BOOLEAN,BOOLEAN);
DROP FUNCTION IF EXISTS homes.fn_get_member_permissions(UUID,UUID);

ALTER POLICY consumption_metric_app_select_policy ON consumption.consumption_metric USING (consumption.fn_can_read_detail(id_home));
ALTER POLICY consumption_app_select_policy ON consumption.consumption USING (consumption.fn_can_read_detail(id_home));

CREATE OR REPLACE FUNCTION consumption.fn_can_read_detail(p_home_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, homes AS $$
  SELECT homes.fn_is_home_owner(p_home_id)
    OR (homes.fn_is_home_active(p_home_id)
        AND homes.fn_is_home_member(p_home_id, ARRAY['MEMBER']::TEXT[]));
$$;
CREATE OR REPLACE FUNCTION consumption.fn_history_devices(p_home_id UUID, p_device_ids UUID[])
RETURNS TABLE(id_device UUID, name TEXT, manufacturer_device_id TEXT)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, consumption, devices AS $$
  SELECT d.id_device, d.name::TEXT, d.manufacturer_device_id::TEXT
  FROM devices.device d
  WHERE consumption.fn_can_read_detail(p_home_id)
    AND d.id_home = p_home_id AND d.id_device = ANY(p_device_ids);
$$;
CREATE OR REPLACE FUNCTION consumption.fn_basic_home_consumption(p_home_id UUID, p_from TIMESTAMPTZ, p_to TIMESTAMPTZ)
RETURNS TABLE(total_energy_delta_kwh NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, consumption, homes AS $$
  SELECT COALESCE(SUM(c.energy_delta_kwh), 0)
  FROM consumption.consumption c
  WHERE c.id_home = p_home_id
    AND (p_from IS NULL OR c.read_at >= p_from)
    AND (p_to IS NULL OR c.read_at <= p_to)
  HAVING homes.fn_is_home_active(p_home_id)
    AND homes.fn_is_home_member(p_home_id, ARRAY['OWNER','MEMBER','GUEST']::TEXT[])
    AND (p_from IS NULL OR p_to IS NULL OR p_from <= p_to);
$$;

DROP POLICY IF EXISTS device_app_update_policy ON devices.device;
DROP POLICY IF EXISTS device_app_select_policy ON devices.device;
CREATE POLICY device_app_select_policy ON devices.device FOR SELECT TO smarthome_app
USING (homes.fn_is_home_owner(id_home) OR (
  status = 'ACTIVE' AND deleted_at IS NULL AND homes.fn_is_home_active(id_home)
  AND homes.fn_is_home_member(id_home, ARRAY['MEMBER','GUEST']::TEXT[])
));
CREATE POLICY device_app_update_policy ON devices.device FOR UPDATE TO smarthome_app
USING (homes.fn_can_manage_home(id_home) OR (
  status = 'ACTIVE' AND deleted_at IS NULL AND homes.fn_is_home_active(id_home)
  AND homes.fn_is_home_member(id_home, ARRAY['MEMBER']::TEXT[])
))
WITH CHECK (devices.fn_device_app_update_allowed(id_device,id_home,name,status,connectivity_status,is_on,transport_type,messaging_protocol,deleted_at));

CREATE OR REPLACE FUNCTION devices.fn_can_view_device(p_device_id UUID, p_roles TEXT[])
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, devices, homes AS $$
  SELECT EXISTS (
    SELECT 1 FROM devices.device d WHERE d.id_device = p_device_id
      AND d.status = 'ACTIVE' AND d.deleted_at IS NULL
      AND homes.fn_is_home_active(d.id_home)
      AND homes.fn_is_home_member(d.id_home, p_roles)
  );
$$;
CREATE OR REPLACE FUNCTION devices.fn_device_app_update_allowed(
  p_device_id UUID, p_home_id UUID, p_name TEXT, p_status TEXT,
  p_connectivity_status TEXT, p_is_on BOOLEAN, p_transport_type TEXT,
  p_messaging_protocol TEXT, p_deleted_at TIMESTAMPTZ
)
RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, devices, homes AS $$
DECLARE v_old devices.device%ROWTYPE;
BEGIN
  SELECT * INTO v_old FROM devices.device WHERE id_device = p_device_id;
  IF NOT FOUND OR p_home_id <> v_old.id_home THEN RETURN FALSE; END IF;
  IF homes.fn_can_manage_home(v_old.id_home) THEN
    IF p_name IS NULL OR pg_catalog.btrim(p_name) = '' THEN RETURN FALSE; END IF;
    IF p_status = 'ACTIVE' AND p_deleted_at IS NOT NULL THEN RETURN FALSE; END IF;
    IF p_status NOT IN ('ACTIVE','DEACTIVATED') THEN RETURN FALSE; END IF;
    RETURN TRUE;
  END IF;
  IF v_old.status = 'ACTIVE' AND v_old.deleted_at IS NULL
    AND homes.fn_is_home_active(v_old.id_home)
    AND homes.fn_is_home_member(v_old.id_home, ARRAY['MEMBER']::TEXT[]) THEN
    RETURN p_name IS NOT DISTINCT FROM v_old.name
      AND p_status IS NOT DISTINCT FROM v_old.status
      AND p_connectivity_status IS NOT DISTINCT FROM v_old.connectivity_status
      AND p_transport_type IS NOT DISTINCT FROM v_old.transport_type
      AND p_messaging_protocol IS NOT DISTINCT FROM v_old.messaging_protocol
      AND p_deleted_at IS NOT DISTINCT FROM v_old.deleted_at AND p_is_on IS NOT NULL;
  END IF;
  RETURN FALSE;
END;
$$;

DROP FUNCTION IF EXISTS devices.fn_device_control_target(UUID,UUID);
DROP FUNCTION IF EXISTS consumption.fn_can_read_device_detail(UUID);
DROP FUNCTION IF EXISTS devices.fn_has_device_permission(UUID,TEXT);
DROP FUNCTION IF EXISTS homes.fn_has_permission(UUID,TEXT);
DROP TRIGGER IF EXISTS trg_reset_member_permissions_on_role_change ON homes.home_member;
DROP FUNCTION IF EXISTS homes.fn_reset_member_permissions_on_role_change();
DROP TRIGGER IF EXISTS trg_initialize_member_permissions ON homes.home_member;
DROP FUNCTION IF EXISTS homes.fn_initialize_member_permissions();
DROP TABLE IF EXISTS devices.device_member_permission;
DROP TABLE IF EXISTS homes.home_member_permission;
