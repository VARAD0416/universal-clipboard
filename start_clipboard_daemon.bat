@echo off
:: ============================================================
:: start_clipboard_daemon.bat
:: Double-click this file to launch the clipboard daemon.
:: ============================================================
cd /d "%~dp0"
echo Starting Universal Clipboard Daemon...
python clipboard_daemon.py --port 8765 --interval 0.5
pause
