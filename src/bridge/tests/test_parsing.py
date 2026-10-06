import json

import pytest

from conftest import FIXTURES
from rail_bridge.parsing import (
    ParseError,
    feed_for_topic,
    summarise,
    to_events,
    topic_from_destination,
    trust_msg_type,
)


def _trust_body() -> str:
    return (FIXTURES / "trust_batch.json").read_text()


def test_trust_batch_is_split_into_events():
    events = to_events(_trust_body(), "TRAIN_MVT_ALL_TOC", "ID:1", received_utc="2026-10-05T09:00:00Z")
    assert len(events) == 4
    assert [e["msg_type"] for e in events] == ["0001", "0003", "0003", "0002"]
    assert [e["batch_index"] for e in events] == [0, 1, 2, 3]
    assert all(e["feed"] == "trust" and e["source"] == "nrod" for e in events)
    assert events[1]["payload"]["body"]["variation_status"] == "LATE"
    assert events[0]["received_utc"] == "2026-10-05T09:00:00Z"


def test_trust_batch_unsplit_keeps_array():
    events = to_events(_trust_body(), "TRAIN_MVT_ALL_TOC", split_batches=False)
    assert len(events) == 1
    assert isinstance(events[0]["payload"], list)
    assert events[0]["msg_type"] is None


def test_td_and_rtppm_feeds():
    td = to_events((FIXTURES / "td_batch.json").read_text(), "TD_ALL_SIG_AREA")
    assert len(td) == 2 and td[0]["feed"] == "td" and td[0]["msg_type"] is None
    rtppm = to_events((FIXTURES / "rtppm.json").read_text(), "RTPPM_ALL")
    assert len(rtppm) == 1 and rtppm[0]["feed"] == "rtppm"
    assert "RTPPMDataMsgV1" in rtppm[0]["payload"]


def test_bytes_body_supported():
    events = to_events(_trust_body().encode(), "TRAIN_MVT_ALL_TOC")
    assert len(events) == 4


def test_invalid_json_raises():
    with pytest.raises(ParseError):
        to_events("not json", "TRAIN_MVT_ALL_TOC")


@pytest.mark.parametrize(
    "topic,feed",
    [("TRAIN_MVT_ALL_TOC", "trust"), ("TRAIN_MVT_HB_TOC", "trust"), ("TD_ALL_SIG_AREA", "td"),
     ("RTPPM_ALL", "rtppm"), ("VSTP_ALL", "vstp"), ("TSR_ALL_ROUTE", "tsr"), ("FOO", "other")],
)
def test_feed_for_topic(topic, feed):
    assert feed_for_topic(topic) == feed


def test_topic_from_destination():
    assert topic_from_destination("/topic/TRAIN_MVT_ALL_TOC") == "TRAIN_MVT_ALL_TOC"
    assert topic_from_destination("") == ""


def test_trust_msg_type_handles_odd_input():
    assert trust_msg_type({"header": {"msg_type": "0003"}}) == "0003"
    assert trust_msg_type({"header": "x"}) is None
    assert trust_msg_type([1, 2]) is None


def test_summarise_counts_names():
    events = to_events(_trust_body(), "TRAIN_MVT_ALL_TOC")
    assert summarise(events) == {"activation": 1, "movement": 2, "cancellation": 1}


def test_events_are_json_serialisable():
    for ev in to_events(_trust_body(), "TRAIN_MVT_ALL_TOC"):
        json.dumps(ev)
