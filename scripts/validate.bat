
@echo off
setlocal

echo ==========================================
echo   SmartHome Database - Validation
echo ==========================================
echo.

powershell.exe -NoProfile -File "%~dp0validate.ps1"

set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo ERROR: La validacion fallo.
)

endlocal & exit /b %EXIT_CODE%
