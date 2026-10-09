"""Configuration loaded from environment variables (optionally overridden by CLI flags)."""

from __future__ import annotations

import os
from dataclasses import dataclass, field

# "eventhub" uses the same Event Hubs producer as "eventstream", just pointed at an Azure Event Hub
# (the optional shared tier in Lab 05c) instead of a Fabric Eventstream custom endpoint.
VALID_SINKS = ("console", "file", "eventstream", "eventhub")
VALID_SOURCES = ("stomp", "replay", "kafka")
KAFKA_OFFSET_RESETS = ("latest", "earliest")


def _bool(value: str | None, default: bool) -> bool:
    if value is None or value == "":
        return default
    return value.strip().lower() in ("1", "true", "yes", "y", "on")


def _list(value: str | None) -> list[str]:
    if not value:
        return []
    return [t.strip() for t in value.split(",") if t.strip()]


def _topics(value: str | None) -> list[str]:
    return _list(value) or ["TRAIN_MVT_ALL_TOC"]


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

    # Kafka source (BRIDGE_SOURCE=kafka): Rail Data Marketplace -> Event Hub relay
    kafka_bootstrap_servers: str = ""
    kafka_topics: list[str] = field(default_factory=list)
    kafka_group_id: str = ""
    kafka_username: str = ""
    kafka_password: str = field(default="", repr=False)
    kafka_security_protocol: str = "SASL_SSL"
    kafka_sasl_mechanism: str = "PLAIN"
    kafka_auto_offset_reset: str = "latest"
    kafka_max_batch: int = 500

    # Sink
    sink: str = "console"
    output_file: str = "./out/messages.jsonl"
    eventstream_connection_string: str = field(default="", repr=False)
    eventstream_entity_name: str = ""
    eventhub_connection_string: str = field(default="", repr=False)
    eventhub_name: str = ""
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
            kafka_bootstrap_servers=e.get("RDM_KAFKA_BOOTSTRAP_SERVERS", ""),
            kafka_topics=_list(e.get("RDM_KAFKA_TOPIC")),
            kafka_group_id=e.get("RDM_KAFKA_CONSUMER_GROUP", ""),
            kafka_username=e.get("RDM_KAFKA_USERNAME", ""),
            kafka_password=e.get("RDM_KAFKA_PASSWORD", ""),
            kafka_security_protocol=e.get("RDM_KAFKA_SECURITY_PROTOCOL", "") or "SASL_SSL",
            kafka_sasl_mechanism=e.get("RDM_KAFKA_SASL_MECHANISM", "") or "PLAIN",
            kafka_auto_offset_reset=(e.get("RDM_KAFKA_AUTO_OFFSET_RESET", "") or "latest").lower(),
            kafka_max_batch=int(e.get("KAFKA_MAX_BATCH", "") or "500"),
            sink=e.get("BRIDGE_SINK", "console").lower(),
            output_file=e.get("BRIDGE_OUTPUT_FILE", "./out/messages.jsonl"),
            eventstream_connection_string=e.get("EVENTSTREAM_CONNECTION_STRING", ""),
            eventstream_entity_name=e.get("EVENTSTREAM_ENTITY_NAME", ""),
            eventhub_connection_string=e.get("EVENTHUB_CONNECTION_STRING", ""),
            eventhub_name=e.get("EVENTHUB_NAME", ""),
            split_batches=_bool(e.get("BRIDGE_SPLIT_BATCHES"), True),
            health_port=int(e.get("HEALTH_PORT", "8080")),
            log_level=e.get("LOG_LEVEL", "INFO").upper(),
            stale_after_s=int(e.get("STALE_AFTER_S", "300")),
        )

    def subscription_name(self, topic: str) -> str:
        """Unique durable subscription name per feed (activemq.subscriptionName)."""
        return f"{self.subscription_prefix}-{topic}"

    def sink_target(self) -> tuple[str, str]:
        """(connection string, entity name) for the Event Hubs-protocol sinks.

        ``eventhub`` falls back to the Eventstream variables so an existing .env keeps working - except for the
        Kafka relay, so RDM data can never be sent to the NROD Eventstream by accident.
        """
        if self.sink == "eventhub":
            if self.eventhub_connection_string or self.source == "kafka":
                return self.eventhub_connection_string, self.eventhub_name
            return self.eventstream_connection_string, self.eventhub_name or self.eventstream_entity_name
        return self.eventstream_connection_string, self.eventstream_entity_name

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
        if self.source == "kafka":
            if not self.kafka_bootstrap_servers:
                errors.append("RDM_KAFKA_BOOTSTRAP_SERVERS is required for BRIDGE_SOURCE=kafka")
            if not self.kafka_topics:
                errors.append("RDM_KAFKA_TOPIC is required for BRIDGE_SOURCE=kafka")
            if not self.kafka_group_id:
                errors.append("RDM_KAFKA_CONSUMER_GROUP is required for BRIDGE_SOURCE=kafka")
            if self.kafka_security_protocol.upper().startswith("SASL") and (not self.kafka_username or not self.kafka_password):
                errors.append("RDM_KAFKA_USERNAME and RDM_KAFKA_PASSWORD are required for BRIDGE_SOURCE=kafka with SASL")
            if self.kafka_auto_offset_reset not in KAFKA_OFFSET_RESETS:
                errors.append(f"RDM_KAFKA_AUTO_OFFSET_RESET must be one of {KAFKA_OFFSET_RESETS}")
            if self.kafka_max_batch < 1:
                errors.append("KAFKA_MAX_BATCH must be >= 1")
        if self.sink == "eventstream" and not self.eventstream_connection_string:
            errors.append("EVENTSTREAM_CONNECTION_STRING is required for BRIDGE_SINK=eventstream")
        if self.sink == "eventhub" and not self.sink_target()[0]:
            errors.append(
                "EVENTHUB_CONNECTION_STRING is required for BRIDGE_SINK=eventhub "
                "(the NROD bridge also accepts EVENTSTREAM_CONNECTION_STRING; the Kafka relay does not)"
            )
        if self.heartbeat_ms < 0:
            errors.append("NROD_HEARTBEAT_MS must be >= 0")
        return errors
