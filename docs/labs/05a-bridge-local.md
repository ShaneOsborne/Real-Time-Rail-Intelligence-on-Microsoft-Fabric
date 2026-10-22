# Lab 05a – Run the STOMP bridge locally (venv and Docker)

**Time:** 40 minutes · **Previous:** [Lab 04](04-rdm-kafka-eventstream.md) · **Next:** [Lab 05b](05b-bridge-azure-container-apps.md)

> **Path:** Solo ✅ · Instructor ✅ (test before the class) · **Classroom student – skip.**

## Objectives

* Run the bridge offline first (replaying sample messages), then against live NROD, using three sinks in turn:
  **console**, then **file (JSONL)**, then **eventstream**.
* Do it both ways: in a **Python virtual environment** and in **Docker / Docker Compose**.
* Wire the bridge to the Fabric **Eventstream custom endpoint** and on to the Eventhouse `RawFeed` table.
* *Optional:* send to the shared **Azure Event Hub** instead (sink `eventhub`, [Lab 05c](05c-shared-event-hub.md)), and run the RDM Kafka relay locally.

## Prerequisites

* Python 3.11+ on your `PATH` (check with `python --version` or `python3 --version`) and, if you want it, Docker with Compose v2.24+.
* For live data: an active NROD account with the feeds subscribed (Lab 01), and `NROD_USERNAME` / `NROD_PASSWORD` in the repo-root `.env`.
* For the eventstream sink: the `RawFeed` table and `RawFeedMapping` exist (Lab 02, "Create the raw tables and mappings now").
* Run the scripts from the **repo root** (the folder that contains `scripts/` and `.env`).
* Your NROD account is subscribed to **RTPPM** (*My Feeds*, see "What this lab brings in" below).

> ⚠️ **One connection per NROD account / client-id.** Stop the local bridge before you start the Azure one (Lab 05b), and
> the other way round. Two consumers with the same durable `client-id` keep kicking each other off.

## What this lab brings in

You already have **Train Movements** from the Rail Data Marketplace (Lab 04). This lab adds a feed that's **only** available
from Network Rail Open Data: **RTPPM**, the national public performance measure (one message a minute). It's parsed into
**`RtppmNational`** and used by the PPM alert in Lab 07. Bringing Train Movements in again would duplicate every movement in
`TrustMovements`.

**Do this before you run anything:**

1. Sign in at <https://publicdatafeeds.networkrail.co.uk> → **My Feeds** → tick **RTPPM** → **Save**. (It can take a few
   minutes to become active.)
2. Open the repo-root `.env` and make sure the topics line reads exactly:

   ```
   NROD_TOPICS=RTPPM_ALL
   ```

   If you created `.env` from an older `.env.example`, it may say `TRAIN_MVT_ALL_TOC`. Change it.
3. Check it (from the repo root). You should see only `NROD_TOPICS=RTPPM_ALL`:

   ```bash
   grep NROD_TOPICS .env          # PowerShell: Select-String NROD_TOPICS .env
   ```

   When you run step 3 of Option A (live → console), the first log lines show `subscribed` with `RTPPM_ALL`.

**Other choices** (not needed for the labs):

| If you… | Set `NROD_TOPICS` to | Notes |
|---|---|---|
| Skipped Lab 04 (no Rail Data Marketplace) | `TRAIN_MVT_ALL_TOC,RTPPM_ALL` | Train Movements then comes from NROD. Also subscribe to *Train Movements – All TOCs* |
| Want berth-level train positions | `RTPPM_ALL,TD_ALL_SIG_AREA` | About **10×** the Train Movements volume. Parsed into `TdEvents`. Check capacity ([capacity planning](../capacity-planning.md)) |
| Want late-notice schedules or speed restrictions | add `VSTP_ALL` and/or `TSR_ALL_ROUTE` | These land in `RawFeed` only. The labs don't parse them |

## How it works

```
NROD ActiveMQ (STOMP :61618)
  └─ CONNECT  client-id=<username>, heart-beat 15000,15000
  └─ SUBSCRIBE /topic/RTPPM_ALL  ack=client-individual  activemq.subscriptionName=rail-fabric-rti-RTPPM_ALL
       └─ MESSAGE (JSON; TRUST/TD arrive as batches) ─► split into envelope events ─► sink.send() ─► ACK (only on success)
                                                                     └─ failure ─► no ACK ─► reconnect with backoff 1,2,4,8,16…s
```

## Option A – automated

Work through **A1 → A2 → A3** in order. Each stage builds on the previous one. Stop a running bridge with **Ctrl+C**
before you start the next row: only one connection per NROD account is allowed.

