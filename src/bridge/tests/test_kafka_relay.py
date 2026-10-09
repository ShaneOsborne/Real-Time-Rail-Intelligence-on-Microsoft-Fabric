import json
import threading

import pytest

from rail_bridge.config import BridgeConfig
from rail_bridge.health import BridgeState
from rail_bridge.kafka_relay import KafkaRelay, KafkaRelayError, kafka_config, run_kafka
from rail_bridge.sinks import SinkError


class FakeError:
    def __init__(self, text, fatal=False):
        self._text = text
        self._fatal = fatal

    def fatal(self):
        return self._fatal

    def __str__(self):
        return self._text


class FakeMessage:
    def __init__(self, partition, offset, value, topic="rdm-trust-topic", error=None):
        self._partition = partition
        self._offset = offset
        self._value = value
        self._topic = topic
        self._error = error

    def topic(self):
        return self._topic

    def partition(self):
        return self._partition

    def offset(self):
        return self._offset

    def value(self):
        return self._value

    def error(self):
        return self._error


class FakeConsumer:
    """Returns the queued batches in order, then empty lists. Records commits as (topic, partition, next offset)."""

    def __init__(self, batches, on_empty=None, fail_commit=False):
        self.batches = list(batches)
        self.commits = []
        self.subscribed = None
        self.closed = False
        self.on_empty = on_empty
        self.fail_commit = fail_commit

    def subscribe(self, topics, **_kwargs):
        self.subscribed = topics

    def consume(self, num_messages=1, timeout=-1):
        if self.batches:
            return self.batches.pop(0)
        if self.on_empty:
            self.on_empty()
        return []

    def commit(self, message=None, asynchronous=True):
        assert asynchronous is False, "commits must be synchronous"
        if self.fail_commit:
            raise RuntimeError("commit failed")
        self.commits.append((message.topic(), message.partition(), message.offset() + 1))

    def close(self):
        self.closed = True


class ListSink:
    def __init__(self, fail_times=0):
        self.events = []
        self.fail_times = fail_times
        self.calls = 0

    def send(self, events):
        self.calls += 1
        if self.fail_times:
            self.fail_times -= 1
            raise SinkError("Event Hub send failed: boom")
        self.events.extend(events)

    def close(self):
        pass


def _msg(partition, offset, payload):
    return FakeMessage(partition, offset, json.dumps(payload).encode())


def test_forwards_values_and_commits_last_offset_per_partition_after_send():
    batch = [_msg(0, 10, {"a": 1}), _msg(1, 5, [{"b": 2}, {"c": 3}]), _msg(0, 11, {"d": 4})]
    consumer, sink, state = FakeConsumer([batch]), ListSink(), BridgeState()
    committed = KafkaRelay(consumer, sink, state).poll_once()
    # Values are forwarded as-is (a JSON array stays one event; the KQL update policy expands it)
    assert sink.events == [{"a": 1}, [{"b": 2}, {"c": 3}], {"d": 4}]
    assert committed == 2
    assert sorted(consumer.commits) == [("rdm-trust-topic", 0, 12), ("rdm-trust-topic", 1, 6)]
    assert state.frames_received == 3 and state.events_sent == 3 and state.frames_acked == 3


def test_no_commit_when_sink_fails():
    consumer, state = FakeConsumer([[_msg(0, 1, {"a": 1})]]), BridgeState()
    with pytest.raises(SinkError):
        KafkaRelay(consumer, ListSink(fail_times=1), state).poll_once()
    assert consumer.commits == [] and state.send_failures == 1 and state.events_sent == 0


def test_poison_message_is_skipped_but_committed():
    batch = [FakeMessage(0, 7, b"{broken"), _msg(0, 8, {"ok": True})]
    consumer, sink, state = FakeConsumer([batch]), ListSink(), BridgeState()
    KafkaRelay(consumer, sink, state).poll_once()
    assert sink.events == [{"ok": True}]
    assert consumer.commits == [("rdm-trust-topic", 0, 9)] and state.parse_failures == 1


