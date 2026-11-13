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

# GROQ_API_KEY and APP_API_KEY are provided at runtime by the host's secret store.
EXPOSE 5000
CMD ["sh", "-c", "gunicorn server:app --workers 1 --threads 4 --timeout 120 --bind 0.0.0.0:${PORT:-5000}"]
