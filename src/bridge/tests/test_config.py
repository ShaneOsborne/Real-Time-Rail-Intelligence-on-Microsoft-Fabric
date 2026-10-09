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


def test_eventhub_sink_alias_falls_back_to_eventstream_variables():
    cfg = BridgeConfig.from_env({"BRIDGE_SINK": "eventhub", "EVENTSTREAM_CONNECTION_STRING": "Endpoint=sb://es/", "EVENTSTREAM_ENTITY_NAME": "es-entity"})
    assert cfg.sink_target() == ("Endpoint=sb://es/", "es-entity")
    assert not any("EVENTHUB_CONNECTION_STRING" in e for e in cfg.validate())


def test_eventhub_sink_prefers_eventhub_variables():
    cfg = BridgeConfig.from_env(
        {
            "BRIDGE_SINK": "eventhub",
            "EVENTHUB_CONNECTION_STRING": "Endpoint=sb://eh/;EntityPath=nrod-feed",
            "EVENTHUB_NAME": "nrod-feed",
            "EVENTSTREAM_CONNECTION_STRING": "Endpoint=sb://es/",
        }
    )
    assert cfg.sink_target() == ("Endpoint=sb://eh/;EntityPath=nrod-feed", "nrod-feed")
    assert "Endpoint" not in repr(cfg)


def test_eventstream_sink_still_uses_eventstream_variables():
    cfg = BridgeConfig.from_env({"BRIDGE_SINK": "eventstream", "EVENTSTREAM_CONNECTION_STRING": "Endpoint=sb://es/", "EVENTHUB_CONNECTION_STRING": "Endpoint=sb://eh/"})
    assert cfg.sink_target() == ("Endpoint=sb://es/", "")


def test_eventhub_sink_requires_a_connection_string():
    cfg = BridgeConfig.from_env({"BRIDGE_SOURCE": "replay", "REPLAY_FILE": "x.json", "BRIDGE_SINK": "eventhub"})
    assert any("EVENTHUB_CONNECTION_STRING" in e for e in cfg.validate())


def test_kafka_source_validation():
    errors = " ".join(BridgeConfig.from_env({"BRIDGE_SOURCE": "kafka"}).validate())
    for name in ("RDM_KAFKA_BOOTSTRAP_SERVERS", "RDM_KAFKA_TOPIC", "RDM_KAFKA_CONSUMER_GROUP", "RDM_KAFKA_USERNAME"):
        assert name in errors
    assert "NROD_USERNAME" not in errors  # NROD credentials are not needed for the relay

    ok = BridgeConfig.from_env(
        {
            "BRIDGE_SOURCE": "kafka",
            "RDM_KAFKA_BOOTSTRAP_SERVERS": "b:9093",
            "RDM_KAFKA_TOPIC": "t1, t2",
            "RDM_KAFKA_CONSUMER_GROUP": "g",
            "RDM_KAFKA_USERNAME": "u",
            "RDM_KAFKA_PASSWORD": "kafka-s3cret",
        }
    )
    assert ok.validate() == [] and ok.kafka_topics == ["t1", "t2"]
    assert "kafka-s3cret" not in repr(ok)


def test_kafka_offset_reset_is_validated():
    cfg = BridgeConfig.from_env({"BRIDGE_SOURCE": "replay", "REPLAY_FILE": "x", "RDM_KAFKA_AUTO_OFFSET_RESET": "Earliest"})
    assert cfg.kafka_auto_offset_reset == "earliest"
    bad = BridgeConfig(source="kafka", kafka_bootstrap_servers="b", kafka_topics=["t"], kafka_group_id="g", kafka_username="u", kafka_password="p", kafka_auto_offset_reset="middle")
    assert any("RDM_KAFKA_AUTO_OFFSET_RESET" in e for e in bad.validate())


def test_kafka_relay_never_falls_back_to_the_eventstream_connection_string():
    cfg = BridgeConfig.from_env(
        {
            "BRIDGE_SOURCE": "kafka",
            "BRIDGE_SINK": "eventhub",
            "RDM_KAFKA_BOOTSTRAP_SERVERS": "b:9093",
            "RDM_KAFKA_TOPIC": "t",
            "RDM_KAFKA_CONSUMER_GROUP": "g",
            "RDM_KAFKA_USERNAME": "u",
            "RDM_KAFKA_PASSWORD": "p",
            "EVENTSTREAM_CONNECTION_STRING": "Endpoint=sb://nrod-eventstream/",
        }
    )
    assert cfg.sink_target() == ("", "")
    assert any("EVENTHUB_CONNECTION_STRING" in e for e in cfg.validate())


def test_cli_source_override_also_disables_the_fallback():
    cfg = BridgeConfig.from_env({"BRIDGE_SOURCE": "stomp", "BRIDGE_SINK": "eventhub", "EVENTSTREAM_CONNECTION_STRING": "Endpoint=sb://es/"})
    assert cfg.sink_target()[0] == "Endpoint=sb://es/"
    cfg.source = "kafka"  # what `--source kafka` does in main.build_config
    assert cfg.sink_target() == ("", "")