def test_only_poison_messages_still_commit_without_sending():
    consumer, sink, state = FakeConsumer([[FakeMessage(0, 3, None)]]), ListSink(), BridgeState()
    KafkaRelay(consumer, sink, state).poll_once()
    assert sink.calls == 0 and consumer.commits == [("rdm-trust-topic", 0, 4)]


def test_non_fatal_error_events_are_ignored_and_fatal_ones_raise():
    benign = FakeMessage(0, -1, None, error=FakeError("broker transport failure"))
    consumer, sink, state = FakeConsumer([[benign, _msg(0, 1, {"a": 1})]]), ListSink(), BridgeState()
    KafkaRelay(consumer, sink, state).poll_once()
    assert sink.events == [{"a": 1}] and state.frames_received == 1

    fatal = FakeMessage(0, -1, None, error=FakeError("fenced", fatal=True))
    with pytest.raises(KafkaRelayError):
        KafkaRelay(FakeConsumer([[fatal]]), ListSink(), BridgeState()).poll_once()


def test_commit_failure_raises_relay_error():
    consumer = FakeConsumer([[_msg(0, 1, {"a": 1})]], fail_commit=True)
    with pytest.raises(KafkaRelayError):
        KafkaRelay(consumer, ListSink(), BridgeState()).poll_once()


def test_empty_poll_is_a_no_op():
    consumer, sink = FakeConsumer([]), ListSink()
    assert KafkaRelay(consumer, sink, BridgeState()).poll_once() == 0
    assert sink.calls == 0 and consumer.commits == []


def _kafka_cfg(**overrides):
    env = {
        "BRIDGE_SOURCE": "kafka",
        "BRIDGE_SINK": "eventhub",
        "RDM_KAFKA_BOOTSTRAP_SERVERS": "broker1:9093,broker2:9093",
        "RDM_KAFKA_TOPIC": "trust-topic",
        "RDM_KAFKA_CONSUMER_GROUP": "rdm-group",
        "RDM_KAFKA_USERNAME": "user",
        "RDM_KAFKA_PASSWORD": "pa55",
        "EVENTHUB_CONNECTION_STRING": "Endpoint=sb://x/;EntityPath=rdm-trust",
        "BACKOFF_INITIAL_S": "0.01",
        "BACKOFF_MAX_S": "0.02",
    }
    env.update(overrides)
    return BridgeConfig.from_env(env)


def test_run_kafka_reconnects_after_send_failure_and_redelivers():
    """First consumer: send fails, nothing committed, consumer closed. Second consumer re-reads and commits."""
    stop = threading.Event()
    sink = ListSink(fail_times=1)
    batch = [_msg(0, 42, {"n": 1})]
    consumers = [FakeConsumer([batch]), FakeConsumer([batch], on_empty=stop.set)]
    created = []

    def factory(cfg):
        c = consumers[len(created)]
        created.append(c)
        return c

    state = BridgeState()
    run_kafka(_kafka_cfg(), sink, state, stop, consumer_factory=factory)

    first, second = created
    assert first.commits == [] and first.closed
    assert second.commits == [("rdm-trust-topic", 0, 43)] and second.closed
    assert first.subscribed == ["trust-topic"]
    assert sink.events == [{"n": 1}]
    assert state.reconnects == 1 and state.send_failures == 1 and state.connected is False


def test_kafka_config_sasl_and_manual_commit():
    conf = kafka_config(_kafka_cfg())
    assert conf["enable.auto.commit"] is False
    assert conf["security.protocol"] == "SASL_SSL" and conf["sasl.mechanism"] == "PLAIN"
    assert conf["sasl.username"] == "user" and conf["group.id"] == "rdm-group"
    assert conf["bootstrap.servers"] == "broker1:9093,broker2:9093"
    assert conf["auto.offset.reset"] == "latest"


def test_kafka_config_without_sasl_has_no_credentials():
    conf = kafka_config(_kafka_cfg(RDM_KAFKA_SECURITY_PROTOCOL="SSL"))
    assert "sasl.username" not in conf and "sasl.password" not in conf
