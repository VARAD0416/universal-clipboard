# Universal Clipboard — Modernization Guide
> Windows 11 PC ↔ iPhone 13 | `clipboard_daemon.py` on port **8765**

---

## Enhancement 1 — Hostname / mDNS Resolution (`.local` addressing)

### Background
Windows 11 ships with a built-in mDNS responder via the **DNS-SD** service (part of Bonjour for Windows, bundled with iTunes or standalone). Your PC will advertise itself as `<COMPUTERNAME>.local` on the LAN automatically.

### Step 1 — Verify the mDNS services are running

Run in PowerShell (as Administrator):

```powershell
# Check all three services that power mDNS/Bonjour on Windows 11
Get-Service -Name 'Bonjour Service', 'mDNS', 'Dnscache' |
    Select-Object Name, Status, StartType | Format-Table -AutoSize
```

Expected output:
```
Name             Status  StartType
----             ------  ---------
Bonjour Service  Running Automatic   # from Apple Bonjour / iTunes
mDNS             Running Manual      # Windows built-in (WS-Discovery)
Dnscache         Running Automatic   # DNS Client — mandatory
```

If **Bonjour Service** is missing, install the standalone package:

```powershell
# Download Apple Bonjour Print Services (contains mdnsresponder.exe)
winget install --id Apple.Bonjour -e --silent
```

### Step 2 — Enable mDNS in Windows DNS Client

```powershell
# Confirm mDNS is enabled in the registry (default on Win11)
Get-ItemProperty `
  -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' `
  -Name EnableMDNS -ErrorAction SilentlyContinue

# If the key is missing or 0, enable it:
Set-ItemProperty `
  -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' `
  -Name EnableMDNS -Value 1 -Type DWord
Restart-Service Dnscache
```

### Step 3 — Find your exact `.local` hostname

```powershell
# Your mDNS hostname is always <COMPUTERNAME>.local
$mdnsHost = "$env:COMPUTERNAME.local"
Write-Host "Your .local address: http://$mdnsHost`:8765"

# Verify the hostname resolves locally
Resolve-DnsName "$mdnsHost" -Type A -ErrorAction SilentlyContinue
```

### Step 4 — Verify from another device (cross-network test)

```powershell
# From Windows, ping your own .local name
ping "$env:COMPUTERNAME.local" -n 3

# Optionally install dns-sd CLI tool for deeper inspection
# (included with Bonjour SDK or iTunes install)
dns-sd -B _services._dns-sd._udp local.
dns-sd -Q "$env:COMPUTERNAME.local" A
```

From your **iPhone**, open Safari and browse to:
```
http://<COMPUTERNAME>.local:8765/clipboard
```
If you get a response, mDNS is working end-to-end.

### Step 5 — Windows Firewall rule for port 8765

```powershell
# Allow inbound TCP on 8765 (if not already open)
New-NetFirewallRule `
  -DisplayName "Universal Clipboard Daemon" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 8765 `
  -Action Allow `
  -Profile Private `
  -ErrorAction SilentlyContinue

# Verify
Get-NetFirewallRule -DisplayName "Universal Clipboard Daemon" |
    Get-NetFirewallPortFilter | Select-Object LocalPort, Protocol
```

### Troubleshooting mDNS

| Symptom | Fix |
|---|---|
| `.local` resolves on PC but not iPhone | Ensure both are on **same Wi-Fi SSID**; check router for "AP isolation" (disable it) |
| `Resolve-DnsName` returns nothing | Restart `Bonjour Service` + `Dnscache` |
| Works sometimes / flaky | Add a static ARP entry or DHCP reservation as fallback |
| Router blocks mDNS | Enable **mDNS Proxy / Avahi** on router, or switch to static IP |

---

## Enhancement 2 — Silent Background Daemon via Task Scheduler

### The Wrapper Script

Save this as `C:\Scripts\clipboard_daemon_launcher.ps1`:

```powershell
# clipboard_daemon_launcher.ps1
# Launches clipboard_daemon.py silently using pythonw.exe

