from flask import Response  # add this
import requests             # add this

SPEECHIFY_TTS_URL = os.getenv('SPEECHIFY_TTS_URL', 'http://tts-service:3000/tts')  # or http://localhost:3000/tts

@app.route('/speak', methods=['POST'])
def speak():
    """Proxy to Speechify TTS Node service"""
    try:
        data = request.get_json()
        text = (data or {}).get('text', '').strip()
        voice_id = (data or {}).get('voiceId', 'cliff')

        if not text:
            return jsonify({"error": "No text provided"}), 400

        resp = requests.post(
            SPEECHIFY_TTS_URL,
            json={"text": text, "voiceId": voice_id, "format": "mp3"},
            timeout=30,
        )
        if resp.status_code != 200:
            return jsonify({"error": f"TTS failed: {resp.text}"}), 502

        return Response(resp.content, mimetype=resp.headers.get('Content-Type', 'audio/mpeg'))
    except Exception as e:
        logger.error(f"TTS proxy error: {e}")
        return jsonify({"error": str(e)}), 500
