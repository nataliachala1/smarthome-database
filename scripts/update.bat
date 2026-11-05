
@echo off
setlocal

echo ==========================================
echo   SmartHome Database - Liquibase
echo ==========================================
echo.
echo Las migraciones no se aplican por defecto.
echo.

powershell.exe -NoProfile -File "%~dp0update.ps1" %*

set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo ERROR: La operacion no finalizo correctamente.
)

endlocal & exit /b %EXIT_CODE%
