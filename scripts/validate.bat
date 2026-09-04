@echo off
setlocal
docker compose run --rm liquibase --defaults-file=liquibase.properties validate
exit /b %errorlevel%
