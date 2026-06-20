# Host-agnostic image for the Mealio backend (works on Render, Fly, Cloud Run, any VPS).
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# GROQ_API_KEY and APP_API_KEY are provided at runtime by the host's secret store.
EXPOSE 5000
CMD ["sh", "-c", "gunicorn server:app --workers 1 --threads 4 --timeout 120 --bind 0.0.0.0:${PORT:-5000}"]
