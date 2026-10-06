import io
import json
import threading

from conftest import FIXTURES
from rail_bridge.config import BridgeConfig
from rail_bridge.health import BridgeState
from rail_bridge.sinks import ConsoleSink, FileSink, SinkError
from rail_bridge.stomp_client import FrameHandler, load_replay_frames, run_replay, stomp12_ack


class FailingSink:
    def send(self, events):
        raise SinkError("boom")

    def close(self):
        pass


class ListSink:
    def __init__(self):
        self.events = []

    def send(self, events):
        self.events.extend(events)

    def close(self):
        pass


HEADERS = {"destination": "/topic/TRAIN_MVT_ALL_TOC", "message-id": "ID:42", "ack": "ack-42", "subscription": "TRAIN_MVT_ALL_TOC"}


def _handler(sink):
    acks = []
    state = BridgeState()
    h = FrameHandler(acks.append, sink, BridgeConfig(), state)
    return h, acks, state


def test_ack_only_after_successful_send():
    sink = ListSink()
    h, acks, state = _handler(sink)
    assert h.handle(HEADERS, (FIXTURES / "trust_batch.json").read_text()) is True
    assert len(sink.events) == 4 and acks == [HEADERS]
    assert state.frames_acked == 1 and state.events_sent == 4


def test_no_ack_and_reconnect_on_send_failure():
    h, acks, state = _handler(FailingSink())
    assert h.handle(HEADERS, (FIXTURES / "trust_batch.json").read_text()) is False
    assert acks == [] and state.send_failures == 1
    assert h.disconnected.is_set()


def test_poison_message_is_acked_and_counted():
    sink = ListSink()
    h, acks, state = _handler(sink)
    assert h.handle(HEADERS, "{broken") is True
    assert sink.events == [] and acks == [HEADERS] and state.parse_failures == 1


def test_stomp12_ack_prefers_ack_header():
    class Conn:
        def __init__(self):
            self.ids = []

        def ack(self, ack_id):
            self.ids.append(ack_id)

    c = Conn()
    stomp12_ack(c)(HEADERS)
    stomp12_ack(c)({"message-id": "ID:7"})
    assert c.ids == ["ack-42", "ID:7"]


def test_console_sink_writes_jsonl():
    buf = io.StringIO()
    ConsoleSink(buf).send([{"a": 1}, {"b": 2}])
    lines = buf.getvalue().splitlines()
    assert [json.loads(x) for x in lines] == [{"a": 1}, {"b": 2}]


def test_file_sink_and_replay_end_to_end(tmp_path):
    out = tmp_path / "out" / "messages.jsonl"
    cfg = BridgeConfig(source="replay", replay_file=str(FIXTURES / "replay_frames.json"), replay_interval_s=0, sink="file", output_file=str(out))
    sink = FileSink(str(out))
    state = BridgeState()
    run_replay(cfg, sink, state, threading.Event())
    sink.close()
    lines = [json.loads(x) for x in out.read_text().splitlines()]
    # 4 TRUST + 2 TD + 1 RTPPM
    assert len(lines) == 7
    assert {ln["feed"] for ln in lines} == {"trust", "td", "rtppm"}
    assert state.frames_received == 3


def test_load_replay_frames_shape():
    frames = load_replay_frames(str(FIXTURES / "replay_frames.json"))
    assert frames[0]["headers"]["destination"] == "/topic/TRAIN_MVT_ALL_TOC"
    assert isinstance(frames[0]["body"], str)