You **don't need to create the virtual environment yourself**. The `venv` and `test` modes create `src/bridge/.venv` on the
first run, install the dependencies and activate it. This works in Linux/macOS shells, **Git Bash on Windows** and PowerShell.

> **Windows:** in **Git Bash** use the `.sh` scripts; in **PowerShell** use the `.ps1` scripts. Don't mix a virtual environment
> created by one with the other – if you switch, delete `src/bridge/.venv` and let the script create it again.

### A1. Local checks (no Fabric needed)

| # | Step | What it proves | bash | PowerShell |
|---|---|---|---|---|
| 1 | Unit tests | Python and dependencies work (no network) | `./scripts/run-local.sh test` | `./scripts/run-local.ps1 -Mode test` |
| 2 | Offline replay → console | Output format, using bundled samples (no NROD) | `./scripts/run-local.sh venv console --replay` | `./scripts/run-local.ps1 -Mode venv -Sink console -Replay` |
| 3 | Live → console | Your NROD login and topics work. RTPPM sends **one message a minute** – wait at least 60–90 seconds | `./scripts/run-local.sh venv console` | `./scripts/run-local.ps1 -Mode venv -Sink console` |
| 4 | Live → file | Messages are written to `src/bridge/out/messages.jsonl` | `./scripts/run-local.sh venv file` | `./scripts/run-local.ps1 -Mode venv -Sink file` |

### A2. Connect to Fabric (portal set-up, then run)

The Eventstream side is **always set up in the portal** – there's no script for it. Do this once:

1. Open **RailEventstreamNrod** → **Add source** → **Custom endpoint** → name it `nrod-bridge` → **Add** → **Publish**.
2. Select the custom endpoint source → **Details** → the **Event Hub** protocol tab → **SAS Key Authentication** → copy the
   **Connection string–primary key**. It looks like
   `Endpoint=sb://…servicebus.windows.net/;SharedAccessKeyName=…;SharedAccessKey=…;EntityPath=…`.
   (The **Kafka** tab gives the equivalent Kafka settings. The bridge uses the Event Hub protocol.)
3. Paste it into the repo-root `.env` on **one line**: `EVENTSTREAM_CONNECTION_STRING=Endpoint=sb://…;EntityPath=…`.
   Quotes are optional. **Never commit `.env`.**
4. **Add destination** → **Eventhouse** → **Direct ingestion** → `RailEventhouse` / **`RailKQL`** (not the default database
   named after the Eventhouse) → **Save** → **Publish**. Then in **Live view**, select **Configure** on the Eventhouse node. In
   the **Get data** wizard choose the **existing** table **`RawFeed`** (not *New table*), format **JSON**, and the **existing
   mapping** **`RawFeedMapping`** → **Finish**. This is the same flow as [Lab 04, steps 5–6](04-rdm-kafka-eventstream.md); the
   table and mapping must already exist (Lab 02, "Create the raw tables and mappings now").

Then run:

| # | Step | bash | PowerShell |
|---|---|---|---|
| 5 | Live → Eventstream | `./scripts/run-local.sh venv eventstream` | `./scripts/run-local.ps1 -Mode venv -Sink eventstream` |

