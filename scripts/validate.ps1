$ErrorActionPreference = 'Stop'
docker compose run --rm liquibase --defaults-file=liquibase.properties validate
