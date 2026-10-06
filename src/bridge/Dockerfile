# syntax=docker/dockerfile:1
FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY rail_bridge ./rail_bridge
COPY tests/fixtures/replay_frames.json ./fixtures/replay_frames.json

# Run as an unprivileged user
RUN groupadd --system --gid 10001 bridge \
 && useradd --system --uid 10001 --gid bridge --home-dir /app --shell /usr/sbin/nologin bridge \
 && mkdir -p /app/out && chown -R bridge:bridge /app
USER 10001

ENV HEALTH_PORT=8080 \
    BRIDGE_SINK=console \
    REPLAY_FILE=/app/fixtures/replay_frames.json \
    BRIDGE_OUTPUT_FILE=/app/out/messages.jsonl
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=4).status == 200 else 1)"

ENTRYPOINT ["python", "-m", "rail_bridge"]
