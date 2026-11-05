
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (
    Join-Path $PSScriptRoot '..'
)).Path

Push-Location $projectRoot

try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker no esta disponible.'
    }

    if (-not (Test-Path '.env')) {
        throw 'No existe .env. Configure primero el entorno local.'
    }

    Write-Host ''
    Write-Host 'SmartHome Database - Liquibase' -ForegroundColor Cyan
    Write-Host 'Validacion de changelogs'
    Write-Host ''

    & docker compose run --rm liquibase `
        --defaults-file=liquibase.properties validate

    if ($LASTEXITCODE -ne 0) {
        throw "Validacion Liquibase fallida. Codigo: $LASTEXITCODE"
    }

    Write-Host ''
    Write-Host 'Changelog validado correctamente.' -ForegroundColor Green
    Write-Host 'No se solicitaron migraciones.'
}
finally {
    Pop-Location
}
