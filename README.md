# Universal Clipboard

Cross-device clipboard sync between **Windows 11 PC** and **iPhone 13** over the local Wi-Fi network.

## Project Structure

```
universal-clipboard/
├── clipboard_daemon.py          # Python HTTP daemon (port 8765)
├── install.ps1                  # One-shot Windows setup script (run as Admin)
├── manage.ps1                   # Start / stop / restart / status / logs / test
├── requirements.txt             # Python dependencies (pywin32 optional)
├── scripts/
│   └── clipboard_daemon_launcher.ps1   # Silent pythonw.exe launcher
├── ios-shortcuts/
│   └── shortcuts_reference.txt         # Step-by-step iOS Shortcuts action guide
└── docs/
    └── enhancements_guide.md           # Full modernization guide
```

## Quick Start

### Windows

1. **Copy** this folder to `C:\Scripts\` (or keep it anywhere and update paths)
2. **Run as Administrator:**
   ```powershell
   .\install.ps1
   ```
3. **Verify:**
   ```powershell
   .\manage.ps1 status
   .\manage.ps1 test
   ```

### iPhone

Follow the step-by-step guide in [`ios-shortcuts/shortcuts_reference.txt`](ios-shortcuts/shortcuts_reference.txt)

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Daemon health check |
| GET | `/clipboard` | Returns `{"text": "..."}` |
| POST | `/clipboard` | Body `{"text": "..."}` sets clipboard |

## Authentication

Set the `CLIPBOARD_TOKEN` environment variable on Windows before starting the daemon:
```powershell
$env:CLIPBOARD_TOKEN = "your-secret-token"
```
Then set the same token in the iOS Shortcut `X-Clipboard-Token` header.

Leave the variable unset to disable auth (fine for home networks).

## Management Commands

```powershell
.\manage.ps1 status    # Check daemon + port + task scheduler
.\manage.ps1 start     # Start via Task Scheduler
.\manage.ps1 stop      # Kill daemon process
.\manage.ps1 restart   # Stop + start
.\manage.ps1 logs      # Tail last 40 log lines
.\manage.ps1 test      # Hit /health via localhost and .local name
```

## Addressing

Your PC is reachable at:  `http://<COMPUTERNAME>.local:8765`

Find your computer name:
```powershell
$env:COMPUTERNAME
```

## Back Tap (iPhone)

- **Double Tap** back of phone → Push iPhone clipboard → PC
- **Triple Tap** back of phone → Pull PC clipboard → iPhone

Configure at: **Settings → Accessibility → Touch → Back Tap**
