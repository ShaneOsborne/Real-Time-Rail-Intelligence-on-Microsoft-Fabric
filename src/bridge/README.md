# STOMP → Fabric Eventstream bridge

This bridge connects to the Network Rail Open Data ActiveMQ broker over STOMP and forwards every message to a
**Fabric Eventstream custom endpoint** using the Event Hubs protocol (`azure-eventhub`). It can also write to the console or to a JSONL file, so you can run it without Fabric.

In the optional shared tier ([Lab 05c](../../docs/labs/05c-shared-event-hub.md)) the same image does two more jobs:

* **Sink `eventhub`**: the same producer, sending to an **Azure Event Hub** (`nrod-feed`) instead of an Eventstream.
* **Source `kafka`**: an **RDM Kafka → Event Hub relay** (`confluent-kafka` consumer, `SASL_SSL` / `PLAIN`). It forwards each message
  value unchanged to the sink, with `enable.auto.commit=false`, and commits offsets **only after** the sink has accepted the batch.
  A failed send or commit closes the consumer, backs off and re-joins the group, which resumes from the last committed offset
  (at-least-once). Values that aren't JSON are logged, counted in `parse_failures`, skipped and committed.

## Features

* **Durable subscriptions.** The CONNECT header `client-id` is set to the NROD username by default. Each feed gets a SUBSCRIBE header `activemq.subscriptionName` = `<prefix>-<topic>`, which is unique per feed.
* **`ack: client-individual`.** A frame is ACKed **only after** the sink has accepted all of its events. If a send fails, the frame isn't ACKed, the bridge reconnects and the broker redelivers it. NROD buffers durable messages for only about **5 minutes** after a disconnect.
* **Heartbeats** default to `15000,15000`.
* **Exponential backoff** of 1, 2, 4, 8, 16 … seconds with ±10 % jitter, capped at `BACKOFF_MAX_S` (default 60 s). The backoff resets once messages flow again.
* **Batch splitting.** TRUST and TD frames are JSON arrays, and each item becomes its own event. Set `BRIDGE_SPLIT_BATCHES=false` to keep whole arrays.
* **Envelope.** Every event looks like `{source, topic, feed, msg_type, message_id, batch_index, received_utc, payload}`. It maps one-to-one onto the Eventhouse `RawFeed` table.
* **Graceful shutdown.** On SIGTERM or SIGINT the bridge finishes the frame in flight, disconnects and closes the producer.
* **Structured JSON logs** go to stderr, ready for Container Apps and Log Analytics.
* **Health endpoint** on `:8080`: `/healthz` (liveness), `/readyz` (connected and a message received within `STALE_AFTER_S`) and `/metrics` (JSON counters).
* **Replay source** (`--source replay`) replays the bundled fixtures, so it works with no accounts at all.

## Run

```bash
# venv
python -m venv .venv && source .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python -m rail_bridge --source replay --replay-file tests/fixtures/replay_frames.json --sink console   # offline
python -m rail_bridge --sink console                   # live NROD -> stdout (needs NROD_USERNAME/PASSWORD)
python -m rail_bridge --sink file --output-file out/messages.jsonl
python -m rail_bridge --sink eventstream               # needs EVENTSTREAM_CONNECTION_STRING
python -m rail_bridge --sink eventhub                  # optional: needs EVENTHUB_CONNECTION_STRING (falls back to EVENTSTREAM_*)
python -m rail_bridge --source kafka --sink console    # optional RDM relay: needs RDM_KAFKA_*
python -m rail_bridge --check-config                   # validate env and exit

# Docker
docker compose --profile offline up --build replay     # offline demo
docker compose up --build bridge                       # reads ../../.env
docker compose --profile relay up --build rdm-relay    # optional RDM relay (export EVENTHUB_RDM_CONNECTION_STRING, RELAY_SINK=eventhub)
curl localhost:8080/metrics
```

The repo-root scripts `scripts/run-local.sh` and `scripts/run-local.ps1` wrap all of these commands.

## Configuration (environment variables)

