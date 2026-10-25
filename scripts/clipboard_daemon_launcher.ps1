# clipboard_daemon_launcher.ps1
# ============================================================
# Launches clipboard_daemon.py silently using pythonw.exe
# Save to: C:\Scripts\clipboard_daemon_launcher.ps1
# ============================================================

$pythonw = (Get-Command pythonw.exe -ErrorAction SilentlyContinue)?.Source
if (-not $pythonw) {
    # Try common Python install paths
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Python\Python312\pythonw.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\pythonw.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python310\pythonw.exe",
        "C:\Python312\pythonw.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { $pythonw = $c; break } }
}

if (-not $pythonw) {
    Write-Error "pythonw.exe not found. Install Python and try again."; exit 1
}

$script  = Join-Path $PSScriptRoot "clipboard_daemon.py"
$logDir  = $PSScriptRoot
$logFile = Join-Path $logDir "clipboard_daemon.log"
$pidFile = Join-Path $logDir "clipboard_daemon.pid"

# Kill existing instance
if (Test-Path $pidFile) {
    $oldPid = Get-Content $pidFile -ErrorAction SilentlyContinue
    if ($oldPid) { Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue }
    Remove-Item $pidFile -Force
}

# Start daemon headlessly
$proc = Start-Process `
    -FilePath $pythonw `
    -ArgumentList "`"$script`"" `
    -RedirectStandardOutput $logFile `
    -RedirectStandardError  "$logFile.err" `
    -WindowStyle Hidden `
    -PassThru

$proc.Id | Out-File $pidFile -Encoding ASCII
Write-Host "[$(Get-Date -f 'HH:mm:ss')] Daemon started — PID $($proc.Id)"
