
-- SmartHome Database
-- Auditoria de identidades PostgreSQL MQTT DEV.
-- Preparacion para migracion controlada a QA.
--
-- SOLO LECTURA.
-- No crea usuarios, no cambia permisos
-- y no ejecuta migraciones.

\set ON_ERROR_STOP on

BEGIN TRANSACTION READ ONLY;

SELECT
    current_database() AS database_name,
    current_user AS audit_user;

-- 1. Comprobar los siete LOGIN y sus roles.

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

-- 2. Verificar el permiso prohibido por SQL037.
-- Tanto el LOGIN como su rol funcional deben
-- carecer de EXECUTE sobre esta funcion.

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

-- 3. Localizar el historial Liquibase.
-- No consulta ni modifica los changesets.

SELECT
    n.nspname AS schema_name,
    c.relname AS table_name

FROM pg_catalog.pg_class c

JOIN pg_catalog.pg_namespace n
    ON n.oid = c.relnamespace

WHERE LOWER(c.relname) = 'databasechangelog'
  AND c.relkind IN ('r', 'p')

ORDER BY n.nspname;

ROLLBACK;
