
-- SmartHome Database
-- Audit of the MQTT DEV PostgreSQL identities.
-- Preparation for a controlled migration to QA.
--
-- READ ONLY.
-- Creates no users, changes no permissions
-- and runs no migrations.

\set ON_ERROR_STOP on

BEGIN TRANSACTION READ ONLY;

SELECT
    current_database() AS database_name,
    current_user AS audit_user;

-- 1. Check the seven LOGINs and their roles.

WITH expected(login_name, functional_role) AS (
    VALUES
    (
        'smarthome_mqtt_reserver_dev_login',
        'smarthome_mqtt_reserver'
    ),
    (
        'smarthome_mqtt_lease_dev_login',
        'smarthome_mqtt_lease_worker'
    ),
    (
        'smarthome_mqtt_confirmer_dev_login',
        'smarthome_mqtt_prepare_confirmer'
    ),
    (
        'smarthome_mqtt_secret_dev_login',
        'smarthome_mqtt_secret_worker'
    ),
    (
        'smarthome_mqtt_rpc_dev_login',
        'smarthome_mqtt_rpc_worker'
    ),
    (
        'smarthome_mqtt_auth_dev_login',
        'smarthome_mqtt_auth_confirmer'
    ),
    (
        'smarthome_mqtt_revoke_dev_login',
        'smarthome_mqtt_revoke'
    )
)
SELECT
    e.login_name,
    e.functional_role,

    CASE
        WHEN l.oid IS NULL THEN 'MISSING'
        WHEN l.rolcanlogin
         AND l.rolinherit
         AND NOT l.rolsuper
         AND NOT l.rolcreatedb
         AND NOT l.rolcreaterole
         AND NOT l.rolreplication
         AND NOT l.rolbypassrls
        THEN 'PASS'
        ELSE 'FAIL'
    END AS login_security,

    CASE
        WHEN g.oid IS NULL THEN 'MISSING'
        WHEN NOT g.rolcanlogin THEN 'PASS'
        ELSE 'FAIL'
    END AS functional_role_security,

    CASE
        WHEN l.oid IS NULL OR g.oid IS NULL
            THEN 'MISSING'
        WHEN EXISTS (
            SELECT 1
            FROM pg_catalog.pg_auth_members m
            WHERE m.member = l.oid
              AND m.roleid = g.oid
        )
            THEN 'PASS'
        ELSE 'FAIL'
    END AS direct_membership,

    (
        SELECT COUNT(*)
        FROM pg_catalog.pg_auth_members m
        WHERE m.member = l.oid
    ) AS direct_membership_count

FROM expected e

LEFT JOIN pg_catalog.pg_roles l
    ON l.rolname = e.login_name

LEFT JOIN pg_catalog.pg_roles g
    ON g.rolname = e.functional_role

ORDER BY e.login_name;

-- 2. Verify the permission forbidden by SQL037.
-- Both the LOGIN and its functional role must
-- lack EXECUTE on this function.

WITH target AS (
    SELECT
        l.oid AS login_oid,
        g.oid AS role_oid,
        pg_catalog.to_regprocedure(
            'devices.fn_quarantine_expired_mqtt_pairing_lease(uuid)'
        ) AS function_oid

    FROM (SELECT 1) AS base

    LEFT JOIN pg_catalog.pg_roles l
        ON l.rolname = 'smarthome_mqtt_lease_dev_login'

    LEFT JOIN pg_catalog.pg_roles g
        ON g.rolname = 'smarthome_mqtt_lease_worker'
)
SELECT
    'SQL037_QUARANTINE_PRIVILEGE' AS check_name,

    CASE
        WHEN login_oid IS NULL
          OR role_oid IS NULL
            THEN 'MISSING_ROLE'

        WHEN function_oid IS NULL
            THEN 'MISSING_FUNCTION'

        WHEN pg_catalog.has_function_privilege(
            login_oid,
            function_oid,
            'EXECUTE'
        )
          OR pg_catalog.has_function_privilege(
            role_oid,
            function_oid,
            'EXECUTE'
        )
            THEN 'FAIL'

        ELSE 'PASS'
    END AS result

FROM target;

-- 3. Locate the Liquibase history.
-- Does not read or modify the changesets.

SELECT
    n.nspname AS schema_name,
    c.relname AS table_name

FROM pg_catalog.pg_class c

JOIN pg_catalog.pg_namespace n
    ON n.oid = c.relnamespace

WHERE LOWER(c.relname) = 'databasechangelog'
  AND c.relkind IN ('r', 'p')

ORDER BY n.nspname;

