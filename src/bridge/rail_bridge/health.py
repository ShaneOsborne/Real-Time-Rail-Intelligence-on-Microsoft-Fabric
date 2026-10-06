"""Tiny HTTP health endpoint used by Docker and Azure Container Apps probes.

GET /healthz -> 200 while the process is alive (liveness)
GET /readyz  -> 200 when connected and a message arrived within ``stale_after_s``
GET /metrics -> JSON counters
"""

from __future__ import annotations

import json
import logging
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

log = logging.getLogger(__name__)


class BridgeState:
    def __init__(self, stale_after_s: int = 300) -> None:
        self._lock = threading.Lock()
        self.started = time.time()
        self.connected = False
        self.last_message_at: float | None = None
        self.frames_received = 0
        self.events_sent = 0
        self.frames_acked = 0
        self.send_failures = 0
        self.parse_failures = 0
        self.reconnects = 0
        self.stale_after_s = stale_after_s

    def update(self, **kwargs: Any) -> None:
        with self._lock:
            for key, value in kwargs.items():
                setattr(self, key, value)

    def incr(self, name: str, by: int = 1) -> None:
        with self._lock:
            setattr(self, name, getattr(self, name) + by)

    def ready(self) -> bool:
        with self._lock:
            if not self.connected:
                return False
            if self.last_message_at is None:
                # Allow a grace period after connecting before declaring stale.
                return time.time() - self.started < self.stale_after_s
            return time.time() - self.last_message_at < self.stale_after_s

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            return {
                "connected": self.connected,
                "uptime_s": round(time.time() - self.started, 1),
                "last_message_age_s": None
                if self.last_message_at is None
                else round(time.time() - self.last_message_at, 1),
                "frames_received": self.frames_received,
                "frames_acked": self.frames_acked,
                "events_sent": self.events_sent,
                "send_failures": self.send_failures,
                "parse_failures": self.parse_failures,
                "reconnects": self.reconnects,
            }


def start_health_server(state: BridgeState, port: int) -> ThreadingHTTPServer | None:
    if port <= 0:
        return None

    class Handler(BaseHTTPRequestHandler):
        def _reply(self, code: int, body: dict[str, Any]) -> None:
            payload = json.dumps(body).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def do_GET(self) -> None:  # noqa: N802
            if self.path == "/healthz":
                self._reply(200, {"status": "alive"})
            elif self.path == "/readyz":
                ok = state.ready()
                self._reply(200 if ok else 503, {"ready": ok, **state.snapshot()})
            elif self.path == "/metrics":
                self._reply(200, state.snapshot())
            else:
                self._reply(404, {"error": "not found"})

        def log_message(self, fmt: str, *args: Any) -> None:
            log.debug("health %s", fmt % args)

    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)  # noqa: S104 - container probe
    threading.Thread(target=server.serve_forever, name="health", daemon=True).start()
    log.info("health endpoint listening", extra={"port": port})
    return server
