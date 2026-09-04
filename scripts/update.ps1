$ErrorActionPreference = 'Stop'
docker compose run --rm liquibase --defaults-file=liquibase.properties validate
docker compose run --rm liquibase --defaults-file=liquibase.properties update-sql
docker compose run --rm liquibase --defaults-file=liquibase.properties update
