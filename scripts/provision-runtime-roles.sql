-- Runs only against the verified existing SmartHome database after Liquibase.
-- The passwords are read from the container environment and never printed.
\getenv app_password APP_DB_PASSWORD
\getenv ingest_password IOT_DB_PASSWORD

SELECT format(
  'CREATE ROLE smarthome_app_login LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS PASSWORD %L',
  :'app_password'
)
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_roles
  WHERE rolname = 'smarthome_app_login'
)
\gexec

ALTER ROLE smarthome_app_login
  LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS
  PASSWORD :'app_password';

SELECT format(
  'CREATE ROLE smarthome_ingest_login LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS PASSWORD %L',
  :'ingest_password'
)
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_roles
  WHERE rolname = 'smarthome_ingest_login'
)
\gexec

ALTER ROLE smarthome_ingest_login
  LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS
  PASSWORD :'ingest_password';

REVOKE smarthome_ingest, smarthome_admin, smarthome_worker,
  smarthome_readonly FROM smarthome_app_login;
REVOKE smarthome_runtime_app, smarthome_admin, smarthome_worker,
  smarthome_readonly FROM smarthome_ingest_login;

GRANT smarthome_runtime_app TO smarthome_app_login;
GRANT smarthome_ingest TO smarthome_ingest_login;
