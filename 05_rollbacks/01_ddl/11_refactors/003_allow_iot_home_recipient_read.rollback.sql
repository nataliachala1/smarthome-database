DROP POLICY IF EXISTS home_member_ingest_select_policy
ON homes.home_member;

DROP POLICY IF EXISTS home_ingest_select_policy
ON homes.home;

REVOKE SELECT
ON TABLE homes.home_member
FROM smarthome_ingest;

REVOKE SELECT
ON TABLE homes.home
FROM smarthome_ingest;
