"""Output sinks: console (stdout), file (JSON Lines) and eventstream / eventhub (Event Hubs protocol).

``send`` must either deliver *all* events or raise; the STOMP listener only ACKs
a frame (and the Kafka relay only commits offsets) after ``send`` returns successfully.
"""

from __future__ import annotations

import json
import logging
import os
import sys
import threading
from typing import Any, Protocol, TextIO

log = logging.getLogger(__name__)


class SinkError(RuntimeError):
    pass


class Sink(Protocol):
    def send(self, events: list[dict[str, Any]]) -> None: ...

    def close(self) -> None: ...


def _dumps(ev: Any) -> str:
    return json.dumps(ev, separators=(",", ":"), ensure_ascii=False)


class ConsoleSink:
    def __init__(self, stream: TextIO | None = None) -> None:
        self._stream = stream or sys.stdout
        self._lock = threading.Lock()

    def send(self, events: list[dict[str, Any]]) -> None:
        with self._lock:
            for ev in events:
                self._stream.write(_dumps(ev) + "\n")
            self._stream.flush()

    def close(self) -> None:
        pass


class FileSink:
    def __init__(self, path: str) -> None:
        directory = os.path.dirname(os.path.abspath(path))
        os.makedirs(directory, exist_ok=True)
        self._fh = open(path, "a", encoding="utf-8")
        self._lock = threading.Lock()
        self.path = path

    def send(self, events: list[dict[str, Any]]) -> None:
        with self._lock:
            try:
                for ev in events:
                    self._fh.write(_dumps(ev) + "\n")
                self._fh.flush()
                os.fsync(self._fh.fileno())
            except OSError as exc:
                raise SinkError(f"File write failed: {exc}") from exc

    def close(self) -> None:
        with self._lock:
            self._fh.close()


class EventstreamSink:
    """Sends to a Fabric Eventstream *Custom endpoint* source using its
    Event Hubs-compatible connection string (``Endpoint=sb://...;EntityPath=...``).

    The same class serves ``BRIDGE_SINK=eventhub``: an Azure Event Hub connection string
    works identically, only the ``label`` used in errors and logs differs.
    """

    def __init__(self, connection_string: str, entity_name: str = "", label: str = "Eventstream") -> None:
        self.label = label
        try:
            from azure.eventhub import EventData, EventHubProducerClient
        except ImportError as exc:  # pragma: no cover - dependency present in image
            raise SinkError("azure-eventhub is not installed") from exc
        self._EventData = EventData
        kwargs: dict[str, Any] = {}
        if entity_name:
            kwargs["eventhub_name"] = entity_name
        self._client = EventHubProducerClient.from_connection_string(connection_string, **kwargs)
        self._lock = threading.Lock()

    def send(self, events: list[dict[str, Any]]) -> None:
        if not events:
            return
        with self._lock:
            try:
                batch = self._client.create_batch()
                for ev in events:
                    data = self._EventData(_dumps(ev))
                    data.content_type = "application/json"
                    if isinstance(ev, dict):
                        data.properties = {"topic": ev.get("topic", ""), "feed": ev.get("feed", "")}
                    try:
                        batch.add(data)
                    except ValueError:
                        # Batch full: flush and start a new one.
                        self._client.send_batch(batch)
                        batch = self._client.create_batch()
                        batch.add(data)
                if len(batch) > 0:
                    self._client.send_batch(batch)
            except Exception as exc:  # noqa: BLE001 - surface any SDK failure as SinkError
                raise SinkError(f"{self.label} send failed: {exc}") from exc

    def close(self) -> None:
        with self._lock:
            self._client.close()


def build_sink(kind: str, output_file: str = "", connection_string: str = "", entity_name: str = "") -> Sink:
    if kind == "console":
        return ConsoleSink()
    if kind == "file":
        return FileSink(output_file)
    if kind == "eventstream":
        return EventstreamSink(connection_string, entity_name)
    if kind == "eventhub":
        return EventstreamSink(connection_string, entity_name, label="Event Hub")
    raise ValueError(f"Unknown sink '{kind}'")
