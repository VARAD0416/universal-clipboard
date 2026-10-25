import asyncio
import threading
import pyperclip
from flask import Flask, request, jsonify
import websockets

app = Flask(__name__)
connected_clients = set()
latest_clipboard = pyperclip.paste()

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok"}), 200

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
        print(f"[INFO] Pushed from iPhone to PC: {incoming_text}")
        return jsonify({"status": "success"}), 200
        
    return jsonify({"status": "error", "message": "Empty payload"}), 400

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
        connected_clients.remove(websocket)
        print("[INFO] WebSocket client disconnected.")

async def monitor_clipboard():
    global latest_clipboard
    while True:
        current_text = pyperclip.paste()
        if current_text != latest_clipboard:
            latest_clipboard = current_text
            print(f"[INFO] Windows clipboard changed: {current_text}")
            if connected_clients:
                await asyncio.gather(*[client.send(current_text) for client in connected_clients])
        await asyncio.sleep(1)

async def main():
    flask_thread = threading.Thread(target=run_flask, daemon=True)
    flask_thread.start()
    print("[INFO] HTTP API running on http://0.0.0.0:8765/clipboard")

    async with websockets.serve(websocket_handler, "0.0.0.0", 8766):
        print("[INFO] WebSocket server running on ws://0.0.0.0:8766")
        await monitor_clipboard()

if __name__ == "__main__":
    asyncio.run(main())