$pythonw  = "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python312\pythonw.exe"
$script   = "C:\Scripts\clipboard_daemon.py"
$logFile  = "C:\Scripts\clipboard_daemon.log"
$pidFile  = "C:\Scripts\clipboard_daemon.pid"

# Kill any existing instance first
if (Test-Path $pidFile) {
    $oldPid = Get-Content $pidFile -ErrorAction SilentlyContinue
    if ($oldPid) {
        Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $pidFile -Force
}

# Start the daemon headlessly
$proc = Start-Process `
    -FilePath $pythonw `
    -ArgumentList $script `
    -RedirectStandardOutput $logFile `
    -RedirectStandardError  "$logFile.err" `
    -WindowStyle Hidden `
    -PassThru

# Save PID for later management
$proc.Id | Out-File $pidFile -Encoding ASCII
Write-Host "Daemon started with PID $($proc.Id)"
```

> [!IMPORTANT]
> Adjust `$pythonw` to match your Python installation path. Run `where.exe pythonw` to find it.

### Register with Task Scheduler (run at logon, any user)

```powershell
# Run as Administrator
$action  = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-WindowStyle Hidden -NonInteractive -File C:\Scripts\clipboard_daemon_launcher.ps1"

$trigger = New-ScheduledTaskTrigger -AtLogOn

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
    -TaskName   "UniversalClipboardDaemon" `
    -TaskPath   "\CustomTasks\" `
    -Action     $action `
    -Trigger    $trigger `
    -Settings   $settings `
    -Principal  $principal `
    -Force

# Confirm registration
Get-ScheduledTask -TaskName "UniversalClipboardDaemon"
```

### Day-to-Day Management Commands

```powershell
# ── STATUS ──────────────────────────────────────────────────────────────────

# Check if pythonw process is running
$daemon = Get-Process -Name "pythonw" -ErrorAction SilentlyContinue
if ($daemon) {
    Write-Host "✅ Daemon running — PID(s): $($daemon.Id -join ', ')"
} else {
    Write-Host "❌ Daemon NOT running"
}

# Check Task Scheduler last run result (0x0 = success)
Get-ScheduledTaskInfo -TaskName "UniversalClipboardDaemon" -TaskPath "\CustomTasks\" |
    Select-Object LastRunTime, LastTaskResult, NextRunTime

# Tail the log
Get-Content C:\Scripts\clipboard_daemon.log -Tail 30 -Wait


# ── STOP ────────────────────────────────────────────────────────────────────

$pidFile = "C:\Scripts\clipboard_daemon.pid"
if (Test-Path $pidFile) {
    $daemonPid = Get-Content $pidFile
    Stop-Process -Id $daemonPid -Force
    Remove-Item $pidFile -Force
    Write-Host "Daemon (PID $daemonPid) stopped."
} else {
    # Fallback: kill all pythonw instances
    Get-Process -Name "pythonw" | Stop-Process -Force
    Write-Host "All pythonw processes killed."
}


# ── RESTART ─────────────────────────────────────────────────────────────────

# Trigger the Task Scheduler task immediately (cleanest restart)
Start-ScheduledTask -TaskName "UniversalClipboardDaemon" -TaskPath "\CustomTasks\"

# Or run the launcher directly
& "C:\Scripts\clipboard_daemon_launcher.ps1"


# ── UNREGISTER (cleanup) ─────────────────────────────────────────────────────
Unregister-ScheduledTask -TaskName "UniversalClipboardDaemon" -TaskPath "\CustomTasks\" -Confirm:$false
```

### Verify port is listening

```powershell
# Confirm daemon is bound to port 8765
netstat -ano | Select-String ":8765"

# Or with Get-NetTCPConnection
Get-NetTCPConnection -LocalPort 8765 -State Listen |
    Select-Object LocalAddress, LocalPort, OwningProcess |
    ForEach-Object {
        $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            Address = $_.LocalAddress
            Port    = $_.LocalPort
            PID     = $_.OwningProcess
            Process = $proc.Name
        }
    }
