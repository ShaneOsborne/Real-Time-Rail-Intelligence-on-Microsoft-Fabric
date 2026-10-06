"""Parse NROD STOMP frame bodies into envelope events.

Every event sent downstream has the same envelope so a single Eventhouse table
(``RawFeed``) can hold all feeds:

    {
      "source": "nrod",
      "topic": "TRAIN_MVT_ALL_TOC",
      "feed": "trust",
      "msg_type": "0003",            # TRUST only, else null
      "message_id": "ID:...",        # STOMP message-id
      "batch_index": 0,              # position inside the STOMP frame's array
      "received_utc": "2026-10-05T09:14:52.016Z",
      "payload": { ... original item ... }
    }
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any

TRUST_MSG_TYPES = {
    "0001": "activation",
    "0002": "cancellation",
    "0003": "movement",
    "0004": "unidentified",
    "0005": "reinstatement",
    "0006": "change_of_origin",
    "0007": "change_of_identity",
    "0008": "change_of_location",
}


class ParseError(ValueError):
    """Raised when a frame body cannot be decoded as JSON."""


def feed_for_topic(topic: str) -> str:
    t = topic.upper()
    if t.startswith("TRAIN_MVT"):
        return "trust"
    if t.startswith("TD_"):
        return "td"
    if t.startswith("RTPPM"):
        return "rtppm"
    if t.startswith("VSTP"):
        return "vstp"
    if t.startswith("TSR"):
        return "tsr"
    return "other"


def topic_from_destination(destination: str) -> str:
    """'/topic/TRAIN_MVT_ALL_TOC' -> 'TRAIN_MVT_ALL_TOC'."""
    return destination.rsplit("/", 1)[-1] if destination else ""


def decode_body(body: str | bytes) -> Any:
    if isinstance(body, bytes):
        body = body.decode("utf-8")
    try:
        return json.loads(body)
    except json.JSONDecodeError as exc:
        raise ParseError(f"Invalid JSON body: {exc}") from exc


def trust_msg_type(item: Any) -> str | None:
    if isinstance(item, dict):
        header = item.get("header")
        if isinstance(header, dict):
            mt = header.get("msg_type")
            return str(mt) if mt is not None else None
    return None


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def to_events(
    body: str | bytes,
    topic: str,
    message_id: str = "",
    split_batches: bool = True,
    received_utc: str | None = None,
) -> list[dict[str, Any]]:
    """Convert one STOMP frame body into one or more envelope events.

    NROD TRUST/TD frames contain JSON arrays (batches). With ``split_batches`` each
    array item becomes its own event; otherwise the whole array is a single payload.
    """
    data = decode_body(body)
    feed = feed_for_topic(topic)
    ts = received_utc or utc_now_iso()

    items: list[Any]
    if split_batches and isinstance(data, list):
        items = data
    else:
        items = [data]

    events = []
    for idx, item in enumerate(items):
        events.append(
            {
                "source": "nrod",
                "topic": topic,
                "feed": feed,
                "msg_type": trust_msg_type(item) if feed == "trust" else None,
                "message_id": message_id,
                "batch_index": idx,
                "received_utc": ts,
                "payload": item,
            }
        )
    return events


def summarise(events: list[dict[str, Any]]) -> dict[str, int]:
    """Count events by TRUST message type name (useful for logging)."""
    counts: dict[str, int] = {}
    for ev in events:
        name = TRUST_MSG_TYPES.get(ev.get("msg_type") or "", ev.get("feed", "other"))
        counts[name] = counts.get(name, 0) + 1
    return counts
