import os
import logging
from flask import Flask, jsonify
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import time

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

app = Flask(__name__)

REQUEST_COUNT = Counter("http_requests_total", "Total HTTP requests", ["method", "endpoint", "status"])
REQUEST_LATENCY = Histogram("http_request_duration_seconds", "HTTP request latency", ["endpoint"])


@app.before_request
def start_timer():
    from flask import g, request
    g.start = time.time()


@app.after_request
def record_metrics(response):
    from flask import g, request
    latency = time.time() - g.start
    REQUEST_COUNT.labels(method=request.method, endpoint=request.path, status=response.status_code).inc()
    REQUEST_LATENCY.labels(endpoint=request.path).observe(latency)
    return response


@app.route("/")
def hello():
    logger.info("GET /")
    return jsonify({
        "message": "Hello from Flask on EKS!",
        "version": os.getenv("APP_VERSION", "1.0.0"),
        "environment": os.getenv("APP_ENV", "production"),
    })


@app.route("/health/live")
def liveness():
    return jsonify({"status": "alive"}), 200


@app.route("/health/ready")
def readiness():
    return jsonify({"status": "ready"}), 200


@app.route("/metrics")
def metrics():
    from flask import Response
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
