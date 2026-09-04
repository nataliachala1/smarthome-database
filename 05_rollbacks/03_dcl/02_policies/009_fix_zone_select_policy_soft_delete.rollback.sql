ALTER POLICY zone_select_policy
ON homes.zone
USING (
    deleted_at IS NULL
    AND (
        homes.fn_is_home_owner(id_home)
        OR (
            homes.fn_is_home_active(id_home)
            AND homes.fn_is_home_member(
                id_home,
                ARRAY['MEMBER'::text, 'GUEST'::text]
            )
        )
    )
);