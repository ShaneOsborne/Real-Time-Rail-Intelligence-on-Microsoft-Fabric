# Solo path – build it all yourself

**Who this is for:** one person with their own NROD and RDM accounts, Azure subscription and Fabric capacity. You run every
connection yourself. In a class? Use the [student path](../student/README.md). Setting up a class? Use the
[instructor path](../instructor/README.md).

Read [Start here](../start-here.md) first (about 20 minutes): architecture, costs, licensing and preview caveats.

## Part 1 – get data in

Follow these in order.

| Page | What it covers | Time | Automated? |
|---|---|---|---|
| [Solo 1.1 – Prerequisites and accounts](1.1-prerequisites.md) | NROD, RDM, Azure, Fabric, tenant settings, Foundry region, tools, Key Vault | 45 min (+ approval wait) | Key Vault: ✅ `create-keyvault.sh/.ps1` |
| [Solo 1.2 – Fabric workspace](1.2-fabric-workspace.md) | Workspace, Eventhouse, KQL database, Lakehouse, Eventstreams, raw tables | 20 min | ✅ `fabric-setup.sh/.ps1` |
| [Solo 1.3 – Reference data](1.3-reference-data.md) | CORPUS, SMART, NaPTAN → Lakehouse and KQL | 30 min | ✅ `load_reference_data.py` / notebook |
| [Solo 1.4 – RDM Train Movements](1.4-rdm-kafka-eventstream.md) | Eventstream Apache Kafka source → `RdmTrustRaw` | 30 min | Manual (portal) |
| [Solo 1.5 – Darwin Push Port](1.5-darwin-push-port.md) (optional) | Forecasts and platforms → `DarwinLocations` | 25 min | Manual (portal); KQL via `apply_kql.py` |
| [Solo 1.6 – Bridge, locally](1.6-bridge-local.md) | STOMP bridge in venv and Docker: console → file → Eventstream | 40 min | ✅ `run-local.sh/.ps1` |
| [Solo 1.7 – Bridge on Azure](1.7-bridge-azure.md) | Bridge on Azure Container Apps (Bicep) | 30 min | ✅ `deploy-bridge.sh/.ps1` |
| [Solo 1.8 – Shared Event Hub](1.8-shared-event-hub.md) (optional) | Buffer the feeds while your capacity is paused overnight (`EVENTHUB_AUTH=entra` if a policy blocks keys) | 30 min | ✅ `create-eventhub.sh/.ps1`; Eventstream source manual |

## Then continue with Part 2

Go on to the shared build: [Part 2 – the build](../build/README.md), starting with
[Lab 2.1 – KQL transformations](../build/2.1-kql-transformations.md).
