"""
Mealio backend — production WSGI app.

This is a thin Flask layer over the business logic in app.py. Every endpoint
reuses the existing `handle_*` functions unchanged — we only swap the dev-grade
`http.server` HTTP layer for a WSGI app that gunicorn can run behind a real host.

Local dev (single-threaded, no extra deps beyond stdlib):
    python app.py

Production (Render / any WSGI host):
    gunicorn server:app --workers 1 --threads 4 --timeout 120
"""

import hmac

from flask import Flask, request, jsonify

from app import (
    APP_API_KEY,
    RequestError,
    _is_rate_limited,
    handle_agent_chat,
    handle_bmr,
    handle_deals,
    handle_gap_fillers,
    handle_health,
    handle_meal_plan,
    handle_products,
    handle_recipe,
    handle_shopping_advice,
)

app = Flask(__name__)

# Reject oversized request bodies early (DoS / memory-exhaustion protection).
# Our largest legitimate payload (meal-plan request) is a few KB.
app.config["MAX_CONTENT_LENGTH"] = 256 * 1024  # 256 KB


# ---------------------------------------------------------------------------
# CORS + rate limiting + auth (mirrors the stdlib Handler in app.py)
# ---------------------------------------------------------------------------

def _client_ip() -> str:
    # Render/most PaaS put the real client IP first in X-Forwarded-For.
    fwd = request.headers.get("X-Forwarded-For", "")
    if fwd:
        return fwd.split(",")[0].strip()
    return request.remote_addr or "unknown"


@app.before_request
def _gate():
    # Let CORS preflight through without auth.
    if request.method == "OPTIONS":
        return ("", 204)

    if _is_rate_limited(_client_ip()):
        return jsonify({"error": "Too many requests"}), 429

    # Auth is enforced only when APP_API_KEY is configured on the server.
    # Constant-time compare avoids leaking the key via timing.
    if APP_API_KEY:
        provided = request.headers.get("X-API-Key", "")
        if not hmac.compare_digest(provided, APP_API_KEY):
            return jsonify({"error": "Unauthorized"}), 401


@app.after_request
def _cors(resp):
    resp.headers["Access-Control-Allow-Origin"] = "*"
    resp.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    resp.headers["Access-Control-Allow-Headers"] = "Content-Type, X-API-Key"
    # Security headers
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["X-Frame-Options"] = "DENY"
    resp.headers["Referrer-Policy"] = "no-referrer"
    resp.headers["Cache-Control"] = "no-store"
    return resp


@app.errorhandler(413)
def _too_large(_):
    return jsonify({"error": "Request body too large"}), 413


def _query_params() -> dict:
    """Reproduce parse_qs() shape ({key: [values]}) the handlers expect."""
    return {k: request.args.getlist(k) for k in request.args.keys()}


def _body() -> dict:
    return request.get_json(force=True, silent=True) or {}


# ---------------------------------------------------------------------------
# Routes — each delegates to the shared handler in app.py
# ---------------------------------------------------------------------------

@app.get("/api/health")
def health():
    return jsonify(handle_health())


@app.get("/api/products")
def products():
    return jsonify(handle_products(_query_params()))


@app.get("/api/deals")
def deals():
    return jsonify(handle_deals(_query_params()))


@app.post("/api/bmr")
def bmr():
    return jsonify(handle_bmr(_body()))


@app.post("/api/meal-plan")
def meal_plan():
    return jsonify(handle_meal_plan(_body()))


@app.post("/api/gap-fillers")
def gap_fillers():
    return jsonify(handle_gap_fillers(_body()))


@app.post("/api/shopping-advice")
def shopping_advice():
    return jsonify(handle_shopping_advice(_body()))


@app.post("/api/agent-chat")
def agent_chat():
    return jsonify(handle_agent_chat(_body()))


@app.post("/api/recipe")
def recipe():
    return jsonify(handle_recipe(_body()))


# ---------------------------------------------------------------------------
# Error handling — RequestError carries a user-safe message + status.
# Anything else becomes a generic 500 (details stay in server logs).
# ---------------------------------------------------------------------------

@app.errorhandler(RequestError)
def _request_error(err: RequestError):
    return jsonify({"error": err.message}), err.status


@app.errorhandler(404)
def _not_found(_):
    return jsonify({"error": "not found"}), 404


@app.errorhandler(Exception)
def _unhandled(err: Exception):
    app.logger.exception("Unhandled error: %s", err)
    return jsonify({"error": "Internal server error"}), 500


if __name__ == "__main__":
    # Dev convenience only. Production uses gunicorn (see Procfile / Dockerfile).
    import os
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 5000)))