```

---

## Enhancement 3 — iOS Shortcuts Configuration

### Prerequisites
- iPhone 13, iOS 16+
- Shortcuts app installed (built-in)
- Both PC and iPhone on the **same Wi-Fi network**
- Replace `YOUR_PC_NAME` with your actual computer name throughout
- Replace `YOUR_TOKEN` with your actual `X-Clipboard-Token` value (omit the header line if no auth is configured)

---

### Shortcut A: "Pull from Windows"

**Purpose:** Fetches `GET /clipboard` from the daemon and copies text to your iPhone clipboard.

#### Step-by-step action sequence:

1. Open **Shortcuts** → tap **+** (top right)
2. Tap the title field → type **`Pull from Windows`**
3. Tap **Add Action** → search **`URL`** → select **URL**
   - Value: `http://YOUR_PC_NAME.local:8765/clipboard`
4. Tap **+** → search **`Get Contents of URL`** → select it
   - Method: **GET**
   - Tap **Headers** → **Add new header**
     - Key: `X-Clipboard-Token`  |  Value: `YOUR_TOKEN`  *(skip if no auth)*
5. Tap **+** → search **`Get Dictionary Value`** → select it
   - Get: **Value**
   - Key: `text`
   - From: **Contents of URL** (variable from step 4)
6. Tap **+** → search **`Copy to Clipboard`** → select it
   - Content: **Dictionary Value** (variable from step 5)
7. Tap **+** → search **`Show Notification`** → select it
   - Title: `Clipboard Synced ✅`
   - Body: **Dictionary Value**
8. Tap **Done** (top right)

> [!NOTE]
> If your daemon returns plain text instead of JSON, skip steps 5–6 and use **Contents of URL** directly in the **Copy to Clipboard** action.

---

### Shortcut B: "Push to Windows"

**Purpose:** Reads your iPhone clipboard and POSTs it to the daemon.

#### Step-by-step action sequence:

1. Open **Shortcuts** → tap **+**
2. Tap the title → type **`Push to Windows`**
3. Tap **Add Action** → search **`Clipboard`** → select **Get Clipboard**
4. Tap **+** → search **`Dictionary`** → select **Dictionary**
   - Tap **Add new item**
     - Key: `text`  |  Value: tap the variable field → choose **Clipboard** (from step 3)
5. Tap **+** → search **`URL`** → select **URL**
   - Value: `http://YOUR_PC_NAME.local:8765/clipboard`
6. Tap **+** → search **`Get Contents of URL`** → select it
   - Method: **POST**
   - Request Body: **JSON**
   - JSON Body: **Dictionary** (variable from step 4)
   - Tap **Headers** → **Add new header**
     - Key: `Content-Type`  |  Value: `application/json`
   - *(Optional auth header)*
     - Key: `X-Clipboard-Token`  |  Value: `YOUR_TOKEN`
7. Tap **+** → search **`Show Notification`** → select it
   - Title: `Pushed to Windows ✅`
8. Tap **Done**

#### Enable "Show in Share Sheet"

1. With the shortcut open, tap **⋯** (three dots, top right) → **Shortcut Details**
2. Toggle **Show in Share Sheet** → **ON**
3. Under **Share Sheet Types**, ensure **Text** and **URLs** are checked
4. Tap **Done**

Now from Safari, Mail, Notes, etc. → tap **Share** → scroll down → **Push to Windows**

---

### Handling the Local Network Access Permission Prompt

The **first time** either shortcut runs, iOS will show:

> *"Shortcuts" Would Like to Find and Connect to Devices on Your Local Network*

**Action required:**
- Tap **Allow** — this is a one-time permission per shortcut

**If you tapped "Don't Allow" by mistake:**

1. Go to **Settings** → **Privacy & Security** → **Local Network**
2. Find **Shortcuts** in the list
3. Toggle it **ON**

**If the shortcut still times out / can't reach the PC:**