After a minute or two, check the [Checkpoint](#checkpoint) queries.

### A3. Docker (optional alternative to the virtual environment)

The same bridge in a container – also the image that Lab 05b deploys. Needs the `.env` from A2 for the eventstream sink.

| # | Step | bash | PowerShell |
|---|---|---|---|
| 6 | Offline replay (Docker) | `./scripts/run-local.sh docker console --replay` | `./scripts/run-local.ps1 -Mode docker -Replay` |
| 7 | Live → Eventstream (Docker) | `./scripts/run-local.sh docker eventstream` | `./scripts/run-local.ps1 -Mode docker -Sink eventstream` |

### A4. Optional: shared Event Hub mode ([Lab 05c](05c-shared-event-hub.md))

Needs the Event Hub from Lab 05c and its connection strings in `.env` (see [B3b](#b3b-optional-send-to-the-shared-event-hub-sink-eventhub)).

| Step | bash | PowerShell |
|---|---|---|
| Live → shared Event Hub `nrod-feed` (venv) | `./scripts/run-local.sh venv eventhub` | `./scripts/run-local.ps1 -Mode venv -Sink eventhub` |
| RDM Kafka relay → console (venv) | `./scripts/run-local.sh venv console --kafka` | `./scripts/run-local.ps1 -Mode venv -Sink console -Kafka` |
| RDM Kafka relay → Event Hub `rdm-trust` (Docker) | `./scripts/run-local.sh docker eventhub --kafka` | `./scripts/run-local.ps1 -Mode docker -Sink eventhub -Kafka` |

## Option B – manual, step by step

### B1. Virtual environment and offline replay

```bash
cd src/bridge
python -m venv .venv                       # use python3 if 'python' isn't found
source .venv/bin/activate                  # Linux / macOS
# source .venv/Scripts/activate            # Windows Git Bash
# .venv\Scripts\Activate.ps1               # Windows PowerShell
pip install -r requirements-dev.txt
python -m pytest -q                        # all tests pass, no network needed
python -m rail_bridge --source replay --replay-file tests/fixtures/replay_frames.json --sink console
```

You'll see seven JSON lines: four TRUST events (types 0001, 0003, 0003 and 0002), two TD events and one RTPPM event.

### B2. Live NROD → console → file

Set `NROD_USERNAME`, `NROD_PASSWORD` and `NROD_TOPICS=RTPPM_ALL` (see "What this lab brings in") in the repo-root `.env`, then load them into your shell
(`set -a; source ../../.env; set +a`). In PowerShell, run `./scripts/run-local.ps1` instead, which loads `.env` for you.

```bash
python -m rail_bridge --check-config
python -m rail_bridge --sink console       # Ctrl+C stops it gracefully
python -m rail_bridge --sink file --output-file out/messages.jsonl
curl -s localhost:8080/metrics             # frames_received, events_sent, frames_acked …
```

### B3. Wire to Eventstream (custom endpoint)

1. Do the portal set-up in [A2, steps 1–4](#a2-connect-to-fabric-portal-set-up-then-run) (custom endpoint, connection string in
   `.env`, Eventhouse destination with `RawFeed` / `RawFeedMapping`). It's the same for both options.
2. Load `.env` into your shell again if you changed it (see B2), then run the bridge with the eventstream sink:

```bash
python -m rail_bridge --sink eventstream
```

> If you load `.env` with `set -a; source ../../.env; set +a`, put the connection string in **double quotes** – otherwise the
> shell treats each `;` as the end of a command. The repo scripts read `.env` safely and don't need the quotes.

### B3b. Optional: send to the shared Event Hub (sink `eventhub`)

In shared mode ([Lab 05c](05c-shared-event-hub.md)) the instructor's bridge sends to an Azure Event Hub instead of an Eventstream.
`eventhub` is the same Event Hubs producer as `eventstream`; only the connection string differs.

1. Copy the `nrod-feed` hub's **bridge-send** connection string (Event Hubs namespace → `nrod-feed` → *Shared access policies* →
   `bridge-send`, or the Key Vault secret `eventhub-nrod-connection-string`) into `.env` as `EVENTHUB_CONNECTION_STRING=…`.
   If it's empty, the bridge falls back to `EVENTSTREAM_CONNECTION_STRING`. **Never commit it.**
2. Run `python -m rail_bridge --sink eventhub`.

The **RDM Kafka relay** runs from the same code with `--source kafka` (or `BRIDGE_SOURCE=kafka`). It reads `RDM_KAFKA_*` from `.env`,
forwards each message value unchanged, and commits offsets only after a successful send. The scripts map
`EVENTHUB_RDM_CONNECTION_STRING` (the `rdm-trust` send string) to the relay; the relay never falls back to the Eventstream string.

```bash
EVENTHUB_CONNECTION_STRING="$EVENTHUB_RDM_CONNECTION_STRING" python -m rail_bridge --source kafka --sink eventhub
```

> Only one consumer may use an RDM consumer group at a time. Stop the local relay before the Azure one starts (and pause your
> Lab 04 Kafka source if it uses the same group).

### B4. Docker / Docker Compose

```bash
cd src/bridge
docker compose --profile offline up --build replay                  # offline demo, health on :8081
mkdir -p out && chmod a+rwx out                                     # the container runs as uid 10001
BRIDGE_SINK=file docker compose up --build bridge                    # reads ../../.env
BRIDGE_SINK=eventstream docker compose up --build -d bridge
docker compose logs -f bridge
curl -s localhost:8080/readyz
docker compose down
```

Plain Docker, without Compose:

```bash
docker build -t rail-bridge:local src/bridge
docker run --rm --env-file .env -e BRIDGE_SINK=eventstream -p 8080:8080 rail-bridge:local
```

## Checkpoint

* Console and file sinks: JSON envelope lines with `feed`, `msg_type` and `payload`.
* `/metrics`: `frames_acked` increases, and `send_failures` stays at 0.
* In Fabric:

```kusto
RawFeed | summarize events = count(), last = max(received_utc) by feed, topic      // expect feed = rtppm, topic = RTPPM_ALL
RtppmNational | top 5 by snapshot_time desc                                         // national PPM, one row a minute
TrustMovements | summarize rows = count() by source                                 // only "rdm" – no "nrod" rows means no duplicates
```

> If `RawFeed` has `rtppm` rows but `RtppmNational` stays empty, the RTPPM field names may differ from what `ParseRtppm()`
> expects (they're marked *verify* in `02_update_policies.kql`). Run `RawFeed | where feed == "rtppm" | take 1 | project payload`
> and compare it with the function.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `.venv/bin/activate: No such file or directory` (Windows Git Bash) | Windows Python puts the activate script in `.venv/Scripts` | Update `scripts/run-local.sh` (this version handles both), or delete `src/bridge/.venv` and re-run. Manually: `source .venv/Scripts/activate` |
| `Python 3.11+ not found` / `python3` opens the Microsoft Store | The Store alias isn't a real Python | Install Python 3.11+ from python.org (tick *Add to PATH*), or turn off the python *App execution aliases* in Windows Settings |
| `EVENTSTREAM_CONNECTION_STRING is required for BRIDGE_SINK=eventstream` | The A2 portal set-up hasn't been done, or the value isn't in the repo-root `.env` | Do [A2](#a2-connect-to-fabric-portal-set-up-then-run) steps 1–3. Check the line is in `.env` (not `.env.example`) and not commented out |
| Eventstream sink fails to connect or authenticate although the string is set | Only part of the string was loaded (for example `source .env` without quotes cut it at the first `;`), or it was split over two lines | Keep it on one line. Use the repo scripts (they read `.env` safely), or quote the value if you `source` it yourself |
| `connection failed … Login failed` | Wrong credentials or account not active | Check them on the NROD portal |
| Repeated disconnects every few seconds | Another process is using the same `client-id` | Stop the other bridge, or set a unique `NROD_CLIENT_ID` (both still count against one account) |
| Connected but no messages | Not subscribed to that feed in *My Feeds*, or you haven't waited a full minute (RTPPM sends once a minute) | Check *My Feeds* → **RTPPM**. Wait 60–90 seconds |
| `TrustMovements` has `source == "nrod"` rows as well as `rdm` | An earlier run used `NROD_TOPICS=TRAIN_MVT_ALL_TOC` (the old default) | Set `NROD_TOPICS=RTPPM_ALL`, restart the bridge, then remove the duplicates (below) |
| Gap after downtime | NROD buffers durable messages for only about 5 minutes | Keep the bridge running. Use Container Apps (05b) for 24×7 |
| `Eventstream send failed … Unauthorized` | Wrong or rotated SAS key, or `EntityPath` missing | Copy the connection string again. Set `EVENTSTREAM_ENTITY_NAME` if there's no `EntityPath` |
| `Event Hub send failed …` (sink `eventhub`) | Same causes, for the shared Event Hub | Use the hub-level `bridge-send` connection string. Set `EVENTHUB_NAME` if there's no `EntityPath` |
| Relay: `EVENTHUB_CONNECTION_STRING is required` | `EVENTHUB_RDM_CONNECTION_STRING` isn't set (the relay doesn't fall back to the Eventstream string) | Set it in `.env`, or export `EVENTHUB_CONNECTION_STRING` before running `python -m rail_bridge --source kafka` |
| `PermissionError` writing `out/` in Docker | Host directory isn't writable by uid 10001 | `chmod a+rwx out` |
| Events in `RawFeed` but parsed tables empty | Update policies aren't applied | Run Lab 06 (`apply_kql.py`), then `.show ingestion failures` |

### Removing duplicate Train Movements from an earlier run

If you ran the bridge with `TRAIN_MVT_ALL_TOC` before, delete the NROD copies so only the Lab 04 (RDM) data remains. Run each
command on its own in a KQL queryset on `RailKQL`:

```kusto
.delete table TrustMovements records <| TrustMovements | where source == "nrod"
```

```kusto
.delete table TrustActivations records <| TrustActivations | where source == "nrod"
```

```kusto
.delete table TrustCancellations records <| TrustCancellations | where source == "nrod"
```

```kusto
.delete table TrustOtherEvents records <| TrustOtherEvents | where source == "nrod"
```

```kusto
.delete table RawFeed records <| RawFeed | where feed == "trust"
```

Materialized views built on `TrustMovements` (Lab 06) pick up the change automatically.
