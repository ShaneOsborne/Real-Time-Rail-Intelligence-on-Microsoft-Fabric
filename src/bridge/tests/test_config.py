from rail_bridge.config import BridgeConfig


def test_defaults_from_empty_env():
    cfg = BridgeConfig.from_env({})
    assert cfg.nrod_host == "publicdatafeeds.networkrail.co.uk"
    assert cfg.nrod_port == 61618
    assert cfg.topics == ["TRAIN_MVT_ALL_TOC"]
    assert cfg.durable is True and cfg.sink == "console"


def test_client_id_defaults_to_username_and_subscription_names_unique():
    cfg = BridgeConfig.from_env({"NROD_USERNAME": "me@example.com", "NROD_TOPICS": "TRAIN_MVT_ALL_TOC, RTPPM_ALL"})
    assert cfg.client_id == "me@example.com"
    assert cfg.topics == ["TRAIN_MVT_ALL_TOC", "RTPPM_ALL"]
    names = {cfg.subscription_name(t) for t in cfg.topics}
    assert len(names) == 2


def test_validation_errors():
    cfg = BridgeConfig.from_env({"BRIDGE_SINK": "eventstream"})
    errors = " ".join(cfg.validate())
    assert "NROD_USERNAME" in errors and "EVENTSTREAM_CONNECTION_STRING" in errors


def test_replay_console_is_valid_without_credentials():
    cfg = BridgeConfig.from_env({"BRIDGE_SOURCE": "replay", "REPLAY_FILE": "x.json"})
    assert cfg.validate() == []


def test_password_not_in_repr():
    cfg = BridgeConfig.from_env({"NROD_PASSWORD": "s3cret", "EVENTSTREAM_CONNECTION_STRING": "Endpoint=sb://x"})
    assert "s3cret" not in repr(cfg) and "Endpoint" not in repr(cfg)
