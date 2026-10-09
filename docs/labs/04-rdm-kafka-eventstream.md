# Lab 04 – Ingest RDM Kafka Train Movements with Eventstream

**Time:** 30 minutes · **Previous:** [Lab 03](03-reference-data.md) · **Next:** [Lab 05a](05a-bridge-local.md)

## Objectives

* Connect the **Apache Kafka** source connector in Eventstream to the Rail Data Marketplace *NWR Train Movements* product.
* Land the raw messages in the Eventhouse table **`RdmTrustRaw`** (one dynamic `payload` column), where update policies (Lab 06) parse them.

> **Shared Event Hub mode (optional, [Lab 05c](05c-shared-event-hub.md)).** If your instructor runs the shared Event Hub,
> **don't** add the Apache Kafka source below and you don't need your own RDM account. Instead, add an **Azure Event Hubs** source
> for the `rdm-trust` hub with your own consumer group (Lab 05c, step S2). The destination (`RdmTrustRaw`, `RdmTrustRawMapping`)
> and the checkpoint queries are the same.

## Prerequisites

* Lab 02 (Eventstream `RailEventstreamRdm`) is done.
* The table **`RdmTrustRaw`** and mapping **`RdmTrustRawMapping`** exist ([Lab 02, "Create the raw tables and mappings now"](02-fabric-workspace.md#create-the-raw-tables-and-mappings-now)).
  Check before you start. In a KQL queryset on `RailKQL`, run:

  ```kusto
  .show table RdmTrustRaw ingestion json mappings
  ```

  If it says the table doesn't exist, run `01_tables.kql` and `02_update_policies.kql` first (see Lab 02). **Don't** let the
  Eventstream wizard create the table: it builds its own columns, and the parsing in Lab 06 expects one `payload` column.
* The Kafka details from your RDM subscription page.

## Option A – automated

Not available. The Eventstream topology (sources, destinations, operators) is configured in the portal. This repo
doesn't generate Eventstream definition payloads. Follow Option B.

## Option B – manual (portal)

> Portal labels change from time to time. If a label differs slightly, pick the closest match.

1. Open **RailEventstreamRdm** → **Add source** → **Connect data sources** → **Apache Kafka** → **Connect**.
2. Create a **new connection**:
   * **Bootstrap server**: from RDM (`host:port`; comma-separate multiple brokers)
   * **Connection name**: for example `rdm-kafka`
   * **Authentication kind**: **API Key**. This is the only option offered, and it's how Fabric stores SASL
     username/password credentials:
     * **Key** = your RDM Kafka **consumer username**
     * **Secret** = your RDM Kafka **consumer password**
   * Select **Connect**.

   > There's no separate "username/password" option in the Eventstream Kafka connection. The **Key** and **Secret**
   > are sent as the SASL username and password once you choose `SASL_SSL` / `PLAIN` in the next step.
3. Configure the source:
   * **Topic**: from RDM
   * **Consumer group**: from RDM. Use the exact value RDM issued
   * **Reset auto offset**: `Latest` for live demos, `Earliest` to backfill whatever the broker retains
   * **Security protocol**: `SASL_SSL`
   * **SASL mechanism**: `PLAIN` (not SCRAM)
   * Leave **TLS/mTLS settings** off. RDM's brokers use a publicly trusted certificate.
4. **Next** → **Add** → **Publish**. In **Data preview**, you should see JSON TRUST messages appear (if preview stays empty, see Troubleshooting – check the Eventhouse table instead).
5. **Add destination** → **Eventhouse**:
   * **Data ingestion mode**: *Direct ingestion* (simplest; the Eventhouse does the parsing) or
     *Event processing before ingestion* (if you want to add Eventstream operators).
   * Workspace `RaintIntelligence`, Eventhouse `RailEventhouse`, KQL database `RailKQL`.
   * **Destination table**: Create new table **`RdmTrustRaw`**.
   * **Input data format**: JSON. Choose the existing mapping **`RdmTrustRawMapping`**, which maps the whole record (`$`) to `payload`. If the wizard proposes its own column mapping instead, edit it so that only `payload` (dynamic) is populated from the full record.
6. **Publish**.

### Should Eventstream split arrays?

The update policies handle **both** shapes: a single TRUST message object, or a JSON array (batch) of them, which they expand with `mv-expand`. You don't need an Eventstream operator.

> TODO(verify): The exact RDM message envelope for *NWR Train Movements* may differ from the NROD STOMP body (for example, extra wrapper fields). Check a message in **Data preview**. If TRUST items sit under a wrapper property, change `ExpandTrustRdm()` in `fabric/kql/02_update_policies.kql` to point at that property.

## Checkpoint

```kusto
RdmTrustRaw | take 5;
RdmTrustRaw | summarize n = count() by t = bin(ingestion_time(), 1m) | order by t desc;
TrustMovements | where source == "rdm" | take 10;
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| Source shows authentication errors | Check the connection's **Key** is the RDM consumer username and **Secret** is the RDM consumer password (no spaces). Check the mechanism is `PLAIN` and the protocol is `SASL_SSL`. To change them, edit the connection under **Settings → Manage connections and gateways** |
| Can't find a username/password option | Expected. Use **Authentication kind = API Key**: Key = username, Secret = password |
| Source runs but **Data preview** is empty or errors | Eventstream previews with a consumer group prefixed `preview-`, and the credentials need read access to it. RDM only grants your issued consumer group, so preview may fail even though ingestion works. Check the Eventhouse table (Checkpoint) instead |
| No data, no errors | Check the topic name and consumer group. Use `Latest` and wait a minute; it's a beta feed with no SLA |
| Data in `RdmTrustRaw` but none in `TrustMovements` | Look at the payload shape (see TODO above). Run `.show ingestion failures` |
| Duplicated movements | You're also ingesting `TRAIN_MVT_ALL_TOC` through the bridge. Filter on `source`, or drop one feed (see Lab 00) |
| Only part of the data arrives | Another consumer uses the same RDM consumer group, for example the instructor's RDM relay (Lab 05c) or a second Eventstream | Run only one reader per RDM consumer group |
