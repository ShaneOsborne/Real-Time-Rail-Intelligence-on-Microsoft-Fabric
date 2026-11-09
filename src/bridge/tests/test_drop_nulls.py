"""Null fields are left out of events sent to the shared Event Hub (Fabric Extended-features schema inference)."""

import json
import os

from rail_bridge.config import BridgeConfig
from rail_bridge.sinks import drop_nulls

FIXTURE = os.path.join(os.path.dirname(__file__), "fixtures", "replay_frames.json")


def _has_null_value(value):
    if isinstance(value, dict):
        return any(v is None or _has_null_value(v) for v in value.values())
    if isinstance(value, list):
        return any(_has_null_value(v) for v in value)
    return False


def test_drops_nested_nulls_and_keeps_values():
    ev = {"msg_type": None, "payload": {"a": 1, "b": None, "c": [{"x": None, "y": "z"}], "d": {"e": None}}}
    assert drop_nulls(ev) == {"payload": {"a": 1, "c": [{"y": "z"}], "d": {}}}


def test_keeps_falsy_values_and_list_positions():
    ev = {"zero": 0, "empty": "", "false": False, "list": [None, 1]}
    assert drop_nulls(ev) == ev


def test_does_not_change_the_input():
    ev = {"a": None, "b": {"c": None}}
    drop_nulls(ev)
    assert ev == {"a": None, "b": {"c": None}}


def test_fixture_frames_have_no_null_fields_after():
    with open(FIXTURE, encoding="utf-8") as fh:
        frames = json.load(fh)
    assert _has_null_value(frames)  # the real feed does contain nulls
    assert not _has_null_value(drop_nulls(frames))


def test_on_by_default_and_can_be_switched_off():
    assert BridgeConfig.from_env({}).eventhub_drop_nulls is True
    assert BridgeConfig.from_env({"EVENTHUB_DROP_NULLS": "false"}).eventhub_drop_nulls is False


def test_repeating_rtppm_sections_are_always_lists():
    from rail_bridge.sinks import schema_safe

    page = {"OperatorPage": [
        {"Operator": {"code": "22"}, "OprToleranceTotal": {"Total": "5"}, "OprServiceGrp": {"name": "A"}},
        {"Operator": {"code": "23"}, "OprToleranceTotal": [{"Total": "1"}, {"Total": "2"}], "OprServiceGrp": [{"name": "B"}]},
        {"Operator": {"code": "24"}, "OprToleranceTotal": {"Total": "3"}, "OprServiceGrp": None},
    ]}
    out = schema_safe({"payload": {"RTPPMDataMsgV1": {"RTPPMData": page}}})["payload"]["RTPPMDataMsgV1"]["RTPPMData"]
    for item in out["OperatorPage"]:
        assert isinstance(item["Operator"], list) and isinstance(item["OprToleranceTotal"], list)
        assert "OprServiceGrp" not in item or isinstance(item["OprServiceGrp"], list)
    assert out["OperatorPage"][2].keys() == {"Operator", "OprToleranceTotal"}


def test_national_page_is_unchanged():
    from rail_bridge.sinks import schema_safe

    national = {"NationalPPM": {"Total": "8253", "PPM": {"text": "85", "rag": "R"}}, "Sector": [{"sectorCode": "LSE"}]}
    ev = {"payload": {"RTPPMDataMsgV1": {"RTPPMData": {"NationalPage": national, "snapshotTStamp": "1"}}}}
    assert schema_safe(ev) == ev
