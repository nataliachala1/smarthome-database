DROP POLICY IF EXISTS home_select_policy
ON homes.home;

CREATE POLICY home_select_policy
ON homes.home
FOR SELECT
TO smarthome_app
USING (
    homes.fn_is_home_owner(id_home)

    OR (
        homes.fn_is_home_active(id_home)
        AND homes.fn_has_home_membership(
            id_home,
            ARRAY['PENDING', 'ACTIVE']::text[]
        )
    )
);