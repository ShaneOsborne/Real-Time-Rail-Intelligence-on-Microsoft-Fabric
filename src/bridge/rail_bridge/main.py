"""Entry point: ``python -m rail_bridge [--sink console|file|eventstream|eventhub] [--source stomp|replay|kafka]``."""

from __future__ import annotations

import argparse
import json
import logging
import signal
import sys
import threading
from datetime import datetime, timezone
from typing import Any

from . import __version__
from .config import VALID_SINKS, VALID_SOURCES, BridgeConfig
from .health import BridgeState, start_health_server
from .kafka_relay import run_kafka
from .sinks import build_sink
from .stomp_client import run_replay, run_stomp

_RESERVED = set(vars(logging.LogRecord("", 0, "", 0, "", (), None)).keys()) | {"message", "asctime"}


class JsonFormatter(logging.Formatter):
    """One JSON object per line - friendly to Log Analytics / Container Apps console logs."""

    def format(self, record: logging.LogRecord) -> str:
        entry: dict[str, Any] = {
            "ts": datetime.fromtimestamp(record.created, timezone.utc).isoformat(timespec="milliseconds"),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        for key, value in record.__dict__.items():
            if key not in _RESERVED and not key.startswith("_"):
                entry[key] = value
        if record.exc_info:
            entry["exc"] = self.formatException(record.exc_info)
        return json.dumps(entry, default=str)


def setup_logging(level: str) -> None:
    handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(level)
    logging.getLogger("stomp").setLevel(logging.WARNING)
    logging.getLogger("azure").setLevel(logging.WARNING)


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    p = argparse.ArgumentParser(prog="rail_bridge", description="NROD STOMP (or RDM Kafka) -> Fabric Eventstream / Azure Event Hub bridge")
    p.add_argument("--sink", choices=VALID_SINKS, help="Override BRIDGE_SINK")
    p.add_argument("--source", choices=VALID_SOURCES, help="Override BRIDGE_SOURCE")
    p.add_argument("--topics", help="Comma-separated NROD topics, e.g. TRAIN_MVT_ALL_TOC,RTPPM_ALL")
    p.add_argument("--output-file", help="JSONL path for --sink file")
    p.add_argument("--replay-file", help="Fixture file for --source replay")
    p.add_argument("--replay-loop", action="store_true", help="Loop the replay file forever")
    p.add_argument("--log-level", help="DEBUG, INFO, WARNING ...")
    p.add_argument("--check-config", action="store_true", help="Validate configuration and exit")
    p.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    return p.parse_args(argv)


def build_config(args: argparse.Namespace) -> BridgeConfig:
    cfg = BridgeConfig.from_env()
    if args.sink:
        cfg.sink = args.sink
    if args.source:
        cfg.source = args.source
    if args.topics:
        cfg.topics = [t.strip() for t in args.topics.split(",") if t.strip()]
    if args.output_file:
        cfg.output_file = args.output_file
    if args.replay_file:
        cfg.replay_file = args.replay_file
    if args.replay_loop:
        cfg.replay_loop = True
    if args.log_level:
        cfg.log_level = args.log_level.upper()
    return cfg


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    cfg = build_config(args)
    setup_logging(cfg.log_level)
    log = logging.getLogger("rail_bridge")

    errors = cfg.validate()
    if errors:
        for e in errors:
            log.error("configuration error", extra={"detail": e})
        return 2
    log.info("configuration ok", extra={"config": repr(cfg)})
    if args.check_config:
        return 0

    stop = threading.Event()

    def _stop(signum: int, _frame: Any) -> None:
        log.info("shutdown requested", extra={"signal": signum})
        stop.set()

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    state = BridgeState(stale_after_s=cfg.stale_after_s)
    server = start_health_server(state, cfg.health_port)
    connection_string, entity_name = cfg.sink_target()
    sink = build_sink(cfg.sink, cfg.output_file, connection_string, entity_name)
    try:
        if cfg.source == "replay":
            run_replay(cfg, sink, state, stop)
        elif cfg.source == "kafka":
            run_kafka(cfg, sink, state, stop)
        else:
            run_stomp(cfg, sink, state, stop)
    finally:
        sink.close()
        if server:
            server.shutdown()
        log.info("bridge stopped", extra={"metrics": state.snapshot()})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
