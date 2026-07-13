# Workday protocol adapter (middleware) — built/pushed by azd to ACR and run as
# an external-ingress Azure Container App.
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PORT=8000

WORKDIR /app

# Install dependencies first for better layer caching.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Application code.
COPY app ./app

# Run as a non-root user (uid 1001, root group — Container Apps friendly).
RUN useradd --uid 1001 --gid 0 --no-create-home --home-dir /app --shell /usr/sbin/nologin appuser \
    && chown -R 1001:0 /app
USER 1001

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["python", "-c", "import os,urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:'+os.environ.get('PORT','8000')+'/healthz').status==200 else 1)"]

# Bind to 0.0.0.0:$PORT (exec form via sh so $PORT is expanded).
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
