-- HU 09-dev / BD-02. Execute with the actual application OR ingestion LOGIN.
-- psql parameter expected_role must be smarthome_runtime_app or smarthome_ingest.
-- This script only reads PostgreSQL catalogs; it never changes roles or schemas.
BEGIN TRANSACTION READ ONLY;

WITH
expected AS (
  SELECT :'expected_role'::text AS role_name,
         to_regrole(:'expected_role') AS role_id
),
protected_tables(schema_name, table_name) AS (
  VALUES ('homes', 'home'),
         ('homes', 'home_member'),
         ('devices', 'device'),
         ('consumption', 'consumption'),
         ('consumption', 'consumption_metric'),
         ('notifications', 'notification'),
         ('notifications', 'alert'),
         ('identity_audit', 'audit_log')
),
relations AS (
  SELECT t.schema_name, t.table_name, c.oid, c.relowner, c.relrowsecurity
  FROM protected_tables t
  LEFT JOIN pg_namespace n ON n.nspname = t.schema_name
  LEFT JOIN pg_class c ON c.relnamespace = n.oid
                     AND c.relname = t.table_name
                     AND c.relkind IN ('r', 'p')
),
checks(check_name, passed) AS (
  SELECT 'expected_runtime_role',
    role_name IN ('smarthome_runtime_app', 'smarthome_ingest') AND role_id IS NOT NULL
  FROM expected
  UNION ALL
  SELECT 'expected_role_privileges_active',
    COALESCE(pg_has_role(current_user, role_id, 'USAGE'), false)
  FROM expected
  UNION ALL
  SELECT 'login_and_active_role_not_privileged',
    NOT EXISTS (
      SELECT 1 FROM pg_roles r
      WHERE r.rolname IN (session_user, current_user)
        AND (r.rolsuper OR r.rolbypassrls OR r.rolcreaterole OR r.rolcreatedb)
    )
  UNION ALL
  SELECT 'cannot_assume_privileged_role',
    NOT EXISTS (
      SELECT 1 FROM pg_roles r
      WHERE (r.rolsuper OR r.rolbypassrls OR r.rolcreaterole OR r.rolcreatedb)
        AND (pg_has_role(session_user, r.oid, 'MEMBER')
          OR pg_has_role(current_user, r.oid, 'MEMBER'))
    )
  UNION ALL
  SELECT 'application_and_ingest_memberships_separate',
    NOT COALESCE(pg_has_role(
      session_user,
      to_regrole(CASE WHEN role_name = 'smarthome_runtime_app'
                     THEN 'smarthome_ingest' ELSE 'smarthome_runtime_app' END),
      'MEMBER'
    ), true)
    AND NOT COALESCE(pg_has_role(
      current_user,
      to_regrole(CASE WHEN role_name = 'smarthome_runtime_app'
                     THEN 'smarthome_ingest' ELSE 'smarthome_runtime_app' END),
      'MEMBER'
    ), true)
  FROM expected
  UNION ALL
  SELECT 'protected_tables_present_and_rls_enabled',
    bool_and(oid IS NOT NULL AND COALESCE(relrowsecurity, false))
  FROM relations
  UNION ALL
  SELECT 'cannot_assume_protected_table_owner',
    NOT EXISTS (
      SELECT 1 FROM relations r
      WHERE pg_has_role(session_user, r.relowner, 'MEMBER')
         OR pg_has_role(current_user, r.relowner, 'MEMBER')
    )
  UNION ALL
  SELECT 'cannot_assume_database_owner',
    NOT EXISTS (
      SELECT 1 FROM pg_database d
      WHERE d.datname = current_database()
        AND (pg_has_role(session_user, d.datdba, 'MEMBER')
          OR pg_has_role(current_user, d.datdba, 'MEMBER'))
    )
  UNION ALL
  SELECT 'no_physical_device_delete',
    COALESCE(NOT has_table_privilege(current_user, oid, 'DELETE'), false)
  FROM relations WHERE schema_name = 'devices' AND table_name = 'device'
)
SELECT check_name,
       CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY check_name;

ROLLBACK;
