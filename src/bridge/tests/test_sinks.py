import sys
import types

import pytest

from rail_bridge.sinks import EventstreamSink, SinkError, build_sink


class _FakeEventData:
    def __init__(self, body):
        self.body = body
        self.content_type = None
        self.properties = None


class _FakeBatch(list):
    def add(self, data):
        self.append(data)


class _FakeProducer:
    instances = []
    fail = False

    def __init__(self, conn, kwargs):
        self.conn, self.kwargs, self.sent, self.closed = conn, kwargs, [], False

    @classmethod
    def from_connection_string(cls, conn, **kwargs):
        inst = cls(conn, kwargs)
        cls.instances.append(inst)
        return inst

    def create_batch(self):
        return _FakeBatch()

    def send_batch(self, batch):
        if _FakeProducer.fail:
            raise RuntimeError("amqp:unauthorized-access")
        self.sent.append(list(batch))

    def close(self):
        self.closed = True


@pytest.fixture
def fake_eventhub():
    module = types.ModuleType("azure.eventhub")
    module.EventData = _FakeEventData
    module.EventHubProducerClient = _FakeProducer
    saved = {k: sys.modules.get(k) for k in ("azure", "azure.eventhub")}
    sys.modules.setdefault("azure", types.ModuleType("azure"))
    sys.modules["azure.eventhub"] = module
    _FakeProducer.instances, _FakeProducer.fail = [], False
    yield _FakeProducer
    for key, value in saved.items():
        if value is None:
            sys.modules.pop(key, None)
        else:
            sys.modules[key] = value


def test_eventhub_alias_builds_the_same_producer_sink(fake_eventhub):
    sink = build_sink("eventhub", connection_string="Endpoint=sb://eh/;EntityPath=nrod-feed", entity_name="")
    assert isinstance(sink, EventstreamSink) and sink.label == "Event Hub"
    sink.send([{"topic": "TRAIN_MVT_ALL_TOC", "feed": "trust", "payload": {}}])
    producer = fake_eventhub.instances[0]
    assert producer.conn.endswith("EntityPath=nrod-feed") and producer.kwargs == {}
    assert producer.sent[0][0].properties == {"topic": "TRAIN_MVT_ALL_TOC", "feed": "trust"}


def test_eventstream_sink_unchanged_and_entity_name_passed(fake_eventhub):
    sink = build_sink("eventstream", connection_string="Endpoint=sb://es/", entity_name="es-entity")
    assert sink.label == "Eventstream"
    assert fake_eventhub.instances[0].kwargs == {"eventhub_name": "es-entity"}


def test_non_dict_values_are_sent_without_properties(fake_eventhub):
    sink = build_sink("eventhub", connection_string="Endpoint=sb://eh/")
    sink.send([[{"header": {"msg_type": "0003"}}]])
    data = fake_eventhub.instances[0].sent[0][0]
    assert data.body == '[{"header":{"msg_type":"0003"}}]' and data.properties is None


def test_send_failure_is_wrapped_with_label(fake_eventhub):
    sink = build_sink("eventhub", connection_string="Endpoint=sb://eh/")
    fake_eventhub.fail = True
    with pytest.raises(SinkError, match="Event Hub send failed"):
        sink.send([{"a": 1}])
