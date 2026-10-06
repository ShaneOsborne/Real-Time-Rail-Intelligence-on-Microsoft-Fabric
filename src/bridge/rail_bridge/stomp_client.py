"""NROD STOMP consumer with durable subscriptions, client-individual ACKs and
exponential-backoff reconnects. Also provides an offline ``replay`` source.
"""

from __future__ import annotations

import json
import logging
import threading
import time
from pathlib import Path
from collections.abc import Callable
from typing import Any

from .backoff import ExponentialBackoff
from .config import BridgeConfig
from .health import BridgeState
from .parsing import ParseError, summarise, to_events, topic_from_destination
from .sinks import Sink, SinkError

log = logging.getLogger(__name__)


class FrameHandler:
    """stomp.py listener. stomp.py looks up ``on_<frame>`` methods by name, so a plain
    class works and keeps this unit-testable without the network.
    """

    def __init__(
        self,
        ack: Callable[[dict[str, str]], None],
        sink: Sink,
        cfg: BridgeConfig,
        state: BridgeState,
    ) -> None:
        self._ack = ack
        self._sink = sink
        self._cfg = cfg
        self._state = state
        self.disconnected = threading.Event()
        self.received_any = False

    # --- stomp.py callbacks -------------------------------------------------
    def on_connected(self, frame: Any) -> None:
        log.info("stomp connected", extra={"server": frame.headers.get("server", "")})

    def on_error(self, frame: Any) -> None:
        log.error("stomp error frame", extra={"headers": dict(frame.headers), "body": str(frame.body)[:500]})

    def on_disconnected(self) -> None:
        log.warning("stomp disconnected")
        self.disconnected.set()

    def on_heartbeat_timeout(self) -> None:
        log.warning("stomp heartbeat timeout")
        self.disconnected.set()

    def on_message(self, frame: Any) -> None:
        self.handle(dict(frame.headers), frame.body)

    # --- core logic -----------------------------------------------------------
    def handle(self, headers: dict[str, str], body: str | bytes) -> bool:
        """Process one frame. Returns True if the frame was ACKed."""
        self.received_any = True
        self._state.incr("frames_received")
        self._state.update(last_message_at=time.time())
        topic = topic_from_destination(headers.get("destination", ""))
        message_id = headers.get("message-id", "")

        try:
            events = to_events(body, topic, message_id, split_batches=self._cfg.split_batches)
        except ParseError as exc:
            # Poison message: ACK so it is not redelivered forever, but record it.
            self._state.incr("parse_failures")
            log.warning("unparseable frame acknowledged and dropped", extra={"topic": topic, "error": str(exc)})
            self._safe_ack(headers)
            return True

        try:
            self._sink.send(events)
        except SinkError as exc:
            # Do NOT ACK: the durable subscription will redeliver after reconnect.
            self._state.incr("send_failures")
            log.error("sink send failed; frame not acknowledged, reconnecting", extra={"topic": topic, "error": str(exc)})
            self.disconnected.set()
            return False

        self._state.incr("events_sent", len(events))
        self._safe_ack(headers)
        log.debug("frame processed", extra={"topic": topic, "events": len(events), "types": summarise(events)})
        return True

    def _safe_ack(self, headers: dict[str, str]) -> None:
        try:
            self._ack(headers)
            self._state.incr("frames_acked")
        except Exception as exc:  # noqa: BLE001
            log.error("ack failed", extra={"error": str(exc)})
            self.disconnected.set()


def stomp12_ack(conn: Any) -> Callable[[dict[str, str]], None]:
    """STOMP 1.2 ACK uses the MESSAGE frame's ``ack`` header (fallback: message-id)."""

    def _ack(headers: dict[str, str]) -> None:
        ack_id = headers.get("ack") or headers.get("message-id")
        if ack_id:
            conn.ack(ack_id)

    return _ack


def run_stomp(cfg: BridgeConfig, sink: Sink, state: BridgeState, stop: threading.Event) -> None:
    import stomp  # imported lazily so unit tests do not need the package

    backoff = ExponentialBackoff(initial=cfg.backoff_initial_s, maximum=cfg.backoff_max_s, jitter=0.1)
    hb = cfg.heartbeat_ms

    while not stop.is_set():
        conn = stomp.Connection12(
            [(cfg.nrod_host, cfg.nrod_port)],
            heartbeats=(hb, hb),
            keepalive=True,
            reconnect_attempts_max=1,  # we own the reconnect/backoff loop
        )
        handler = FrameHandler(stomp12_ack(conn), sink, cfg, state)
        conn.set_listener("bridge", handler)
        try:
            connect_headers: dict[str, str] = {}
            if cfg.durable:
                connect_headers["client-id"] = cfg.client_id
            log.info("connecting", extra={"host": cfg.nrod_host, "port": cfg.nrod_port, "durable": cfg.durable})
            conn.connect(username=cfg.nrod_username, passcode=cfg.nrod_password, wait=True, headers=connect_headers)
            for topic in cfg.topics:
                sub_headers: dict[str, str] = {}
                if cfg.durable:
                    sub_headers["activemq.subscriptionName"] = cfg.subscription_name(topic)
                conn.subscribe(destination=f"/topic/{topic}", id=topic, ack="client-individual", headers=sub_headers)
                log.info("subscribed", extra={"topic": topic, "durable_name": sub_headers.get("activemq.subscriptionName")})
            state.update(connected=True)

            while not stop.is_set() and not handler.disconnected.is_set():
                if handler.received_any and backoff.attempt:
                    backoff.reset()
                stop.wait(1.0)
        except Exception as exc:  # noqa: BLE001
            log.error("connection failed", extra={"error": str(exc)})
        finally:
            state.update(connected=False)
            try:
                if conn.is_connected():
                    conn.disconnect()
            except Exception:  # noqa: BLE001
                pass

        if stop.is_set():
            break
        delay = backoff.next_delay()
        state.incr("reconnects")
        log.warning("reconnecting after backoff", extra={"delay_s": round(delay, 2), "attempt": backoff.attempt})
        # NROD only buffers durable messages for ~5 minutes after disconnect.
        stop.wait(delay)

    log.info("stomp loop stopped")


def load_replay_frames(path: str) -> list[dict[str, Any]]:
    """Fixture format: JSON list of {"topic": "...", "body": <JSON value or string>} or JSONL of the same."""
    text = Path(path).read_text(encoding="utf-8")
    stripped = text.lstrip()
    frames = json.loads(text) if stripped.startswith("[") else [json.loads(line) for line in text.splitlines() if line.strip()]
    out = []
    for i, f in enumerate(frames):
        body = f["body"] if isinstance(f["body"], str) else json.dumps(f["body"])
        out.append({"headers": {"destination": f"/topic/{f['topic']}", "message-id": f"replay-{i}"}, "body": body})
    return out


def run_replay(cfg: BridgeConfig, sink: Sink, state: BridgeState, stop: threading.Event) -> None:
    frames = load_replay_frames(cfg.replay_file)
    handler = FrameHandler(lambda _h: None, sink, cfg, state)
    state.update(connected=True)
    log.info("replaying fixtures", extra={"file": cfg.replay_file, "frames": len(frames), "loop": cfg.replay_loop})
    while not stop.is_set():
        for frame in frames:
            if stop.is_set():
                break
            handler.handle(frame["headers"], frame["body"])
            stop.wait(cfg.replay_interval_s)
        if not cfg.replay_loop:
            break
    state.update(connected=False)
