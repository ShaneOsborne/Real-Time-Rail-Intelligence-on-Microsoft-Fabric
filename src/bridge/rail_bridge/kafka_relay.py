"""Rail Data Marketplace (RDM) Kafka -> sink relay (``BRIDGE_SOURCE=kafka``).

Used in the optional shared Event Hub tier (Lab 05c): one instructor-run relay reads the RDM
*NWR Train Movements* topic and forwards every message value to an Azure Event Hub
(``BRIDGE_SINK=eventhub``), so many students can read it through their own consumer groups.

Delivery semantics mirror the STOMP bridge:

* ``enable.auto.commit`` is off. Offsets are committed **only after** the sink has accepted
  the whole batch, so a failed send is re-read after the reconnect (at-least-once).
* A failed send or commit closes the consumer, waits with exponential backoff and re-joins the
  group, which resumes from the last committed offset.
* Message values that are not valid JSON are counted, logged, skipped and committed, so a poison
  message can't block the partition.

``confluent_kafka`` is imported lazily so the unit tests run without it.
"""

from __future__ import annotations

import json
import logging
import threading
import time
from collections.abc import Callable
from typing import Any

from .backoff import ExponentialBackoff
from .config import BridgeConfig
from .health import BridgeState
from .sinks import Sink, SinkError

log = logging.getLogger(__name__)


class KafkaRelayError(RuntimeError):
    """A fatal consumer error: the relay closes the consumer and reconnects."""


def kafka_config(cfg: BridgeConfig) -> dict[str, Any]:
    """librdkafka settings for the RDM consumer (SASL_SSL / PLAIN by default)."""
    conf: dict[str, Any] = {
        "bootstrap.servers": cfg.kafka_bootstrap_servers,
        "group.id": cfg.kafka_group_id,
        "client.id": "rail-fabric-rti-relay",
        "enable.auto.commit": False,
        "auto.offset.reset": cfg.kafka_auto_offset_reset,
        "security.protocol": cfg.kafka_security_protocol,
        "session.timeout.ms": 45000,
    }
    if cfg.kafka_security_protocol.upper().startswith("SASL"):
        conf["sasl.mechanism"] = cfg.kafka_sasl_mechanism
        conf["sasl.username"] = cfg.kafka_username
        conf["sasl.password"] = cfg.kafka_password
    return conf


def _decode(value: bytes | str | None) -> Any:
    if value is None:
        raise ValueError("empty message value (tombstone)")
    if isinstance(value, bytes):
        value = value.decode("utf-8")
    return json.loads(value)


class KafkaRelay:
    """Forwards one consumed batch at a time to the sink and commits only after a successful send."""

    def __init__(self, consumer: Any, sink: Sink, state: BridgeState, max_batch: int = 500, poll_timeout_s: float = 1.0) -> None:
        self._consumer = consumer
        self._sink = sink
        self._state = state
        self._max_batch = max_batch
        self._poll_timeout_s = poll_timeout_s

    def poll_once(self) -> int:
        """Consume and process one batch. Returns the number of messages committed (0 if none arrived).

        Raises ``SinkError`` or ``KafkaRelayError`` when the batch could not be delivered or committed.
        """
        messages = self._consumer.consume(num_messages=self._max_batch, timeout=self._poll_timeout_s)
        return self.process_batch(messages or [])

    def process_batch(self, messages: list[Any]) -> int:
        events: list[Any] = []
        last_by_partition: dict[tuple[str, int], Any] = {}

        for msg in messages:
            err = msg.error()
            if err is not None:
                if _is_fatal(err):
                    raise KafkaRelayError(f"fatal Kafka error: {err}")
                log.warning("kafka consumer event", extra={"error": str(err)})
                continue

            self._state.incr("frames_received")
            self._state.update(last_message_at=time.time())
            last_by_partition[(msg.topic(), msg.partition())] = msg
            try:
                events.append(_decode(msg.value()))
            except (ValueError, UnicodeDecodeError) as exc:
                # Poison message: skip it but still commit past it, as the STOMP bridge does.
                self._state.incr("parse_failures")
                log.warning(
                    "unparseable kafka message skipped",
                    extra={"topic": msg.topic(), "partition": msg.partition(), "offset": msg.offset(), "error": str(exc)},
                )

        if events:
            try:
                self._sink.send(events)
            except SinkError:
                self._state.incr("send_failures")
                raise
            self._state.incr("events_sent", len(events))

        committed = 0
        for msg in last_by_partition.values():
            try:
                # Commits msg.offset() + 1 for that partition, synchronously.
                self._consumer.commit(message=msg, asynchronous=False)
            except Exception as exc:  # noqa: BLE001 - KafkaException when the group rebalanced, broker down ...
                raise KafkaRelayError(f"offset commit failed: {exc}") from exc
            committed += 1
        if last_by_partition:
            self._state.incr("frames_acked", sum(1 for m in messages if m.error() is None))
        return committed


def _is_fatal(err: Any) -> bool:
    fatal = getattr(err, "fatal", None)
    return bool(fatal()) if callable(fatal) else False


def _default_consumer_factory(cfg: BridgeConfig) -> Any:
    from confluent_kafka import Consumer  # imported lazily so unit tests do not need the package

    conf = kafka_config(cfg)
    conf["error_cb"] = lambda err: log.warning("kafka client error", extra={"error": str(err)})
    return Consumer(conf)


def run_kafka(
    cfg: BridgeConfig,
    sink: Sink,
    state: BridgeState,
    stop: threading.Event,
    consumer_factory: Callable[[BridgeConfig], Any] | None = None,
) -> None:
    factory = consumer_factory or _default_consumer_factory
    backoff = ExponentialBackoff(initial=cfg.backoff_initial_s, maximum=cfg.backoff_max_s, jitter=0.1)

    while not stop.is_set():
        consumer = None
        try:
            log.info(
                "kafka connecting",
                extra={"bootstrap": cfg.kafka_bootstrap_servers, "topics": cfg.kafka_topics, "group": cfg.kafka_group_id},
            )
            consumer = factory(cfg)
            consumer.subscribe(
                cfg.kafka_topics,
                on_assign=lambda _c, parts: log.info("partitions assigned", extra={"partitions": [p.partition for p in parts]}),
                on_revoke=lambda _c, parts: log.info("partitions revoked", extra={"partitions": [p.partition for p in parts]}),
            )
            state.update(connected=True)
            relay = KafkaRelay(consumer, sink, state, max_batch=cfg.kafka_max_batch)
            while not stop.is_set():
                if relay.poll_once() and backoff.attempt:
                    backoff.reset()
        except SinkError as exc:
            log.error("sink send failed; offsets not committed, reconnecting", extra={"error": str(exc)})
        except Exception as exc:  # noqa: BLE001
            log.error("kafka relay failed", extra={"error": str(exc)})
        finally:
            state.update(connected=False)
            if consumer is not None:
                try:
                    consumer.close()  # leaves the group; nothing uncommitted is committed (auto commit is off)
                except Exception:  # noqa: BLE001
                    pass

        if stop.is_set():
            break
        delay = backoff.next_delay()
        state.incr("reconnects")
        log.warning("reconnecting after backoff", extra={"delay_s": round(delay, 2), "attempt": backoff.attempt})
        stop.wait(delay)

    log.info("kafka loop stopped")
