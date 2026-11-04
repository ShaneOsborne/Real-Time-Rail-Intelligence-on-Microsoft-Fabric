"""Tests for the plain-language hints shown for NROD broker errors."""
from rail_bridge.stomp_client import error_hint


def test_amq339009_hint_mentions_one_connection_and_durable_test():
    hint = error_hint("AMQ339009 Exception getting session")
    assert "one connection" in hint
    assert "NROD_DURABLE=false" in hint


def test_auth_hint():
    assert "password" in error_hint("AMQ229031: Unable to validate user").lower()


def test_unknown_error_has_no_hint():
    assert error_hint("something else") == ""
