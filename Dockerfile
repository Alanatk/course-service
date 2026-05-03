# ── Stage 1: builder ─────────────────────────────────────────────
# Install all Python dependencies in an isolated layer.
# Only requirements.txt changes trigger a pip re-install.
FROM python:3.12-slim AS builder

WORKDIR /app

# gcc is needed by some Python packages (e.g. cryptography)
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# Install into /install so we can copy only the packages in stage 2
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Stage 2: runtime ─────────────────────────────────────────────
# Slim final image: no gcc, no pip, no build cache.
FROM python:3.12-slim AS runtime

WORKDIR /app

# Copy only the installed packages from the builder
COPY --from=builder /install /usr/local

# Copy application source
COPY app.py .

# ── Security: run as a non-root user ─────────────────────────────
RUN addgroup --system appgroup && \
    adduser  --system --ingroup appgroup appuser
USER appuser

# ── Runtime metadata ─────────────────────────────────────────────
EXPOSE 3000

# HEALTHCHECK used by `docker run` and local testing.
# Kubernetes uses its own readinessProbe in the Deployment manifest.
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c \
    "import urllib.request; urllib.request.urlopen('http://localhost:3000/health')" \
    || exit 1

# ── Start with gunicorn (production WSGI server) ─────────────────
# 2 workers is a safe starting point; tune with --workers=$(nproc*2+1)
CMD ["gunicorn","--bind", "0.0.0.0:3000","--workers", "2","--timeout", "30","app:app"]
