
[CmdletBinding()]
param(
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Invoke-Liquibase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    Write-Host ""
    Write-Host "Liquibase: $Command" -ForegroundColor Cyan

    & docker compose run --rm liquibase `
        --defaults-file=liquibase.properties $Command

    if ($LASTEXITCODE -ne 0) {
        throw "Liquibase $Command fallo. Codigo: $LASTEXITCODE"
    }
}

Push-Location $projectRoot

try {
    if (-not (Test-Path '.env')) {
        throw 'No existe .env local. Configure primero el entorno de pruebas.'
    }

    $composeConfig = & docker compose config --format json

    if ($LASTEXITCODE -ne 0) {
        throw 'No se pudo validar la configuracion Docker Compose.'
    }

    $config = ($composeConfig | Out-String) | ConvertFrom-Json
    $databaseUrl = $config.services.liquibase.environment.LIQUIBASE_COMMAND_URL

    if ($databaseUrl -notmatch '^jdbc:postgresql://postgres:5432/') {
        throw 'Destino no autorizado: se exige PostgreSQL del Compose local.'
    }

    Write-Host 'Destino: PostgreSQL del Compose local' -ForegroundColor Yellow

    Invoke-Liquibase 'validate'
    Invoke-Liquibase 'update-sql'

    if (-not $Apply) {
        Write-Host ''
        Write-Host 'Validacion finalizada.' -ForegroundColor Green
        Write-Host 'No se aplicaron migraciones.'
        Write-Host 'Revise el SQL generado antes de autorizar cualquier cambio.'
        return
    }

    Write-Host ''
    Write-Warning 'Esta operacion MODIFICA la base de datos configurada.'

    $confirmation = Read-Host 'Escriba APLICAR-LOCAL para continuar'

    if ($confirmation -cne 'APLICAR-LOCAL') {
        throw 'Operacion cancelada. No se aplicaron migraciones.'
    }

    Invoke-Liquibase 'update'

    Write-Host ''
    Write-Host 'Migraciones locales aplicadas.' -ForegroundColor Green
}
finally {
    Pop-Location
}
