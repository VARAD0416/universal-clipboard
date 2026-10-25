# manage.ps1
# ============================================================
# Day-to-day management for Universal Clipboard Daemon
# Usage:  .\manage.ps1 [status|start|stop|restart|logs|test]
# ============================================================

param([string]$Command = "status")

$pidFile  = Join-Path $PSScriptRoot "scripts\clipboard_daemon.pid"
$logFile  = Join-Path $PSScriptRoot "scripts\clipboard_daemon.log"
$launcher = Join-Path $PSScriptRoot "scripts\clipboard_daemon_launcher.ps1"
$taskPath = "\CustomTasks\"
$taskName = "UniversalClipboardDaemon"
$port     = 8765
$mdns     = "$env:COMPUTERNAME.local"

function Show-Status {
    Write-Host "`n── Daemon Process ───────────────────────────────" -ForegroundColor Cyan
    $procs = Get-Process -Name "pythonw" -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | ForEach-Object {
            Write-Host "  ✅ pythonw running  PID=$($_.Id)  Mem=$([math]::Round($_.WorkingSet64/1MB,1))MB  CPU=$($_.CPU)s" -ForegroundColor Green
        }
    } else {
        Write-Host "  ❌ Daemon NOT running" -ForegroundColor Red
    }

    Write-Host "`n── Task Scheduler ───────────────────────────────" -ForegroundColor Cyan
    $info = Get-ScheduledTaskInfo -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    if ($info) {
        $result = if ($info.LastTaskResult -eq 0) { "✅ Success (0x0)" } else { "⚠  Code $($info.LastTaskResult)" }
        Write-Host "  Last run : $($info.LastRunTime)"
        Write-Host "  Result   : $result"
        Write-Host "  Next run : $($info.NextRunTime)"
    } else {
        Write-Host "  ⚠  Task not registered. Run install.ps1 first." -ForegroundColor Yellow
    }

    Write-Host "`n── Port $port ─────────────────────────────────────" -ForegroundColor Cyan
    $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($conn) {
        Write-Host "  ✅ Port $port LISTENING  (PID $($conn.OwningProcess))" -ForegroundColor Green
    } else {
        Write-Host "  ❌ Nothing listening on port $port" -ForegroundColor Red
    }
    Write-Host ""
}

function Start-Daemon {
    Write-Host "Starting daemon via Task Scheduler..." -ForegroundColor Yellow
    Start-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Show-Status
}

function Stop-Daemon {
    Write-Host "Stopping daemon..." -ForegroundColor Yellow
    if (Test-Path $pidFile) {
        $id = Get-Content $pidFile
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
        Remove-Item $pidFile -Force
        Write-Host "  Killed PID $id" -ForegroundColor Green
    } else {
        Get-Process -Name "pythonw" -ErrorAction SilentlyContinue | Stop-Process -Force
        Write-Host "  All pythonw processes killed" -ForegroundColor Green
    }
}

function Restart-Daemon {
    Stop-Daemon
    Start-Sleep -Seconds 1
    Start-Daemon
}

function Show-Logs {
    if (Test-Path $logFile) {
        Write-Host "`n── Last 40 log lines ──────────────────────────" -ForegroundColor Cyan
        Get-Content $logFile -Tail 40
    } else {
        Write-Host "Log file not found: $logFile" -ForegroundColor Yellow
    }
}

function Test-Endpoint {
    Write-Host "`n── Endpoint Test ────────────────────────────────" -ForegroundColor Cyan
    $urls = @("http://localhost:$port/health", "http://$mdns`:$port/health")
    foreach ($url in $urls) {
        try {
            $r = Invoke-RestMethod -Uri $url -TimeoutSec 3
            Write-Host "  ✅ $url -> $($r | ConvertTo-Json -Compress)" -ForegroundColor Green
        } catch {
            Write-Host "  ❌ $url -> $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    Write-Host ""
}

switch ($Command.ToLower()) {
    "status"  { Show-Status }
    "start"   { Start-Daemon }
    "stop"    { Stop-Daemon }
    "restart" { Restart-Daemon }
    "logs"    { Show-Logs }
    "test"    { Test-Endpoint }
    default   {
        Write-Host "Usage: .\manage.ps1 [status|start|stop|restart|logs|test]"
    }
}
