param(
    [ValidateSet('storm', 'wave', 'custom', 'all')]
    [string]$Scenario = 'all'
)

$DemoAppPath = Join-Path $PSScriptRoot "..\..\example-sd-repo\demo-app-1"
$ScriptsPath = Join-Path $PSScriptRoot "..\k6\scripts"

if (-not (Test-Path $DemoAppPath)) {
    Write-Error "demo-app-1 not found at $DemoAppPath"
    exit 1
}

Write-Host "==> Seeding test users..."
curl.exe -s -X POST http://localhost:8081/api/users -H "Content-Type: application/json" -d '{"name":"User1","email":"user1@test.local"}' | Out-Null
curl.exe -s -X POST http://localhost:8081/api/users -H "Content-Type: application/json" -d '{"name":"User2","email":"user2@test.local"}' | Out-Null

$scripts = @{
    storm  = 'storm.js'
    wave   = 'wave.js'
    custom = 'custom-sawtooth.js'
}

function Run-K6([string]$ScriptName) {
    $resultsPath = Join-Path $PSScriptRoot "..\results"
    $baseName = $ScriptName -replace '\.js$',''
    New-Item -ItemType Directory -Force -Path $resultsPath | Out-Null
    Write-Host "`n==> Running $ScriptName ..."
    docker run --rm --network host `
        -v "${ScriptsPath}:/scripts:ro" `
        -v "${resultsPath}:/results" `
        -e K6_PROMETHEUS_RW_SERVER_URL=http://localhost:9090/api/v1/write `
        -e K6_PROMETHEUS_RW_TREND_STATS=p(95),p(99),min,max `
        grafana/k6:latest run --summary-export="/results/${baseName}_summary.json" /scripts/$ScriptName
}

if ($Scenario -eq 'all') {
    foreach ($s in $scripts.Values) { Run-K6 $s }
} else {
    Run-K6 $scripts[$Scenario]
}

Write-Host "`nDone. Check Grafana at http://localhost:3000 and results in hw1/results/"
