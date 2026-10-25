import asyncio
import io
import os
import subprocess
import threading
from datetime import datetime
from pathlib import Path

import pyperclip
from flask import Flask, request, jsonify
import websockets

# ---------------------------------------------------------------------------
# Optional heavy imports — gracefully degrade if not installed
# ---------------------------------------------------------------------------
try:
    from PIL import Image
    PILLOW_AVAILABLE = True
except ImportError:
    PILLOW_AVAILABLE = False
    print("[WARN] Pillow not installed — image clipboard support disabled. "
          "Run: pip install Pillow")

try:
    import win32clipboard
    import win32con
    WIN32_AVAILABLE = True
except ImportError:
    WIN32_AVAILABLE = False
    print("[WARN] pywin32 not installed — image clipboard support disabled. "
          "Run: pip install pywin32")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
MEDIA_SAVE_DIR = Path(os.environ.get("CLIPBOARD_MEDIA_DIR",
                                     Path.home() / "ClipboardMedia"))
MEDIA_SAVE_DIR.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# Flask app
# ---------------------------------------------------------------------------
app = Flask(__name__)
connected_clients = set()
latest_clipboard = pyperclip.paste()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _put_image_on_clipboard(pil_image) -> bool:
    """Copy a PIL Image to the Windows clipboard as DIB."""
    if not (PILLOW_AVAILABLE and WIN32_AVAILABLE):
        return False
    try:
        rgb = pil_image.convert("RGB")
        buf = io.BytesIO()
        rgb.save(buf, format="BMP")
        bmp_data = buf.getvalue()[14:]   # strip 14-byte BITMAPFILEHEADER
        win32clipboard.OpenClipboard()
        win32clipboard.EmptyClipboard()
        win32clipboard.SetClipboardData(win32con.CF_DIB, bmp_data)
        win32clipboard.CloseClipboard()
        return True
    except Exception as exc:
        print(f"[ERROR] clipboard write failed: {exc}")
        try:
            win32clipboard.CloseClipboard()
        except Exception:
            pass
        return False


def _save_media(data: bytes, filename: str) -> Path:
    """Save bytes to MEDIA_SAVE_DIR with a timestamp prefix."""
    ts   = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem, ext = os.path.splitext(filename)
    dest = MEDIA_SAVE_DIR / f"{ts}_{stem}{ext}"
    dest.write_bytes(data)
    return dest


def _reveal_in_explorer(path: Path):
    """Select the file in Windows Explorer (non-blocking)."""
    try:
        subprocess.Popen(["explorer", "/select,", str(path)])
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        "status": "ok",
        "image_clipboard": PILLOW_AVAILABLE and WIN32_AVAILABLE,
        "media_dir": str(MEDIA_SAVE_DIR),
    }), 200

@app.route('/clipboard', methods=['GET'])
def get_clipboard():
    return jsonify({"text": pyperclip.paste()}), 200

@app.route('/clipboard', methods=['POST'])
def post_clipboard():
    global latest_clipboard
    # Accept JSON payload from Apple Shortcuts
    data = request.get_json(silent=True)
    incoming_text = ""
    
    if data and 'text' in data:
        incoming_text = data['text']
    else:
        # Fallback to plain text / form data if sent raw
        incoming_text = request.data.decode('utf-8')

    if incoming_text:
        pyperclip.copy(incoming_text)
        latest_clipboard = incoming_text
        print(f"[INFO] Text pushed from iPhone: {incoming_text[:120]}")
        return jsonify({"status": "success"}), 200

    return jsonify({"status": "error", "message": "Empty payload"}), 400


@app.route('/upload', methods=['POST'])
def upload_media():
    """
    Accept a multipart/form-data file upload from iPhone.

    Form field:
      file  — image or video (required)

    Behaviour:
      Images  → placed on Windows clipboard AND saved to MEDIA_SAVE_DIR
      Videos  → saved to MEDIA_SAVE_DIR and revealed in Explorer
    """
    if 'file' not in request.files:
        return jsonify({"status": "error", "message": "No 'file' field in request"}), 400

    f = request.files['file']
    if not f.filename:
        return jsonify({"status": "error", "message": "Empty filename"}), 400

    mime = (f.content_type or "").lower()
    raw  = f.read()
    saved_path = _save_media(raw, f.filename)
    print(f"[INFO] Received upload: {f.filename}  mime={mime}  size={len(raw):,} B")

    IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.heic', '.heif'}
    VIDEO_EXTS = {'.mp4', '.mov', '.avi', '.mkv', '.m4v'}
    ext = Path(f.filename).suffix.lower()

    # ── Image ──────────────────────────────────────────────────────────────
    if mime.startswith("image/") or ext in IMAGE_EXTS:
        if PILLOW_AVAILABLE and WIN32_AVAILABLE:
            try:
                img = Image.open(io.BytesIO(raw))
                ok  = _put_image_on_clipboard(img)
                action = "clipboard + saved" if ok else "saved only (clipboard write failed)"
                print(f"[INFO] Image action: {action}")
                return jsonify({"status": "success", "action": action,
                                "path": str(saved_path)}), 200
            except Exception as exc:
                return jsonify({"status": "partial",
                                "action": f"saved only (error: {exc})",
                                "path": str(saved_path)}), 200
        else:
            missing = [p for p, ok in [("Pillow", PILLOW_AVAILABLE),
                                        ("pywin32", WIN32_AVAILABLE)] if not ok]
            return jsonify({"status": "partial",
                            "action": "saved only (install: " + ", ".join(missing) + ")",
                            "path": str(saved_path)}), 200

    # ── Video ──────────────────────────────────────────────────────────────
    if mime.startswith("video/") or ext in VIDEO_EXTS:
        _reveal_in_explorer(saved_path)
        print(f"[INFO] Video saved + revealed in Explorer")
        return jsonify({"status": "success", "action": "saved + Explorer",
                        "path": str(saved_path)}), 200

    # ── Fallback ───────────────────────────────────────────────────────────
    return jsonify({"status": "success", "action": "saved",
                    "path": str(saved_path)}), 200

def run_flask():
    app.run(host='0.0.0.0', port=8765, debug=False, use_reloader=False)

async def websocket_handler(websocket):
    connected_clients.add(websocket)
    print("[INFO] iPhone WebSocket client connected!")
    try:
        async for message in websocket:
            pyperclip.copy(message)
            print(f"[INFO] Received via WebSocket: {message}")
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        connected_clients.discard(websocket)
        print("[INFO] WebSocket client disconnected.")

async def monitor_clipboard():
    global latest_clipboard
    while True:
        current_text = pyperclip.paste()
        if current_text != latest_clipboard:
            latest_clipboard = current_text
            print(f"[INFO] Windows clipboard changed: {current_text[:80]}")
            if connected_clients:
                dead = set()
                for client in list(connected_clients):
                    try:
                        await client.send(current_text)
                    except Exception:
                        dead.add(client)
                connected_clients -= dead
        await asyncio.sleep(1)

async def main():
    flask_thread = threading.Thread(target=run_flask, daemon=True)
    flask_thread.start()
    print("[INFO] HTTP text  → http://0.0.0.0:8765/clipboard")
    print("[INFO] HTTP upload→ http://0.0.0.0:8765/upload  (multipart POST)")
    print(f"[INFO] Media dir  → {MEDIA_SAVE_DIR}")

    async with websockets.serve(websocket_handler, "0.0.0.0", 8766):
        print("[INFO] WebSocket  → ws://0.0.0.0:8766")
        await monitor_clipboard()

if __name__ == "__main__":
    asyncio.run(main())