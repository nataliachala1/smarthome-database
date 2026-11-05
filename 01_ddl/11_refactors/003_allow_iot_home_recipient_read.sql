GRANT SELECT
ON TABLE homes.home
TO smarthome_ingest;

GRANT SELECT
ON TABLE homes.home_member
TO smarthome_ingest;


CREATE POLICY home_ingest_select_policy
ON homes.home
FOR SELECT
TO smarthome_ingest
USING (
    status = 'ACTIVE'
    AND deleted_at IS NULL
);


CREATE POLICY home_member_ingest_select_policy
ON homes.home_member
FOR SELECT
TO smarthome_ingest
USING (
    status = 'ACTIVE'
);