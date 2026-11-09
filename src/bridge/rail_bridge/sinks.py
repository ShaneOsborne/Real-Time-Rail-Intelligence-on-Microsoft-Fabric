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


def sink_error_hint(message: str) -> str:
    """Plain-language next step for the Event Hubs / Eventstream send errors people hit most often."""
    m = message.lower()
    if "localauthdisabled" in m or "local authentication" in m:
        return (
            "Key (shared access) authentication is disabled on this Event Hubs namespace, often by an Azure Policy. "
            "Use Microsoft Entra ID instead: EVENTHUB_AUTH=entra (see Solo 1.8 / Instructor 1.4)."
        )
    if "claim" in m and "send" in m:
        return "The key has no Send right. Use the bridge-send rule's connection string, not students-listen."
    if "cbs token" in m or "unauthorized" in m or "invalidsignature" in m:
        return (
            "The Event Hub (or Eventstream custom endpoint) rejected the key in the connection string. Check that it "
            "is the Send key for THIS hub: the relay needs the rdm-trust bridge-send string (EVENTHUB_RDM_CONNECTION_STRING), "
            "the NROD bridge the nrod-feed one (EVENTHUB_CONNECTION_STRING) or the Eventstream custom endpoint's string; "
            "that the namespace name and EntityPath are exact; and that the key hasn't been regenerated since. On Azure "
            "Container Apps a changed secret only takes effect after a restart: "
            "az containerapp revision restart -g <resource group> -n <app> --revision <active revision>. "
            "If the key is right, key sign-in may be switched off on the namespace (often by an Azure Policy): "
            "az eventhubs namespace show -g <rg> -n <namespace> --query disableLocalAuth. If that says true, use "
            "EVENTHUB_AUTH=entra (Solo 1.8 / Instructor 1.4). With EVENTHUB_AUTH=entra, this error means the identity "
            "has no 'Azure Event Hubs Data Sender' role on the namespace yet (role assignments can take a few minutes)."
        )
    if "could not be found" in m or ("entity" in m and "not found" in m):
        return (
            "The hub in the connection string doesn't exist. Check the namespace name and EntityPath "
            "(nrod-feed, rdm-trust or rdm-darwin) - a missing last character in the namespace name is a common cause."
        )
    return ""


class SinkError(RuntimeError):
    pass


class Sink(Protocol):
    def send(self, events: list[dict[str, Any]]) -> None: ...

    def close(self) -> None: ...


def _dumps(ev: Any) -> str:
    return json.dumps(ev, separators=(",", ":"), ensure_ascii=False)


def drop_nulls(value: Any) -> Any:
    """Return a copy without dictionary entries whose value is None, at any depth.

    Fabric Eventstream's Azure Event Hubs source with *Extended features* (the only level that offers workspace identity)
    infers a schema from the messages and refuses to publish ("Required property 'type' not found in JSON") when a field
    is always null, as some RTPPM and TRUST fields are. KQL reads a missing field as null, so parsing is unchanged.
    None items inside lists are kept, so list positions don't move.
    """
    if isinstance(value, dict):
        return {k: drop_nulls(v) for k, v in value.items() if v is not None}
    if isinstance(value, list):
        return [drop_nulls(v) for v in value]
    return value


# RTPPM is converted from XML, so a repeating element is a JSON object when there's one of it and a list when there are
# several (OperatorPage[].OprServiceGrp is an object for one operator and a list for the next). A field that is sometimes
# an object and sometimes a list has no single type, which Fabric's Extended-features schema inference rejects with
# "Required property 'type' not found". These keys are always sent as lists.
ALWAYS_LIST_KEYS = frozenset({"RAGThresholds", "Sector", "Operator", "OperatorPage", "OprToleranceTotal", "OprServiceGrp"})


def lists_for_repeating_keys(value: Any, keys: frozenset[str] = ALWAYS_LIST_KEYS) -> Any:
    """Return a copy where every value under one of ``keys`` is a list (a single object becomes a one-item list)."""
    if isinstance(value, dict):
        out = {}
        for k, v in value.items():
            v = lists_for_repeating_keys(v, keys)
            out[k] = [v] if k in keys and isinstance(v, dict) else v
        return out
    if isinstance(value, list):
        return [lists_for_repeating_keys(v, keys) for v in value]
    return value


def schema_safe(ev: Any) -> Any:
    """Shape an event so Fabric's Extended-features Event Hubs source can infer one schema: no null-only fields and no
    fields that switch between object and list. KQL reads a missing field as null and Lab 2.1 only reads the RTPPM
    NationalPage, so parsing is unchanged."""
    return lists_for_repeating_keys(drop_nulls(ev))


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

    def __init__(
        self,
        connection_string: str = "",
        entity_name: str = "",
        label: str = "Eventstream",
        fully_qualified_namespace: str = "",
        credential: Any = None,
        drop_null_fields: bool = False,
    ) -> None:
        self.label = label
        self._drop_nulls = drop_null_fields
        try:
            from azure.eventhub import EventData, EventHubProducerClient
        except ImportError as exc:  # pragma: no cover - dependency present in image
            raise SinkError("azure-eventhub is not installed") from exc
        self._EventData = EventData
        if credential is not None:
            # Microsoft Entra ID: no key; the identity needs 'Azure Event Hubs Data Sender' on the namespace or hub.
            self._client = EventHubProducerClient(
                fully_qualified_namespace=fully_qualified_namespace, eventhub_name=entity_name, credential=credential
            )
        else:
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
                    data = self._EventData(_dumps(schema_safe(ev) if self._drop_nulls else ev))
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


def entra_credential() -> Any:
    """DefaultAzureCredential: the managed identity on Azure (AZURE_CLIENT_ID selects a user-assigned one),
    az login / VS Code / environment credentials when you run locally."""
    try:
        from azure.identity import DefaultAzureCredential
    except ImportError as exc:  # pragma: no cover - dependency present in image
        raise SinkError("azure-identity is not installed (pip install -r requirements.txt)") from exc
    return DefaultAzureCredential(exclude_interactive_browser_credential=True)


def build_sink(
    kind: str,
    output_file: str = "",
    connection_string: str = "",
    entity_name: str = "",
    fully_qualified_namespace: str = "",
    credential: Any = None,
    drop_null_fields: bool = True,
) -> Sink:
    if kind == "console":
        return ConsoleSink()
    if kind == "file":
        return FileSink(output_file)
    if kind == "eventstream":
        return EventstreamSink(connection_string, entity_name)
    if kind == "eventhub":
        return EventstreamSink(
            connection_string, entity_name, label="Event Hub",
            fully_qualified_namespace=fully_qualified_namespace, credential=credential,
            drop_null_fields=drop_null_fields,
        )
    raise ValueError(f"Unknown sink '{kind}'")
