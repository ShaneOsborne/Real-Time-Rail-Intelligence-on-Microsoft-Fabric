"""Tests for the plain-language hints shown for NROD broker errors."""
from rail_bridge.stomp_client import error_hint


def test_amq339009_hint_explains_block_and_one_connection():
    hint = error_hint("AMQ339009 Exception getting session")
    assert "TEMPORARY BLOCK" in hint
    assert "one per account" in hint


def test_auth_hint():
    assert "password" in error_hint("AMQ229031: Unable to validate user").lower()


def test_unknown_error_has_no_hint():
    assert error_hint("something else") == ""


def test_backoff_defaults_are_gentle(monkeypatch):
    from rail_bridge.config import BridgeConfig
    cfg = BridgeConfig()
    assert cfg.backoff_initial_s >= 30
    assert cfg.blocked_wait_s >= 1200