-- 4. Fail if the MQTT identities do not meet the expected contract.
-- Each LOGIN may only belong to its functional role, without administrative
-- privileges or memberships that widen its access.
DO $audit$
DECLARE
    v_expected RECORD;
    v_login_oid OID;
    v_functional_oid OID;
    v_function_oid OID;
BEGIN
    FOR v_expected IN
        SELECT *
        FROM (VALUES
            ('smarthome_mqtt_reserver_dev_login', 'smarthome_mqtt_reserver'),
            ('smarthome_mqtt_lease_dev_login', 'smarthome_mqtt_lease_worker'),
            ('smarthome_mqtt_confirmer_dev_login', 'smarthome_mqtt_prepare_confirmer'),
            ('smarthome_mqtt_secret_dev_login', 'smarthome_mqtt_secret_worker'),
            ('smarthome_mqtt_rpc_dev_login', 'smarthome_mqtt_rpc_worker'),
            ('smarthome_mqtt_auth_dev_login', 'smarthome_mqtt_auth_confirmer'),
            ('smarthome_mqtt_revoke_dev_login', 'smarthome_mqtt_revoke')
        ) AS expected(login_name, functional_role)
    LOOP
        v_login_oid := pg_catalog.to_regrole(v_expected.login_name);
        IF v_login_oid IS NULL THEN
            RAISE EXCEPTION 'SQL037_REQUIRED_LOGIN_MISSING: %', v_expected.login_name;
        END IF;

        v_functional_oid := pg_catalog.to_regrole(v_expected.functional_role);
        IF v_functional_oid IS NULL THEN
            RAISE EXCEPTION 'SQL037_REQUIRED_ROLE_MISSING: %', v_expected.functional_role;
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_roles
            WHERE oid = v_login_oid
              AND rolcanlogin
              AND rolinherit
              AND NOT rolsuper
              AND NOT rolcreatedb
              AND NOT rolcreaterole
              AND NOT rolreplication
              AND NOT rolbypassrls
        ) THEN
            RAISE EXCEPTION 'SQL037_INVALID_LOGIN_SECURITY: %', v_expected.login_name;
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_roles
            WHERE oid = v_functional_oid
              AND NOT rolcanlogin
              AND NOT rolsuper
              AND NOT rolcreatedb
              AND NOT rolcreaterole
              AND NOT rolreplication
              AND NOT rolbypassrls
        ) THEN
            RAISE EXCEPTION 'SQL037_INVALID_FUNCTIONAL_ROLE_SECURITY: %', v_expected.functional_role;
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_auth_members m
            WHERE m.member = v_login_oid
              AND m.roleid = v_functional_oid
              AND NOT m.admin_option
        ) THEN
            RAISE EXCEPTION
                'SQL037_REQUIRED_MEMBERSHIP_MISSING_OR_ADMIN_OPTION: % -> %',
                v_expected.login_name,
                v_expected.functional_role;
        END IF;

        IF EXISTS (
            SELECT 1
            FROM pg_catalog.pg_auth_members m
            WHERE m.member = v_login_oid
              AND m.roleid <> v_functional_oid
        ) THEN
            RAISE EXCEPTION 'SQL037_ADDITIONAL_LOGIN_MEMBERSHIP: %', v_expected.login_name;
        END IF;

        IF EXISTS (
            SELECT 1
            FROM pg_catalog.pg_auth_members m
            WHERE m.member = v_functional_oid
        ) THEN
            RAISE EXCEPTION
                'SQL037_ADDITIONAL_FUNCTIONAL_ROLE_MEMBERSHIP: %',
                v_expected.functional_role;
        END IF;
    END LOOP;

    v_function_oid := pg_catalog.to_regprocedure(
        'devices.fn_quarantine_expired_mqtt_pairing_lease(uuid)'
    );

    IF v_function_oid IS NULL THEN
        RAISE EXCEPTION 'SQL037_REQUIRED_FUNCTION_MISSING';
    END IF;

    IF pg_catalog.to_regrole('smarthome_mqtt_lease_dev_login') IS NULL
       OR pg_catalog.to_regrole('smarthome_mqtt_lease_worker') IS NULL THEN
        RAISE EXCEPTION 'SQL037_REQUIRED_ROLE_MISSING';
    END IF;

    IF pg_catalog.has_function_privilege(
        'smarthome_mqtt_lease_dev_login',
        v_function_oid,
        'EXECUTE'
    )
    OR pg_catalog.has_function_privilege(
        'smarthome_mqtt_lease_worker',
        v_function_oid,
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'SQL037_FORBIDDEN_EXECUTE_PRIVILEGE';
    END IF;
END
$audit$;

ROLLBACK;
