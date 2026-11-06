"""Tests for the plain-language hints shown when an Event Hub / Eventstream send fails."""
from rail_bridge.sinks import sink_error_hint


def test_cbs_token_failure_points_at_key_and_restart():
    hint = sink_error_hint("Event Hub send failed: CBS Token authentication failed.\nStatus code: None")
    assert "rdm-trust" in hint
    assert "restart" in hint


def test_missing_send_claim():
    assert "bridge-send" in sink_error_hint("Unauthorized access. 'Send' claim(s) are required to perform this operation.")


def test_unknown_hub():
    assert "EntityPath" in sink_error_hint("The messaging entity 'sb://x/rdm-trus' could not be found.")


def test_other_errors_have_no_hint():
    assert sink_error_hint("Connection reset by peer") == ""
