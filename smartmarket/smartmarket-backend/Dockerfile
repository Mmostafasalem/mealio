# Host-agnostic image for the Nourlo backend (works on Render, Fly, Cloud Run, any VPS).
FROM python:3.11-slim

# MEALIO_ENV=production makes server.py fail closed on incomplete config
# (e.g. missing APP_API_KEY) instead of silently running without auth.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    MEALIO_ENV=production

WORKDIR /app

COPY requirements.lock .
RUN pip install --no-cache-dir -r requirements.lock

COPY . .

# Run as an unprivileged user: the app only reads its own code. Tests and local
# files are kept out of the image by .dockerignore. If you mount a volume for
# AI_STATE_DB, make it writable by uid 10001.
RUN useradd --system --uid 10001 --no-create-home nourlo
USER 10001

# GROQ_API_KEY, APP_API_KEY and TRUSTED_PROXY_COUNT are provided at runtime by
# the host (secrets from its secret store). Production refuses to start without
# APP_API_KEY, AI_ACCOUNTS_ENABLED and TRUSTED_PROXY_COUNT; see DEPLOY.md.
EXPOSE 5000
CMD ["sh", "-c", "gunicorn server:app --workers 1 --threads 4 --timeout 120 --bind 0.0.0.0:${PORT:-5000}"]
