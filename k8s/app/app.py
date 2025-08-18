from flask import Flask, request, jsonify, render_template_string, Response
import redis
import json
import hashlib
import time
from transformers import pipeline
import os
import logging
import requests  # NEW: for proxying to the Node TTS service

app = Flask(__name__)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Redis connection
redis_host = os.getenv('REDIS_HOST', 'redis-service')
redis_port = int(os.getenv('REDIS_PORT', 6379))
r = redis.Redis(host=redis_host, port=redis_port, decode_responses=True)

# External Speechify TTS service (Node) URL
# In Kubernetes, point to your service (e.g., http://tts-service:3000/tts).
# Locally, export SPEECHIFY_TTS_URL=http://localhost:3000/tts
SPEECHIFY_TTS_URL = os.getenv('SPEECHIFY_TTS_URL', 'http://tts-service:3000/tts')

# Load sentiment analysis model (cached for performance)
try:
    sentiment_pipeline = pipeline("sentiment-analysis",
                                  model="distilbert-base-uncased-finetuned-sst-2-english")
    logger.info("Model loaded successfully")
except Exception as e:
    logger.error(f"Failed to load model: {e}")
    sentiment_pipeline = None

# Chat interface HTML template
CHAT_HTML = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Sentiment Analysis Chat</title>
    <style>
        .speak-button {
            display: inline-block; margin-top: 8px; padding: 6px 10px;
            background: #e9ecef; border: none; border-radius: 12px; cursor: pointer;
            font-size: 0.9em;
        }
        .speak-button:hover { background: #dde2e6; }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f0f2f5; }
        .container { max-width: 800px; margin: 0 auto; height: 100vh; display: flex; flex-direction: column; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; text-align: center; }
        .header h1 { margin-bottom: 10px; }
        .stats { display: flex; justify-content: space-around; margin-top: 10px; }
        .stat { text-align: center; }
        .stat-value { font-size: 1.2em; font-weight: bold; }
        .chat-container { flex: 1; display: flex; flex-direction: column; background: white; margin: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .messages { flex: 1; padding: 20px; overflow-y: auto; }
        .message { margin-bottom: 15px; padding: 12px 16px; border-radius: 18px; max-width: 70%; }
        .user-message { background: #007bff; color: white; margin-left: auto; }
        .bot-message { background: #f1f3f5; color: #333; }
        .sentiment { display: inline-block; padding: 4px 8px; border-radius: 12px; font-size: 0.8em; margin-left: 10px; }
        .positive { background: #d4edda; color: #155724; }
        .negative { background: #f8d7da; color: #721c24; }
        .cache-hit { color: #28a745; font-size: 0.7em; }
        .processing-time { color: #6c757d; font-size: 0.7em; }
        .input-container { padding: 20px; border-top: 1px solid #eee; }
        .input-group { display: flex; gap: 10px; }
        .message-input { flex: 1; padding: 12px; border: 1px solid #ddd; border-radius: 25px; outline: none; }
        .send-button { padding: 12px 24px; background: #007bff; color: white; border: none; border-radius: 25px; cursor: pointer; }
        .send-button:hover { background: #0056b3; }
        .send-button:disabled { background: #ccc; cursor: not-allowed; }
        .loading { display: none; color: #666; font-style: italic; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🤖 AI Sentiment Analysis Demo</h1>
            <p>Kubernetes + Redis + ML Pipeline</p>
            <div class="stats">
                <div class="stat">
                    <div class="stat-value" id="total-requests">0</div>
                    <div>Total Requests</div>
                </div>
                <div class="stat">
                    <div class="stat-value" id="cache-hits">0</div>
                    <div>Cache Hits</div>
                </div>
                <div class="stat">
                    <div class="stat-value" id="avg-response">0ms</div>
                    <div>Avg Response</div>
                </div>
            </div>
        </div>
        
        <div class="chat-container">
            <div class="messages" id="messages">
                <div class="message bot-message" data-speech="Welcome! I'm an AI sentiment analyzer running on Kubernetes with Redis caching. Try sending me some text to analyze!">
                    👋 Welcome! I'm an AI sentiment analyzer running on Kubernetes with Redis caching. 
                    Try sending me some text to analyze! 
                    <br><br>
                    <strong>Demo features:</strong><br>
                    • Real-time sentiment analysis<br>
                    • Redis caching for performance<br>
                    • Auto-scaling based on load<br>
                    • Production monitoring
                    <div><button class="speak-button">🔊 Speak</button></div>
                </div>
            </div>
            
            <div class="input-container">
                <div class="input-group">
                    <input type="text" class="message-input" id="messageInput" 
                           placeholder="Type your message here..." maxlength="500">
                    <button class="send-button" id="sendButton">Send</button>
                </div>
                <div class="loading" id="loading">🤖 Analyzing sentiment...</div>
            </div>
        </div>
    </div>

    <script>
        let stats = { total: 0, cacheHits: 0, totalTime: 0 };
        
        const messagesContainer = document.getElementById('messages');
        const messageInput = document.getElementById('messageInput');
        const sendButton = document.getElementById('sendButton');
        const loading = document.getElementById('loading');

        function updateStats() {
            document.getElementById('total-requests').textContent = stats.total;
            document.getElementById('cache-hits').textContent = stats.cacheHits;
            const avgTime = stats.total > 0 ? Math.round(stats.totalTime / stats.total) : 0;
            document.getElementById('avg-response').textContent = avgTime + 'ms';
        }

        // Enhanced addMessage: stores speakable text in data-speech and shows a Speak button for bot messages
        function addMessage(text, isUser = false, sentiment = null, cached = false, processingTime = 0, speechText = null) {
            const messageDiv = document.createElement('div');
            messageDiv.className = `message ${isUser ? 'user-message' : 'bot-message'}`;

            const speakable = (speechText ?? text).trim();
            messageDiv.dataset.speech = speakable;

            let content = text;
            if (sentiment) {
                const sentimentClass = sentiment.label === 'POSITIVE' ? 'positive' : 'negative';
                const confidence = Math.round(sentiment.score * 100);
                content += `<span class="sentiment ${sentimentClass}">
                    ${sentiment.label} (${confidence}%)
                </span>`;
                
                if (cached) {
                    content += `<br><span class="cache-hit">⚡ Cache hit!</span>`;
                } else {
                    content += `<br><span class="processing-time">⏱️ ${Math.round(processingTime * 1000)}ms</span>`;
                }
            }

            if (!isUser) {
                content += `<div><button class="speak-button">🔊 Speak</button></div>`;
            }
            
            messageDiv.innerHTML = content;
            messagesContainer.appendChild(messageDiv);
            messagesContainer.scrollTop = messagesContainer.scrollHeight;
        }

        async function sendMessage() {
            const text = messageInput.value.trim();
            if (!text) return;

            // Add user message
            addMessage(text, true);
            messageInput.value = '';
            
            // Show loading
            sendButton.disabled = true;
            loading.style.display = 'block';

            try {
                const response = await fetch('/predict', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ text: text })
                });

                const result = await response.json();
                
                if (result.prediction) {
                    // Update stats
                    stats.total++;
                    if (result.cached) stats.cacheHits++;
                    stats.totalTime += result.processing_time * 1000;
                    updateStats();

                    // Add bot response
                    const emoji = result.prediction.label === 'POSITIVE' ? '😊' : '😔';
                    const botLine = `${emoji} I detected ${result.prediction.label.toLowerCase()} sentiment!`;
                    addMessage(
                        botLine,
                        false,
                        result.prediction,
                        result.cached,
                        result.processing_time,
                        botLine // speak exactly what we show
                    );
                } else {
                    addMessage('❌ Sorry, I couldn\\'t analyze that text. Please try again.', false, null, false, 0, 'Sorry, I could not analyze that text. Please try again.');
                }
            } catch (error) {
                console.error('Error:', error);
                addMessage('❌ Connection error. Please check if the service is running.', false, null, false, 0, 'Connection error. Please check if the service is running.');
            } finally {
                sendButton.disabled = false;
                loading.style.display = 'none';
            }
        }

        // Event listeners
        sendButton.addEventListener('click', sendMessage);
        messageInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') sendMessage();
        });

        // Speak button handler (event delegation)
        messagesContainer.addEventListener('click', async (e) => {
            const btn = e.target.closest('.speak-button');
            if (!btn) return;

            const msgDiv = btn.closest('.message');
            const text = (msgDiv?.dataset?.speech || '').trim();
            if (!text) return;

            btn.disabled = true;
            const oldLabel = btn.textContent;
            btn.textContent = '🔊 ...';

            try {
                const resp = await fetch('/speak', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ text })
                });
                if (!resp.ok) throw new Error('TTS failed');

                const buf = await resp.arrayBuffer();
                const blob = new Blob([buf], { type: 'audio/mpeg' });
                const url = URL.createObjectURL(blob);

                const audio = new Audio(url);
                await audio.play();
                // Optionally revoke after playback:
                // audio.onended = () => URL.revokeObjectURL(url);
            } catch (err) {
                console.error(err);
                alert('❌ Text-to-speech failed.');
            } finally {
                btn.disabled = false;
                btn.textContent = oldLabel;
            }
        });

        // Focus input on load
        messageInput.focus();

        // Load initial metrics (optional)
        fetch('/metrics')
            .then(r => r.json())
            .then(data => {
                // Could populate initial cache stats here
            })
            .catch(e => console.log('Metrics not available'));
    </script>
</body>
</html>
'''

@app.route('/')
def chat_interface():
    """Serve the chat interface"""
    return render_template_string(CHAT_HTML)

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint for Kubernetes"""
    return jsonify({"status": "healthy", "timestamp": time.time()})

@app.route('/predict', methods=['POST'])
def predict():
    """Predict sentiment with Redis caching"""
    try:
        data = request.get_json()
        text = (data or {}).get('text', '')
        
        if not text:
            return jsonify({"error": "No text provided"}), 400
        
        # Create cache key
        cache_key = f"prediction:{hashlib.md5(text.encode()).hexdigest()}"
        
        # Check cache first
        cached_result = r.get(cache_key)
        if cached_result:
            logger.info(f"Cache hit for key: {cache_key}")
            return jsonify({
                "text": text,
                "prediction": json.loads(cached_result),
                "cached": True,
                "processing_time": 0
            })
        
        # Make prediction
        start_time = time.time()
        if sentiment_pipeline:
            result = sentiment_pipeline(text)[0]
            processing_time = time.time() - start_time
            
            # Cache result for 1 hour
            r.setex(cache_key, 3600, json.dumps(result))
            
            logger.info(f"New prediction cached with key: {cache_key}")
            return jsonify({
                "text": text,
                "prediction": result,
                "cached": False,
                "processing_time": processing_time
            })
        else:
            return jsonify({"error": "Model not available"}), 503
            
    except Exception as e:
        logger.error(f"Prediction error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/speak', methods=['POST'])
def speak():
    """Proxy to Speechify TTS Node service"""
    try:
        data = request.get_json() or {}
        text = (data.get('text') or '').strip()
        voice_id = (data.get('voiceId') or 'cliff').strip()

        if not text:
            return jsonify({"error": "No text provided"}), 400

        # Call the Node TTS service
        resp = requests.post(
            SPEECHIFY_TTS_URL,
            json={"text": text, "voiceId": voice_id, "format": "mp3"},
            timeout=30
        )
        if resp.status_code != 200:
            logger.error(f"TTS service error: {resp.status_code} {resp.text}")
            return jsonify({"error": "TTS failed"}), 502

        # Stream MP3 bytes back to the browser
        return Response(resp.content, mimetype=resp.headers.get('Content-Type', 'audio/mpeg'))
    except Exception as e:
        logger.error(f"TTS proxy error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/metrics', methods=['GET'])
def metrics():
    """Basic metrics endpoint"""
    try:
        cache_info = r.info()
        hits = cache_info.get('keyspace_hits', 0)
        misses = cache_info.get('keyspace_misses', 0)
        denom = max(hits + misses, 1)
        return jsonify({
            "redis_connected_clients": cache_info.get('connected_clients', 0),
            "redis_used_memory": cache_info.get('used_memory_human', '0B'),
            "redis_keyspace_hits": hits,
            "redis_keyspace_misses": misses,
            "cache_hit_rate": hits / denom
        })
    except Exception as e:
        return jsonify({"error": f"Metrics unavailable: {e}"}), 503

if __name__ == '__main__':
    # For local dev; in production use a real WSGI server (gunicorn/uwsgi)
    app.run(host='0.0.0.0', port=5000)
