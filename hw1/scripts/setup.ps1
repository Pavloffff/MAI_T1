$Root = Split-Path $PSScriptRoot -Parent
$DemoApp = Join-Path $Root "..\example-sd-repo\demo-app-1"
$Hw1Backend = Join-Path $Root "backend\main.go"

Write-Host "==> Applying enhanced backend with extra metrics..."
Copy-Item $Hw1Backend (Join-Path $DemoApp "backend\main.go") -Force

Write-Host "==> Copying k6 scripts to demo-app-1..."
$K6Dest = Join-Path $DemoApp "k6\scripts\hw1"
New-Item -ItemType Directory -Force -Path $K6Dest | Out-Null
Copy-Item (Join-Path $Root "k6\scripts\*") $K6Dest -Force

Write-Host "==> Starting docker compose..."
Set-Location $DemoApp
docker compose up -d --build

Write-Host "`nWait 20 seconds for services to start..."
Start-Sleep -Seconds 20

Write-Host "==> Health check..."
curl.exe -s http://localhost:8081/api/users
Write-Host "`n`nSetup complete. Run: .\hw1\scripts\run-load-tests.ps1"
