# install.ps1
# ============================================================
# One-shot setup script for Universal Clipboard Daemon
# Run as Administrator in PowerShell
# ============================================================

param(
    [string]$DaemonPath = "$PSScriptRoot\clipboard_daemon.py",
    [string]$LauncherPath = "$PSScriptRoot\scripts\clipboard_daemon_launcher.ps1",
    [int]$Port = 8765
)

Write-Host "`n=== Universal Clipboard — Install Script ===" -ForegroundColor Cyan

# ── 1. Verify pythonw.exe ──────────────────────────────────
Write-Host "`n[1/5] Checking pythonw.exe..." -ForegroundColor Yellow
$pythonw = (Get-Command pythonw.exe -ErrorAction SilentlyContinue)?.Source
if ($pythonw) {
    Write-Host "  ✅ Found: $pythonw" -ForegroundColor Green
} else {
    Write-Host "  ❌ pythonw.exe not found. Install Python from python.org" -ForegroundColor Red
    exit 1
}

# ── 2. Check / Install Bonjour ────────────────────────────
Write-Host "`n[2/5] Checking Bonjour / mDNS..." -ForegroundColor Yellow
$bonjour = Get-Service "Bonjour Service" -ErrorAction SilentlyContinue
if ($bonjour -and $bonjour.Status -eq "Running") {
    Write-Host "  ✅ Bonjour Service is running" -ForegroundColor Green
} else {
    Write-Host "  ⚠  Bonjour Service not found — installing..." -ForegroundColor Yellow
    winget install --id Apple.Bonjour -e --silent
    Start-Service "Bonjour Service" -ErrorAction SilentlyContinue
}

# Enable Windows mDNS
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters"
Set-ItemProperty -Path $regPath -Name EnableMDNS -Value 1 -Type DWord -ErrorAction SilentlyContinue
Restart-Service Dnscache -ErrorAction SilentlyContinue
Write-Host "  ✅ Windows mDNS registry key set" -ForegroundColor Green

# ── 3. Firewall rule ──────────────────────────────────────
Write-Host "`n[3/5] Configuring Firewall (port $Port)..." -ForegroundColor Yellow
$existing = Get-NetFirewallRule -DisplayName "Universal Clipboard Daemon" -ErrorAction SilentlyContinue
if (-not $existing) {
    New-NetFirewallRule `
        -DisplayName "Universal Clipboard Daemon" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $Port `
        -Action Allow `
        -Profile Private | Out-Null
    Write-Host "  ✅ Firewall rule created" -ForegroundColor Green
} else {
    Write-Host "  ✅ Firewall rule already exists" -ForegroundColor Green
}

# ── 4. Register Task Scheduler ───────────────────────────
Write-Host "`n[4/5] Registering Task Scheduler job..." -ForegroundColor Yellow
$action   = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-WindowStyle Hidden -NonInteractive -File `"$LauncherPath`""
$trigger  = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 0) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName "UniversalClipboardDaemon" `
    -TaskPath "\CustomTasks\" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Force | Out-Null

Write-Host "  ✅ Task Scheduler job registered" -ForegroundColor Green

# ── 5. Start immediately ─────────────────────────────────
Write-Host "`n[5/5] Starting daemon now..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName "UniversalClipboardDaemon" -TaskPath "\CustomTasks\"
Start-Sleep -Seconds 2
$proc = Get-Process pythonw -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "  ✅ Daemon is running — PID(s): $($proc.Id -join ', ')" -ForegroundColor Green
} else {
    Write-Host "  ⚠  Daemon did not start. Check: $PSScriptRoot\scripts\clipboard_daemon.log" -ForegroundColor Yellow
}

# ── Summary ────────────────────────────────────────────────
$mdns = "$env:COMPUTERNAME.local"
Write-Host "`n=== Setup Complete ===" -ForegroundColor Cyan
Write-Host "  .local address : http://$mdns`:$Port"
Write-Host "  GET clipboard  : curl http://$mdns`:$Port/clipboard"
Write-Host "  POST clipboard : curl -X POST http://$mdns`:$Port/clipboard -H 'Content-Type: application/json' -d '{`"text`":`"hello`"}'"
Write-Host ""
