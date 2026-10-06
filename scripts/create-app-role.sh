#!/bin/sh
set -eu

: "${APP_DB_PASSWORD:?APP_DB_PASSWORD is required}"
: "${IOT_DB_PASSWORD:?IOT_DB_PASSWORD is required}"

psql \
  --set=ON_ERROR_STOP=1 \
  --set=app_password="$APP_DB_PASSWORD" \
  --set=iot_password="$IOT_DB_PASSWORD" <<'SQL'
SELECT 'CREATE ROLE smarthome_app_local LOGIN'
WHERE NOT EXISTS (
  SELECT 1 FROM pg_roles WHERE rolname = 'smarthome_app_local'
)
\gexec

SELECT format(
  'ALTER ROLE smarthome_app_local PASSWORD %L',
  :'app_password'
)
\gexec

GRANT smarthome_app TO smarthome_app_local;

SELECT 'CREATE ROLE smarthome_ingest_local LOGIN'
WHERE NOT EXISTS (
  SELECT 1 FROM pg_roles WHERE rolname = 'smarthome_ingest_local'
)
\gexec

SELECT format(
  'ALTER ROLE smarthome_ingest_local PASSWORD %L',
  :'iot_password'
)
\gexec

GRANT smarthome_ingest TO smarthome_ingest_local;
SQL
