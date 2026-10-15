-- Restore the previous contract only with the previous backend version.
-- This restores GUEST access to detailed rows; never apply as an isolated fix.
ALTER POLICY consumption_app_select_policy ON consumption.consumption
USING (homes.fn_is_home_owner(id_home) OR (
  homes.fn_is_home_active(id_home)
  AND homes.fn_is_home_member(id_home, ARRAY['MEMBER', 'GUEST']::TEXT[])
));
ALTER POLICY consumption_metric_app_select_policy ON consumption.consumption_metric
USING (homes.fn_is_home_owner(id_home) OR (
  homes.fn_is_home_active(id_home)
  AND homes.fn_is_home_member(id_home, ARRAY['MEMBER', 'GUEST']::TEXT[])
));
DROP FUNCTION consumption.fn_history_devices(UUID, UUID[]);
DROP FUNCTION consumption.fn_basic_home_consumption(UUID, TIMESTAMPTZ, TIMESTAMPTZ);
DROP FUNCTION consumption.fn_can_read_detail(UUID);
