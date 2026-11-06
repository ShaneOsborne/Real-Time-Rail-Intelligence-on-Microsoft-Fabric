"""Tests for EVENTHUB_AUTH=entra (Microsoft Entra ID sign-in to Azure Event Hubs)."""
from rail_bridge.config import BridgeConfig
from rail_bridge.sinks import sink_error_hint


def _cfg(**env):
    base = {"BRIDGE_SOURCE": "kafka", "BRIDGE_SINK": "eventhub", "RDM_KAFKA_BOOTSTRAP_SERVERS": "b:9092",
            "RDM_KAFKA_TOPIC": "TRAIN_MVT_ALL_TOC", "RDM_KAFKA_CONSUMER_GROUP": "g",
            "RDM_KAFKA_USERNAME": "u", "RDM_KAFKA_PASSWORD": "p"}
    base.update(env)
    return BridgeConfig.from_env(base)


def test_entra_needs_namespace_and_hub_but_no_connection_string():
    cfg = _cfg(EVENTHUB_AUTH="entra", EVENTHUB_NAMESPACE="railrti-ehns-abc", EVENTHUB_NAME="rdm-trust")
    assert cfg.validate() == []
    assert cfg.uses_entra
    assert cfg.eventhub_fqdn == "railrti-ehns-abc.servicebus.windows.net"


def test_entra_accepts_fully_qualified_namespace():
    cfg = _cfg(EVENTHUB_AUTH="entra", EVENTHUB_NAMESPACE="sb://x.servicebus.windows.net/", EVENTHUB_NAME="rdm-trust")
    assert cfg.eventhub_fqdn == "x.servicebus.windows.net"


def test_entra_missing_values_are_reported():
    errors = " ".join(_cfg(EVENTHUB_AUTH="entra").validate())
    assert "EVENTHUB_NAMESPACE" in errors and "EVENTHUB_NAME" in errors


def test_key_mode_still_needs_connection_string():
    assert any("EVENTHUB_CONNECTION_STRING" in e for e in _cfg().validate())


def test_bad_auth_value():
    assert any("EVENTHUB_AUTH" in e for e in _cfg(EVENTHUB_AUTH="sas", EVENTHUB_CONNECTION_STRING="x").validate())


def test_cbs_hint_mentions_disabled_local_auth():
    assert "disableLocalAuth" in sink_error_hint("CBS Token authentication failed.")