| Check | Fix |
|---|---|
| PC firewall blocking 8765 | Run the firewall rule from Enhancement 1 |
| iPhone on different SSID (e.g., 5 GHz vs 2.4 GHz) | Connect both to same band/SSID |
| mDNS not resolving | Use static IP fallback in the URL action |
| Router AP isolation | Disable "Client Isolation" / "AP Isolation" in router settings |

#### Fallback: Dual-URL with IP address

If `.local` is unreliable, add an **If** block at the top of the shortcut:

1. **Add Action** → **Choose from Menu** (or **If**)
   - Option 1: `Use .local` → URL = `http://YOUR_PC_NAME.local:8765/clipboard`
   - Option 2: `Use IP` → URL = `http://192.168.x.x:8765/clipboard`

---

## Enhancement 4 — Hands-Free Hardware Triggers (Back Tap)

### Map shortcuts to Back Tap gestures

1. Open **Settings** → **Accessibility** → **Touch** → **Back Tap**
2. Tap **Double Tap**
   - Scroll down to **Shortcuts** section
   - Select **Push to Windows**
3. Tap **Triple Tap**
   - Scroll down to **Shortcuts** section
   - Select **Pull from Windows**

### Back Tap Tips & Requirements

| Requirement | Detail |
|---|---|
| iPhone model | iPhone 8 or later (iPhone 13 ✅) |
| Case | Works with most cases; thick/rubbery cases may reduce sensitivity |
| Tap location | Tap the **Apple logo** area on the back |
| Sensitivity | If triggers are unreliable → Settings → Accessibility → Touch → Back Tap → adjust tap timing |
| Conflict with camera | If double-tap conflicts, remap camera to triple-tap and push to a different gesture |

### Testing Back Tap

1. Lock your phone → wake it
2. Double-tap the back → watch for the notification banner: **"Pushed to Windows ✅"**
3. Triple-tap the back → watch for: **"Clipboard Synced ✅"**

---

## Complete Setup Checklist

```
WINDOWS SIDE
 [ ] pythonw.exe path identified (run: where.exe pythonw)
 [ ] C:\Scripts\ directory created
 [ ] clipboard_daemon.py moved/copied to C:\Scripts\
 [ ] clipboard_daemon_launcher.ps1 created and tested manually
 [ ] Task Scheduler task registered (UniversalClipboardDaemon)
 [ ] Task tested: Start-ScheduledTask ... confirms daemon starts
 [ ] Port 8765 confirmed open: netstat -ano | sls ":8765"
 [ ] Firewall rule added for port 8765
 [ ] Bonjour Service running (Get-Service 'Bonjour Service')
 [ ] .local name resolves: ping $env:COMPUTERNAME.local

iOS SIDE
 [ ] Both devices on the same Wi-Fi network / SSID
 [ ] "Pull from Windows" shortcut created and tested
 [ ] "Push to Windows" shortcut created and tested
 [ ] Local Network Access permission granted to Shortcuts
 [ ] "Push to Windows" enabled in Share Sheet
 [ ] Back Tap → Double Tap → Push to Windows configured
 [ ] Back Tap → Triple Tap → Pull from Windows configured
 [ ] End-to-end test: type on PC → triple-tap iPhone → paste confirms sync
 [ ] End-to-end test: copy on iPhone → double-tap → paste on PC confirms sync
```

---

## Quick Reference Card

| Action | Method |
|---|---|
| Push iPhone → PC | Double-tap iPhone back |
| Pull PC → iPhone | Triple-tap iPhone back |
| Push from any app | Share Sheet → Push to Windows |
| Daemon status | `Get-Process pythonw` |
| Daemon log | `Get-Content C:\Scripts\clipboard_daemon.log -Tail 30` |
| Restart daemon | `Start-ScheduledTask -TaskName "UniversalClipboardDaemon" -TaskPath "\CustomTasks\"` |
| PC .local address | `http://$env:COMPUTERNAME.local:8765` |
| Manual GET test | `curl http://PCNAME.local:8765/clipboard` |
| Manual POST test | `curl -X POST http://PCNAME.local:8765/clipboard -H "Content-Type: application/json" -d '{"text":"hello"}'` |
