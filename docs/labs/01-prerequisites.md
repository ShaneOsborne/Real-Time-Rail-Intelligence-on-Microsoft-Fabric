# Lab 01 – Prerequisites and accounts

**Time:** 45 minutes, plus any account approval wait · **Previous:** [Lab 00](00-overview.md) · **Next:** [Lab 02](02-fabric-workspace.md)

## Objectives

Get every account, subscription, tenant setting and tool in place before you build anything.

## 1. Network Rail Open Data (NROD)

1. Register at <https://publicdatafeeds.networkrail.co.uk/>. Accounts are limited (about 1,000 users), so register early.
2. Wait for the account to become **active**. You'll get an email.
3. ~~In **My Feeds**, subscribe to:~~
  * ~~**Train Movements**: *All TOCs* (`TRAIN_MVT_ALL_TOC`)~~
  * ~~**RTPPM** (`RTPPM_ALL`), **VSTP** (`VSTP_ALL`) and **TSR** (`TSR_ALL_ROUTE`) – optional~~
  * ~~**TD**: *All signalling areas* (`TD_ALL_SIG_AREA`) – optional and high volume~~
  * ~~**All Reference Data** – required for CORPUS and SMART downloads (Lab 03)~~
  * ~~**SCHEDULE** – optional~~
4. Make a note of your login email and password. These are `NROD_USERNAME` and `NROD_PASSWORD`.

## 2. Rail Data Marketplace (RDM)

1. Create an account at <https://raildata.org.uk>.
2. Subscribe to **NWR Train Movements**:
   <https://raildata.org.uk/dataProduct/P-826477b8-3789-45e7-85bd-22c4ae9bcfae/overview> (beta).
3. Optionally, subscribe to **Darwin Real Time Train Information (Push)**:
   <https://raildata.org.uk/dataProduct/P-3f10bf96-d8e8-4041-aa5e-d75d82c45c4e/overview>.
4. Open the subscription page and note the **Kafka bootstrap server(s)**, **topic**, **consumer group**,
   **username** and **password**. The security protocol is `SASL_SSL` and the mechanism is `PLAIN`.

## 3. Azure

* An Azure subscription with permission to create resource groups and role assignments (Owner, or Contributor plus User Access Administrator), so Bicep can grant Key Vault and ACR roles.
* Resource providers registered: `Microsoft.App`, `Microsoft.OperationalInsights`, `Microsoft.KeyVault`, `Microsoft.ContainerRegistry` and `Microsoft.ManagedIdentity`.

Run the following command within the 'Cloud Shell' in the Azure Portal to ensure all providers are available 

```bash
for p in Microsoft.App Microsoft.OperationalInsights Microsoft.KeyVault Microsoft.ContainerRegistry Microsoft.ManagedIdentity; do
  az provider register -n $p
done
```

## 4. Microsoft Fabric

* A **Fabric capacity F2 or higher**, or a Fabric trial. The Foundry Fabric tool (Lab 10) needs a **paid F2+** (or P1+) capacity.
* A workspace on that capacity (Lab 02 can create one). You need *Contributor* or above.
* **Tenant settings** (Fabric admin portal). Ask your Fabric admin if you can't change these yourself:
  * Users can create Fabric items (Real-Time Intelligence: Eventhouse, Eventstream, Activator).
  * **Fabric data agent** tenant settings enabled (Copilot and Azure OpenAI-powered features), plus the
    **cross-geo processing** and **cross-geo storage** settings for AI if your capacity region requires them.
  * **Fabric Apps (preview)** workload: *OneLake catalog > Govern > Configurations > Workloads*.
  * Service principals can use Fabric APIs (only if you'll run the scripts as a service principal).
* Capacity region: keep the data agent and its data sources on capacities in the **same region**.

## 5. Azure AI Foundry (Lab 10)

* A Foundry project in the **same tenant** as Fabric, with a model deployment (for example `gpt-4.1-mini`).
* You and your end users need the **Foundry User** RBAC role (formerly *Azure AI User*).

## 6. Tools on your machine

| Tool | Version | Used in |
|---|---|---|
| Azure CLI (`az`) | recent; `az bicep install` | 02, 03, 05b, 06, 12 |
| Python | 3.11+ | 03, 05a, 06, 10 |
| Docker Desktop / Engine with Compose v2.24+ | – | 05a (optional) |
| Node.js and npm | 20+ | 11 |
| Git | – | all |
| GitHub CLI (`gh`) | – | 11 (listed by the Rayfin installation guide) |
| PowerShell 7 | – | if you use the `.ps1` scripts |

The Fabric CLI (`fab`) isn't needed. The scripts call the Fabric REST API with `az rest`.

## 7. Clone the repo and configure

```bash
git clone https://github.com/<you>/Real-Time-Rail-Intelligence-on-Microsoft-Fabric.git
cd Real-Time-Rail-Intelligence-on-Microsoft-Fabric
cp .env.example .env     # then edit .env
az login
```

## 8. Edit the initial values within .env

Check the default values within the .env file, we will modify some of these later as we go through the labs but for the moment ensure the following are populated

Section : Network Rail Open Data (NROD)
- NROD_USERNAME
- NROD_PASSWORD
- NROD_CLIENT_ID

Section : Rail Data Marketplace (RDM) Kafka
- RDM_KAFKA_BOOTSTRAP_SERVERS
- RDM_KAFKA_TOPIC (Ensure you enter the JSON topic)
- RDM_KAFKA_CONSUMER_GROUP
- RDM_KAFKA_USERNAME
- RDM_KAFKA_PASSWORD

## Checkpoint

- [ ] NROD account is active and the feeds are subscribed (including *All Reference Data*)
- [ ] RDM subscription page shows the Kafka connection details
- [ ] `az account show` returns the right subscription
- [ ] You can create items in a Fabric workspace on F2+ or trial capacity
- [ ] `python --version` is 3.11+, `node --version` is 20+, and `docker compose version` works (optional)

## Troubleshooting

| Symptom | Fix |
|---|---|
| NROD account "pending" | Approval can take time. Do Lab 05a with `--replay` in the meantime |
| Can't see the Fabric Apps workload | A Fabric admin must enable it under *Govern > Configurations > Workloads* |
| `az provider register` permission error | Ask a subscription Owner |
