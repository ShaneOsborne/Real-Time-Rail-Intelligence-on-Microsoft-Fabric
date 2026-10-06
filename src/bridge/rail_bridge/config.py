"""Configuration loaded from environment variables (optionally overridden by CLI flags)."""

from __future__ import annotations

import os
from dataclasses import dataclass, field

VALID_SINKS = ("console", "file", "eventstream")
VALID_SOURCES = ("stomp", "replay")


def _bool(value: str | None, default: bool) -> bool:
    if value is None or value == "":
        return default
    return value.strip().lower() in ("1", "true", "yes", "y", "on")


def _topics(value: str | None) -> list[str]:
    if not value:
        return ["TRAIN_MVT_ALL_TOC"]
    return [t.strip() for t in value.split(",") if t.strip()]


@dataclass
class BridgeConfig:
    # Source
    source: str = "stomp"
    nrod_host: str = "publicdatafeeds.networkrail.co.uk"
    nrod_port: int = 61618
    nrod_username: str = ""
    nrod_password: str = field(default="", repr=False)
    topics: list[str] = field(default_factory=lambda: ["TRAIN_MVT_ALL_TOC"])
    durable: bool = True
    client_id: str = ""
    subscription_prefix: str = "rail-fabric-rti"
    heartbeat_ms: int = 15000
    backoff_initial_s: float = 1.0
    backoff_max_s: float = 60.0
    replay_file: str = ""
    replay_interval_s: float = 1.0
    replay_loop: bool = False

    # Sink
    sink: str = "console"
    output_file: str = "./out/messages.jsonl"
    eventstream_connection_string: str = field(default="", repr=False)
    eventstream_entity_name: str = ""
    split_batches: bool = True

    # Ops
    health_port: int = 8080
    log_level: str = "INFO"
    stale_after_s: int = 300

    @classmethod
    def from_env(cls, env: dict[str, str] | None = None) -> BridgeConfig:
        e = os.environ if env is None else env
        username = e.get("NROD_USERNAME", "")
        return cls(
            source=e.get("BRIDGE_SOURCE", "stomp").lower(),
            nrod_host=e.get("NROD_HOST", "publicdatafeeds.networkrail.co.uk"),
            nrod_port=int(e.get("NROD_STOMP_PORT", "61618")),
            nrod_username=username,
            nrod_password=e.get("NROD_PASSWORD", ""),
            topics=_topics(e.get("NROD_TOPICS")),
            durable=_bool(e.get("NROD_DURABLE"), True),
            client_id=e.get("NROD_CLIENT_ID", "") or username,
            subscription_prefix=e.get("NROD_SUBSCRIPTION_PREFIX", "rail-fabric-rti"),
            heartbeat_ms=int(e.get("NROD_HEARTBEAT_MS", "15000")),
            backoff_initial_s=float(e.get("BACKOFF_INITIAL_S", "1")),
            backoff_max_s=float(e.get("BACKOFF_MAX_S", "60")),
            replay_file=e.get("REPLAY_FILE", ""),
            replay_interval_s=float(e.get("REPLAY_INTERVAL_S", "1")),
            replay_loop=_bool(e.get("REPLAY_LOOP"), False),
            sink=e.get("BRIDGE_SINK", "console").lower(),
            output_file=e.get("BRIDGE_OUTPUT_FILE", "./out/messages.jsonl"),
            eventstream_connection_string=e.get("EVENTSTREAM_CONNECTION_STRING", ""),
            eventstream_entity_name=e.get("EVENTSTREAM_ENTITY_NAME", ""),
            split_batches=_bool(e.get("BRIDGE_SPLIT_BATCHES"), True),
            health_port=int(e.get("HEALTH_PORT", "8080")),
            log_level=e.get("LOG_LEVEL", "INFO").upper(),
            stale_after_s=int(e.get("STALE_AFTER_S", "300")),
        )

    def subscription_name(self, topic: str) -> str:
        """Unique durable subscription name per feed (activemq.subscriptionName)."""
        return f"{self.subscription_prefix}-{topic}"

    def validate(self) -> list[str]:
        errors: list[str] = []
        if self.source not in VALID_SOURCES:
            errors.append(f"BRIDGE_SOURCE must be one of {VALID_SOURCES}")
        if self.sink not in VALID_SINKS:
            errors.append(f"BRIDGE_SINK must be one of {VALID_SINKS}")
        if self.source == "stomp":
            if not self.nrod_username or not self.nrod_password:
                errors.append("NROD_USERNAME and NROD_PASSWORD are required for BRIDGE_SOURCE=stomp")
            if not self.topics:
                errors.append("NROD_TOPICS must list at least one topic")
        if self.source == "replay" and not self.replay_file:
            errors.append("REPLAY_FILE is required for BRIDGE_SOURCE=replay")
        if self.sink == "eventstream" and not self.eventstream_connection_string:
            errors.append("EVENTSTREAM_CONNECTION_STRING is required for BRIDGE_SINK=eventstream")
        if self.heartbeat_ms < 0:
            errors.append("NROD_HEARTBEAT_MS must be >= 0")
        return errors
