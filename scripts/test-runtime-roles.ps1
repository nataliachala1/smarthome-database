param(
  [string]$PostgresImage = 'postgres:16-alpine'
)

$ErrorActionPreference = 'Stop'
$auditFile = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'audit-runtime-roles.sql')).Path
$testContainer = 'smarthome-hu09-test-' + [guid]::NewGuid().ToString('N')
$started = $false

function Assert-Audit {
  param(
    [string]$Login,
    [string]$ExpectedRole,
    [string[]]$ExpectedFailures = @(),
    [switch]$MaskWithAppRole
  )

  $arguments = @('exec', $testContainer, 'psql', '-X', '-qAt', '-U', $Login,
    '-d', 'postgres', '--set=ON_ERROR_STOP=1', "--set=expected_role=$ExpectedRole")
  if ($MaskWithAppRole) { $arguments += @('-c', 'SET ROLE smarthome_app') }
  $arguments += @('--file=/audit.sql')
  $rows = @(& docker @arguments)
  if ($LASTEXITCODE -ne 0) { throw "SQL audit failed for test case $Login" }
  $results = @($rows | Where-Object { $_ -match '^[a-z_]+\|(PASS|FAIL)$' })
  if ($results.Count -ne 9) { throw 'Expected exactly nine catalog checks' }
  $failures = @($results | Where-Object { $_ -like '*|FAIL' } | ForEach-Object { ($_ -split '\|')[0] })
  $expectedList = ($ExpectedFailures | Sort-Object) -join ','
  $actualList = ($failures | Sort-Object) -join ','
  if ($expectedList -cne $actualList) {
    throw "Unexpected catalog-check results in test case $Login : $($failures -join ', ')"
  }
  Write-Output "PASS: $Login / $ExpectedRole (negative checks: $($failures.Count))"
}

try {
  # New, isolated, ephemeral PostgreSQL. No host ports, existing volumes, or secrets.
  $containerId = & docker run --detach --rm --network none --name $testContainer `
    --env POSTGRES_HOST_AUTH_METHOD=trust `
    --tmpfs /var/lib/postgresql/data:rw,size=268435456 `
    --mount "type=bind,source=$auditFile,target=/audit.sql,readonly" $PostgresImage
  if ($LASTEXITCODE -ne 0) { throw 'Unable to start isolated PostgreSQL test container' }
  $started = $true
  $ready = $false
  for ($attempt = 0; $attempt -lt 30; $attempt++) {
    # The image uses a temporary Unix-socket-only server during initialization.
    # TCP on loopback becomes ready only when the final test server has started.
    & docker exec $testContainer pg_isready -q -h 127.0.0.1 -U postgres
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Milliseconds 500
  }
  if (-not $ready) { throw 'Isolated PostgreSQL did not become ready' }

  $fixture = @'
CREATE ROLE smarthome_app NOLOGIN NOBYPASSRLS;
CREATE ROLE smarthome_ingest NOLOGIN NOBYPASSRLS;
CREATE ROLE smarthome_admin NOLOGIN BYPASSRLS;
CREATE ROLE app_test_login LOGIN IN ROLE smarthome_app;
CREATE ROLE ingest_test_login LOGIN IN ROLE smarthome_ingest;
CREATE ROLE unsafe_test_login LOGIN IN ROLE smarthome_app, smarthome_admin;
CREATE SCHEMA homes;
CREATE SCHEMA devices;
CREATE SCHEMA consumption;
CREATE SCHEMA notifications;
CREATE SCHEMA identity_audit;
CREATE TABLE homes.home (id integer);
CREATE TABLE homes.home_member (id integer);
CREATE TABLE devices.device (id integer);
CREATE TABLE consumption.consumption (id integer);
CREATE TABLE consumption.consumption_metric (id integer);
CREATE TABLE notifications.notification (id integer);
CREATE TABLE notifications.alert (id integer);
CREATE TABLE identity_audit.audit_log (id integer);
ALTER TABLE homes.home ENABLE ROW LEVEL SECURITY;
ALTER TABLE homes.home_member ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices.device ENABLE ROW LEVEL SECURITY;
ALTER TABLE consumption.consumption ENABLE ROW LEVEL SECURITY;
ALTER TABLE consumption.consumption_metric ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications.notification ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications.alert ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity_audit.audit_log ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON devices.device TO smarthome_app, smarthome_ingest;
'@
  $fixture | & docker exec -i $testContainer psql -X -q -U postgres -d postgres -v ON_ERROR_STOP=1
  if ($LASTEXITCODE -ne 0) { throw 'Unable to prepare isolated test fixture' }

  Assert-Audit -Login app_test_login -ExpectedRole smarthome_app
  Assert-Audit -Login ingest_test_login -ExpectedRole smarthome_ingest
  Assert-Audit -Login unsafe_test_login -ExpectedRole smarthome_app `
    -ExpectedFailures @('cannot_assume_privileged_role')
  Assert-Audit -Login app_test_login -ExpectedRole smarthome_ingest `
    -ExpectedFailures @('expected_role_privileges_active', 'application_and_ingest_memberships_separate')
  Assert-Audit -Login postgres -ExpectedRole smarthome_app -MaskWithAppRole `
    -ExpectedFailures @('login_and_active_role_not_privileged', 'cannot_assume_privileged_role',
      'application_and_ingest_memberships_separate', 'cannot_assume_protected_table_owner',
      'cannot_assume_database_owner')

  & docker exec $testContainer psql -X -q -U postgres -d postgres -v ON_ERROR_STOP=1 `
    -c 'ALTER TABLE devices.device DISABLE ROW LEVEL SECURITY'
  if ($LASTEXITCODE -ne 0) { throw 'Unable to prepare negative RLS scenario' }
  Assert-Audit -Login app_test_login -ExpectedRole smarthome_app `
    -ExpectedFailures @('protected_tables_present_and_rls_enabled')
  Write-Output 'All six isolated PostgreSQL role-audit scenarios passed.'
}
finally {
  if ($started) {
    # Only the unique container created above, never an existing service/volume.
    & docker rm --force $testContainer | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Unable to remove the isolated test container' }
  }
}
