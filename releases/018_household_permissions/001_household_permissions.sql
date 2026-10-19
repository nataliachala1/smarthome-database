-- Permission baselines are separate from membership state so accepting or
-- leaving an invitation cannot accidentally change grants.
CREATE TABLE homes.home_member_permission (
  id_home_member UUID PRIMARY KEY REFERENCES homes.home_member(id_home_member),
  can_view_devices BOOLEAN NOT NULL,
  can_view_consumption BOOLEAN NOT NULL,
  can_control_devices BOOLEAN NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO homes.home_member_permission
  (id_home_member, can_view_devices, can_view_consumption, can_control_devices)
SELECT id_home_member, TRUE, TRUE, role = 'MEMBER'
FROM homes.home_member WHERE role IN ('MEMBER', 'GUEST');

CREATE TABLE devices.device_member_permission (
  id_home_member UUID NOT NULL REFERENCES homes.home_member_permission(id_home_member),
  id_device UUID NOT NULL REFERENCES devices.device(id_device),
  can_view_device BOOLEAN NULL,
  can_view_consumption BOOLEAN NULL,
  can_control_device BOOLEAN NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pk_device_member_permission PRIMARY KEY (id_home_member, id_device),
  CONSTRAINT ck_device_member_permission_override CHECK (
    can_view_device IS NOT NULL OR can_view_consumption IS NOT NULL OR can_control_device IS NOT NULL
  )
);

CREATE INDEX idx_device_member_permission_device ON devices.device_member_permission(id_device);

CREATE FUNCTION homes.fn_initialize_member_permissions()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, homes AS $$
BEGIN
  IF NEW.role IN ('MEMBER', 'GUEST') THEN
    INSERT INTO homes.home_member_permission
      (id_home_member, can_view_devices, can_view_consumption, can_control_devices)
    VALUES (NEW.id_home_member, TRUE, TRUE, NEW.role = 'MEMBER')
    ON CONFLICT (id_home_member) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION homes.fn_initialize_member_permissions() FROM PUBLIC;
CREATE TRIGGER trg_initialize_member_permissions
AFTER INSERT ON homes.home_member
FOR EACH ROW EXECUTE FUNCTION homes.fn_initialize_member_permissions();

CREATE FUNCTION homes.fn_reset_member_permissions_on_role_change()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, homes AS $$
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role AND NEW.role IN ('MEMBER', 'GUEST') THEN
    UPDATE homes.home_member_permission
       SET can_view_devices = TRUE,
           can_view_consumption = TRUE,
           can_control_devices = (NEW.role = 'MEMBER'),
           updated_at = NOW()
     WHERE id_home_member = NEW.id_home_member;
    DELETE FROM devices.device_member_permission
     WHERE id_home_member = NEW.id_home_member;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION homes.fn_reset_member_permissions_on_role_change() FROM PUBLIC;
CREATE TRIGGER trg_reset_member_permissions_on_role_change
AFTER UPDATE OF role ON homes.home_member
FOR EACH ROW EXECUTE FUNCTION homes.fn_reset_member_permissions_on_role_change();

CREATE FUNCTION homes.fn_has_permission(p_home_id UUID, p_permission TEXT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, homes AS $$
  SELECT CASE
    WHEN p_permission IN ('view_devices','view_consumption','control_devices')
      AND homes.fn_is_home_owner(p_home_id) THEN TRUE
    WHEN p_permission = 'view_devices' THEN EXISTS (
      SELECT 1 FROM homes.home_member hm
      JOIN homes.home_member_permission hp USING (id_home_member)
      WHERE hm.id_home = p_home_id AND hm.id_user = auth.fn_current_user_id()
        AND hm.status = 'ACTIVE' AND hm.role IN ('MEMBER','GUEST')
        AND homes.fn_is_home_active(p_home_id) AND hp.can_view_devices
    )
    WHEN p_permission = 'view_consumption' THEN EXISTS (
      SELECT 1 FROM homes.home_member hm
      JOIN homes.home_member_permission hp USING (id_home_member)
      WHERE hm.id_home = p_home_id AND hm.id_user = auth.fn_current_user_id()
        AND hm.status = 'ACTIVE' AND hm.role IN ('MEMBER','GUEST')
        AND homes.fn_is_home_active(p_home_id) AND hp.can_view_consumption
    )
    WHEN p_permission = 'control_devices' THEN EXISTS (
      SELECT 1 FROM homes.home_member hm
      JOIN homes.home_member_permission hp USING (id_home_member)
      WHERE hm.id_home = p_home_id AND hm.id_user = auth.fn_current_user_id()
        AND hm.status = 'ACTIVE' AND hm.role IN ('MEMBER','GUEST')
        AND homes.fn_is_home_active(p_home_id) AND hp.can_control_devices
    )
    ELSE FALSE
  END;
$$;
REVOKE ALL ON FUNCTION homes.fn_has_permission(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION homes.fn_has_permission(UUID, TEXT) TO smarthome_app;

CREATE FUNCTION devices.fn_has_device_permission(p_device_id UUID, p_permission TEXT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, homes, devices AS $$
  SELECT EXISTS (
    SELECT 1 FROM devices.device owner_device
    WHERE owner_device.id_device = p_device_id
      AND p_permission IN ('view','view_consumption','control')
      AND homes.fn_is_home_owner(owner_device.id_home)
  ) OR EXISTS (
    SELECT 1 FROM devices.device d
    JOIN homes.home_member hm ON hm.id_home = d.id_home
    JOIN homes.home_member_permission hp USING (id_home_member)
    LEFT JOIN devices.device_member_permission dp
      ON dp.id_home_member = hm.id_home_member AND dp.id_device = d.id_device
    WHERE d.id_device = p_device_id AND d.status = 'ACTIVE' AND d.deleted_at IS NULL
      AND hm.id_user = auth.fn_current_user_id() AND hm.status = 'ACTIVE'
      AND hm.role IN ('MEMBER','GUEST') AND homes.fn_is_home_active(d.id_home)
      AND CASE p_permission
        WHEN 'view' THEN COALESCE(dp.can_view_device, hp.can_view_devices)
        WHEN 'view_consumption' THEN COALESCE(dp.can_view_consumption, hp.can_view_consumption)
        WHEN 'control' THEN COALESCE(dp.can_control_device, hp.can_control_devices)
        ELSE FALSE
      END
  );
$$;
REVOKE ALL ON FUNCTION devices.fn_has_device_permission(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_has_device_permission(UUID, TEXT) TO smarthome_app;

CREATE OR REPLACE FUNCTION devices.fn_can_view_device(p_device_id UUID, p_roles TEXT[])
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, homes, devices AS $$
  SELECT homes.fn_is_home_owner(d.id_home)
      OR (d.status = 'ACTIVE' AND d.deleted_at IS NULL
          AND homes.fn_is_home_active(d.id_home)
          AND homes.fn_is_home_member(d.id_home, p_roles)
          AND (NOT ('MEMBER' = ANY(p_roles) OR 'GUEST' = ANY(p_roles))
               OR devices.fn_has_device_permission(d.id_device, 'view')))
  FROM devices.device d WHERE d.id_device = p_device_id;
$$;
REVOKE ALL ON FUNCTION devices.fn_can_view_device(UUID, TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_can_view_device(UUID, TEXT[]) TO smarthome_app;

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
    RETURN p_name IS NOT NULL AND pg_catalog.btrim(p_name) <> ''
      AND ((p_status = 'ACTIVE' AND p_deleted_at IS NULL)
        OR (p_status = 'DEACTIVATED'));
  END IF;
  IF v_old.status = 'ACTIVE' AND v_old.deleted_at IS NULL
     AND homes.fn_is_home_active(v_old.id_home)
     AND devices.fn_has_device_permission(v_old.id_device, 'control') THEN
    RETURN p_name IS NOT DISTINCT FROM v_old.name
      AND p_status IS NOT DISTINCT FROM v_old.status
      AND p_connectivity_status IS NOT DISTINCT FROM v_old.connectivity_status
      AND p_transport_type IS NOT DISTINCT FROM v_old.transport_type
      AND p_messaging_protocol IS NOT DISTINCT FROM v_old.messaging_protocol
      AND p_deleted_at IS NOT DISTINCT FROM v_old.deleted_at
      AND p_is_on IS NOT NULL;
  END IF;
  RETURN FALSE;
END;
$$;
REVOKE ALL ON FUNCTION devices.fn_device_app_update_allowed(UUID, UUID, TEXT, TEXT, TEXT, BOOLEAN, TEXT, TEXT, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_device_app_update_allowed(UUID, UUID, TEXT, TEXT, TEXT, BOOLEAN, TEXT, TEXT, TIMESTAMPTZ) TO smarthome_app;

DROP POLICY IF EXISTS device_app_select_policy ON devices.device;
CREATE POLICY device_app_select_policy ON devices.device FOR SELECT TO smarthome_app
USING (homes.fn_is_home_owner(id_home) OR devices.fn_can_view_device(id_device, ARRAY['MEMBER','GUEST']::TEXT[]));

DROP POLICY IF EXISTS device_app_update_policy ON devices.device;
CREATE POLICY device_app_update_policy ON devices.device FOR UPDATE TO smarthome_app
USING (homes.fn_is_home_owner(id_home) OR devices.fn_has_device_permission(id_device, 'control'))
WITH CHECK (devices.fn_device_app_update_allowed(id_device,id_home,name,status,connectivity_status,is_on,transport_type,messaging_protocol,deleted_at));

CREATE OR REPLACE FUNCTION consumption.fn_can_read_detail(p_home_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, homes AS $$
  SELECT homes.fn_is_home_owner(p_home_id)
      OR (homes.fn_is_home_active(p_home_id)
          AND homes.fn_is_home_member(p_home_id, ARRAY['MEMBER']::TEXT[])
          AND homes.fn_has_permission(p_home_id, 'view_consumption'));
$$;
REVOKE ALL ON FUNCTION consumption.fn_can_read_detail(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION consumption.fn_can_read_detail(UUID) TO smarthome_app;

CREATE FUNCTION consumption.fn_can_read_device_detail(p_device_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, devices, consumption AS $$
  SELECT EXISTS (
    SELECT 1 FROM devices.device d
    WHERE d.id_device = p_device_id
      AND (homes.fn_is_home_owner(d.id_home)
        OR (homes.fn_is_home_active(d.id_home)
          AND homes.fn_is_home_member(d.id_home, ARRAY['MEMBER']::TEXT[])))
      AND devices.fn_has_device_permission(d.id_device, 'view_consumption')
  );
$$;
REVOKE ALL ON FUNCTION consumption.fn_can_read_device_detail(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION consumption.fn_can_read_device_detail(UUID) TO smarthome_app;

CREATE OR REPLACE FUNCTION consumption.fn_history_devices(p_home_id UUID, p_device_ids UUID[])
RETURNS TABLE(id_device UUID, name TEXT, manufacturer_device_id TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, auth, homes, devices, consumption AS $$
  SELECT d.id_device, d.name::TEXT, d.manufacturer_device_id::TEXT
  FROM devices.device d
  WHERE d.id_home = p_home_id AND d.id_device = ANY(p_device_ids)
    AND consumption.fn_can_read_device_detail(d.id_device);
$$;
REVOKE ALL ON FUNCTION consumption.fn_history_devices(UUID, UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION consumption.fn_history_devices(UUID, UUID[]) TO smarthome_app;

CREATE OR REPLACE FUNCTION consumption.fn_basic_home_consumption(p_home_id UUID, p_from TIMESTAMPTZ, p_to TIMESTAMPTZ)
RETURNS TABLE(total_energy_delta_kwh NUMERIC)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, auth, consumption, homes AS $$
  SELECT COALESCE(SUM(c.energy_delta_kwh), 0)
  FROM consumption.consumption c
  WHERE c.id_home = p_home_id AND (p_from IS NULL OR c.read_at >= p_from)
    AND (p_to IS NULL OR c.read_at <= p_to)
  HAVING homes.fn_is_home_active(p_home_id)
    AND homes.fn_is_home_member(p_home_id, ARRAY['OWNER','MEMBER','GUEST']::TEXT[])
    AND homes.fn_has_permission(p_home_id, 'view_consumption')
    AND (p_from IS NULL OR p_to IS NULL OR p_from <= p_to);
$$;
REVOKE ALL ON FUNCTION consumption.fn_basic_home_consumption(UUID, TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION consumption.fn_basic_home_consumption(UUID, TIMESTAMPTZ, TIMESTAMPTZ) TO smarthome_app;

ALTER POLICY consumption_metric_app_select_policy ON consumption.consumption_metric
USING (consumption.fn_can_read_device_detail(id_device));
ALTER POLICY consumption_app_select_policy ON consumption.consumption
USING (consumption.fn_can_read_device_detail(id_device));

CREATE FUNCTION devices.fn_device_control_target(p_home_id UUID, p_device_id UUID)
RETURNS TABLE(
  id_device UUID, id_home UUID, name VARCHAR, status VARCHAR,
  connectivity_status VARCHAR, is_on BOOLEAN, current_power_w NUMERIC,
  manufacturer_device_id VARCHAR, transport_type VARCHAR, messaging_protocol VARCHAR,
  created_at TIMESTAMPTZ, updated_at TIMESTAMPTZ, deleted_at TIMESTAMPTZ
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, auth, homes, devices AS $$
  SELECT d.id_device, d.id_home, d.name, d.status, d.connectivity_status,
    d.is_on, d.current_power_w, d.manufacturer_device_id, d.transport_type,
    d.messaging_protocol, d.created_at, d.updated_at, d.deleted_at
  FROM devices.device d
  WHERE d.id_home = p_home_id AND d.id_device = p_device_id
    AND d.status = 'ACTIVE' AND d.deleted_at IS NULL
    AND (homes.fn_is_home_owner(p_home_id)
      OR devices.fn_has_device_permission(p_device_id, 'control'));
$$;
REVOKE ALL ON FUNCTION devices.fn_device_control_target(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION devices.fn_device_control_target(UUID, UUID) TO smarthome_app;

CREATE FUNCTION homes.fn_get_member_permissions(p_home_id UUID, p_member_id UUID)
RETURNS TABLE(can_view_devices BOOLEAN, can_view_consumption BOOLEAN, can_control_devices BOOLEAN)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, homes AS $$
  SELECT hp.can_view_devices, hp.can_view_consumption, hp.can_control_devices
  FROM homes.home_member hm JOIN homes.home_member_permission hp USING (id_home_member)
  WHERE homes.fn_can_manage_home(p_home_id) AND hm.id_home = p_home_id
    AND hm.id_home_member = p_member_id AND hm.role IN ('MEMBER','GUEST');
$$;
REVOKE ALL ON FUNCTION homes.fn_get_member_permissions(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION homes.fn_get_member_permissions(UUID, UUID) TO smarthome_app;

CREATE FUNCTION homes.fn_set_member_permissions(
  p_home_id UUID, p_member_id UUID, p_can_view_devices BOOLEAN,
  p_can_view_consumption BOOLEAN, p_can_control_devices BOOLEAN
)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, homes AS $$
BEGIN
  IF NOT homes.fn_can_manage_home(p_home_id) THEN RETURN FALSE; END IF;
  UPDATE homes.home_member_permission hp SET
    can_view_devices = p_can_view_devices,
    can_view_consumption = p_can_view_consumption,
    can_control_devices = p_can_control_devices,
    updated_at = NOW()
  FROM homes.home_member hm
  WHERE hm.id_home_member = p_member_id AND hm.id_home = p_home_id
    AND hm.role IN ('MEMBER','GUEST') AND hp.id_home_member = hm.id_home_member;
  RETURN FOUND;
END;
$$;
REVOKE ALL ON FUNCTION homes.fn_set_member_permissions(UUID, UUID, BOOLEAN, BOOLEAN, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION homes.fn_set_member_permissions(UUID, UUID, BOOLEAN, BOOLEAN, BOOLEAN) TO smarthome_app;

CREATE FUNCTION homes.fn_get_device_permissions(p_home_id UUID, p_member_id UUID, p_device_id UUID)
RETURNS TABLE(can_view_device BOOLEAN, can_view_consumption BOOLEAN, can_control_device BOOLEAN)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, homes, devices AS $$
  SELECT dp.can_view_device, dp.can_view_consumption, dp.can_control_device
  FROM homes.home_member hm LEFT JOIN devices.device_member_permission dp
    ON dp.id_home_member = hm.id_home_member AND dp.id_device = p_device_id
  JOIN devices.device d ON d.id_device = p_device_id AND d.id_home = p_home_id
  WHERE homes.fn_can_manage_home(p_home_id) AND hm.id_home = p_home_id
    AND hm.id_home_member = p_member_id AND hm.role IN ('MEMBER','GUEST');
$$;
REVOKE ALL ON FUNCTION homes.fn_get_device_permissions(UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION homes.fn_get_device_permissions(UUID, UUID, UUID) TO smarthome_app;

CREATE FUNCTION homes.fn_set_device_permissions(
  p_home_id UUID, p_member_id UUID, p_device_id UUID,
  p_can_view_device BOOLEAN, p_can_view_consumption BOOLEAN, p_can_control_device BOOLEAN
)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, homes, devices AS $$
DECLARE v_membership UUID;
BEGIN
  IF NOT homes.fn_can_manage_home(p_home_id) OR NOT EXISTS (
    SELECT 1 FROM homes.home_member hm JOIN devices.device d ON d.id_home = hm.id_home
    WHERE hm.id_home_member = p_member_id AND hm.id_home = p_home_id
      AND hm.role IN ('MEMBER','GUEST') AND d.id_device = p_device_id
  ) THEN RETURN FALSE; END IF;
  IF p_can_view_device IS NULL AND p_can_view_consumption IS NULL AND p_can_control_device IS NULL THEN
    DELETE FROM devices.device_member_permission WHERE id_home_member = p_member_id AND id_device = p_device_id;
    RETURN TRUE;
  END IF;
  INSERT INTO devices.device_member_permission(id_home_member,id_device,can_view_device,can_view_consumption,can_control_device)
  VALUES (p_member_id,p_device_id,p_can_view_device,p_can_view_consumption,p_can_control_device)
  ON CONFLICT (id_home_member,id_device) DO UPDATE SET
    can_view_device = EXCLUDED.can_view_device,
    can_view_consumption = EXCLUDED.can_view_consumption,
    can_control_device = EXCLUDED.can_control_device,
    updated_at = NOW();
  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION homes.fn_set_device_permissions(UUID, UUID, UUID, BOOLEAN, BOOLEAN, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION homes.fn_set_device_permissions(UUID, UUID, UUID, BOOLEAN, BOOLEAN, BOOLEAN) TO smarthome_app;

REVOKE ALL ON homes.home_member_permission FROM PUBLIC, smarthome_app;
REVOKE ALL ON devices.device_member_permission FROM PUBLIC, smarthome_app;