| Variable | Default | Notes |
|---|---|---|
| `BRIDGE_SOURCE` | `stomp` | `stomp`, `replay` or `kafka` (RDM relay) |
| `BRIDGE_SINK` | `console` | `console`, `file`, `eventstream` or `eventhub` |
| `NROD_HOST` / `NROD_STOMP_PORT` | `publicdatafeeds.networkrail.co.uk` / `61618` | |
| `NROD_USERNAME` / `NROD_PASSWORD` | – | Your NROD login (email and password) |
| `NROD_TOPICS` | `TRAIN_MVT_ALL_TOC` | Comma-separated, e.g. `TRAIN_MVT_ALL_TOC,RTPPM_ALL,VSTP_ALL,TSR_ALL_ROUTE,TD_ALL_SIG_AREA` |
| `NROD_DURABLE` | `true` | |
| `NROD_CLIENT_ID` | = username | Only **one** live connection may use a given client-id |
| `NROD_SUBSCRIPTION_PREFIX` | `rail-fabric-rti` | |
| `NROD_HEARTBEAT_MS` | `15000` | |
| `BACKOFF_INITIAL_S` / `BACKOFF_MAX_S` | `1` / `60` | |
| `EVENTSTREAM_CONNECTION_STRING` | – | Eventstream custom endpoint → Event Hub → SAS key → connection string (with `EntityPath`) |
| `EVENTSTREAM_ENTITY_NAME` | – | Only needed if the connection string has no `EntityPath` |
| `EVENTHUB_CONNECTION_STRING` | = `EVENTSTREAM_CONNECTION_STRING` | Sink `eventhub`: Azure Event Hub **Send** connection string (with `EntityPath`). The `kafka` source never falls back to the Eventstream string |
| `EVENTHUB_NAME` | = `EVENTSTREAM_ENTITY_NAME` | Only needed if the Event Hub connection string has no `EntityPath` (no fallback for the `kafka` source) |
| `RDM_KAFKA_BOOTSTRAP_SERVERS` / `RDM_KAFKA_TOPIC` / `RDM_KAFKA_CONSUMER_GROUP` | – | Source `kafka`. Topic may be a comma-separated list |
| `RDM_KAFKA_USERNAME` / `RDM_KAFKA_PASSWORD` | – | Source `kafka` (SASL) |
| `RDM_KAFKA_SECURITY_PROTOCOL` / `RDM_KAFKA_SASL_MECHANISM` | `SASL_SSL` / `PLAIN` | |
| `RDM_KAFKA_AUTO_OFFSET_RESET` | `latest` | `latest` or `earliest`; only used when the group has no committed offset |
| `KAFKA_MAX_BATCH` | `500` | Messages per consume/send/commit cycle |
| `BRIDGE_OUTPUT_FILE` | `./out/messages.jsonl` | |
| `BRIDGE_SPLIT_BATCHES` | `true` | |
| `REPLAY_FILE`, `REPLAY_INTERVAL_S`, `REPLAY_LOOP` | – / `1` / `false` | |
| `HEALTH_PORT` | `8080` | `0` disables the endpoint |
| `STALE_AFTER_S` | `300` | Used by `/readyz` |
| `LOG_LEVEL` | `INFO` | |

## Volumes and sizing

| Feed | Typical peak | Suggested size |
|---|---|---|
| `TRAIN_MVT_ALL_TOC` (TRUST) | up to ~600 msgs/min (batched) | 0.25 vCPU / 0.5 GiB |
| `TD_ALL_SIG_AREA` | up to ~6,000 msgs/min | 0.5 vCPU / 1 GiB |
| `RTPPM_ALL` | 1/min | negligible |

## Tests

```bash
pip install -r requirements-dev.txt
ruff check . && python -m pytest -q
```

The tests cover parsing of batched TRUST/TD/RTPPM frames, backoff, config validation, ACK-after-send, the no-ACK path on sink failure, poison messages, the console and file sinks, and an end-to-end replay. For the optional tier they also cover the `eventhub` sink alias and its fallback, and the Kafka relay with a fake consumer: commit-after-send, no commit on failure, reconnect and redelivery, and poison messages. None of them need the network, `azure-eventhub` or `confluent-kafka`.
