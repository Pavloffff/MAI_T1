# Сценарии отказоустойчивости для ручного тестирования
# Запускайте при работающем traffic-generator.py

param(
    [ValidateSet('stop-leader', 'stop-replica', 'stop-etcd', 'stop-haproxy', 'status', 'restore')]
    [string]$Action = 'status'
)

function Show-Status {
    Write-Host "`n=== patronictl list ==="
    docker exec demo-patroni1 patronictl list 2>$null
    if ($LASTEXITCODE -ne 0) { docker exec demo-patroni2 patronictl list }
}

switch ($Action) {
    'status'   { Show-Status }
    'stop-leader' {
        $leader = (docker exec demo-patroni1 patronictl list -f json 2>$null | ConvertFrom-Json | Where-Object { $_.Role -eq 'Leader' }).Member
        Write-Host "Stopping leader: $leader"
        docker stop "demo-$leader"
        Start-Sleep -Seconds 20
        Show-Status
    }
    'stop-replica' {
        Write-Host "Stopping replica: patroni1"
        docker stop demo-patroni1
        Start-Sleep -Seconds 5
        Show-Status
    }
    'stop-etcd' {
        Write-Host "Stopping etcd1 (quorum 2/3 remains)"
        docker stop demo-etcd1
        Start-Sleep -Seconds 5
        Show-Status
    }
    'stop-haproxy' {
        Write-Host "Stopping HAProxy - apps lose DB endpoint"
        docker stop demo-haproxy
    }
    'restore' {
        docker start demo-patroni1 demo-patroni2 demo-patroni3 demo-etcd1 demo-etcd2 demo-etcd3 demo-haproxy 2>$null
        Start-Sleep -Seconds 15
        Show-Status
    }
}
