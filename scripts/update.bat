@echo off
setlocal

echo [1/2] Validando changelogs...
docker compose run --rm liquibase --defaults-file=liquibase.properties validate
if errorlevel 1 exit /b %errorlevel%

echo [2/2] Aplicando migraciones...
docker compose run --rm liquibase --defaults-file=liquibase.properties update
if errorlevel 1 exit /b %errorlevel%

endlocal
