# Lab 01 – Prerequisites and accounts

**Time:** 45 minutes, plus any account approval wait · **Previous:** [Lab 00](00-overview.md) · **Next:** [Lab 02](02-fabric-workspace.md)

## Objectives

Get every account, subscription, tenant setting and tool in place before you build anything.

## 1. Network Rail Open Data (NROD)

1. Register at <https://publicdatafeeds.networkrail.co.uk/>. Accounts are limited (about 1,000 users), so register early.
2. Wait for the account to become **active**. You'll get an email.
3. In **My Feeds**, subscribe to:
   * **RTPPM** (`RTPPM_ALL`) – **required for Lab 05a/05b**. It's the feed the bridge brings in by default (national
     performance, one message a minute) and the one Lab 07's PPM alert uses
   * **Train Movements**: *All TOCs* (`TRAIN_MVT_ALL_TOC`) – only if you'll skip Lab 04 (Train Movements from the Rail Data
     Marketplace). Don't bring Train Movements in from both
   * **VSTP** (`VSTP_ALL`) and **TSR** (`TSR_ALL_ROUTE`) – optional
   * **TD**: *All signalling areas* (`TD_ALL_SIG_AREA`) – optional and high volume
   * **All Reference Data** – required for CORPUS and SMART downloads (Lab 03)
   * **SCHEDULE** – optional
4. Make a note of your login email and password. These are `NROD_USERNAME` and `NROD_PASSWORD`.

## 2. Rail Data Marketplace (RDM)

1. Create an account at <https://raildata.org.uk>.
2. Subscribe to **NWR Train Movements** (this is the TRUST feed that fills `TrustMovements`, used by the dashboards and data agent):
   <https://raildata.org.uk/dataProduct/P-826477b8-3789-45e7-85bd-22c4ae9bcfae/overview> (beta).
3. Optionally, subscribe to **Darwin Real Time Train Information (Push)** (forecasts, platforms and reasons; used in the optional [Lab 04b](04b-darwin-push-port.md), parsed into `DarwinLocations`). Each product has its **own** topic and consumer group:
   <https://raildata.org.uk/dataProduct/P-3f10bf96-d8e8-4041-aa5e-d75d82c45c4e/overview>.
4. Open the subscription page and note the **Kafka bootstrap server(s)**, **topic**, **consumer group**,
   **username** and **password**. The security protocol is `SASL_SSL` and the mechanism is `PLAIN`.
   In Fabric (Lab 04) these go into a connection of type **API Key**: **Key** = username, **Secret** = password.

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

* A **Fabric capacity** sized for the feeds you'll run (**estimates** – see [Capacity planning and sizing](../capacity-planning.md)):
  * **Single builder, Train Movements only:** F2 is the minimum and works, but it's tight. F4 is comfortable.
  * **Adding Darwin (Lab 04b) and/or the NROD bridge (Labs 05a/05b):** F4 recommended. Two always-on Kafka Eventstreams can throttle an F2.
  * **Classroom:** see [Classrooms and shared capacities](../capacity-planning.md#classrooms-and-shared-capacities). Capacity grows
    roughly in line with the number of student pipelines.
  * A Fabric trial works for most labs. The Foundry Fabric tool (Lab 10) needs a **paid F2+** (or P1+) capacity.
* **Install the [Microsoft Fabric Capacity Metrics app](https://learn.microsoft.com/en-us/fabric/enterprise/metrics-app)**
  (a capacity admin installs it). You'll use it to check how much capacity the Eventstreams and Eventhouse use, and to spot
  throttling. Consider setting a capacity alert too (Capacity Overview Events in Real-Time hub).
* A workspace on that capacity (Lab 02 can create one). You need *Contributor* or above.
* **Tenant settings** (Fabric admin portal). Ask your Fabric admin if you can't change these yourself:
  * Users can create Fabric items (Real-Time Intelligence: Eventhouse, Eventstream, Activator).
  * **Fabric data agent** tenant settings enabled (Copilot and Azure OpenAI-powered features), plus the
    **cross-geo processing** and **cross-geo storage** settings for AI if your capacity region requires them.
  * **Fabric Apps (preview)** (Lab 11): *Admin portal > Tenant settings > Fabric Apps (preview)* → **Enabled**, for the whole
    organisation or a security group that includes every lab user. Allow a few minutes to propagate. Check it worked: in the
    workspace, **+ New item** should list **App (preview)**.
  * Service principals can use Fabric APIs (only if you'll run the scripts as a service principal).
* Capacity region: keep the data agent and its data sources on capacities in the **same region**.
* **Capacity region for Lab 11 (Rayfin app).** Fabric Apps (preview) isn't available in every Fabric region. Even with the
  tenant setting on, **App (preview)** won't appear under *New item* if the workspace's capacity is in an unsupported region.
  Check this **now**, not at Lab 11: in a workspace on your capacity, **+ New item** → search **App (preview)**.
  * Listed: you're fine.
  * Not listed (and the tenant setting is on): you need a **second capacity in a region that supports Fabric Apps** for a
    separate app workspace. See [Lab 11 – If App (preview) isn't available in your region](11-rayfin-app.md#if-app-preview-isnt-available-in-your-region).
    The rest of the labs stay on your main capacity. A trial capacity is created in your tenant's home region, so it won't help here.
  * If you can't get one, skip Lab 11. Labs 00–10 and 12 don't need Fabric Apps.

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
- [ ] You can create items in a Fabric workspace on a capacity sized for your scenario (F2 minimum) or a trial
- [ ] The Capacity Metrics app is installed and shows your capacity
- [ ] (Lab 11 only) **+ New item → App (preview)** is listed in a workspace on a capacity you can use (tenant setting on **and** a supported region)
- [ ] `python --version` is 3.11+, `node --version` is 20+, and `docker compose version` works (optional)

## Troubleshooting

| Symptom | Fix |
|---|---|
| NROD account "pending" | Approval can take time. Do Lab 05a with `--replay` in the meantime |
| Can't see **App (preview)** under *New item*, or `rayfin up` fails with *403 Forbidden – The feature is not available* | Two causes. 1) The tenant setting is off: a Fabric admin must enable *Admin portal > Tenant settings > Fabric Apps (preview)* for you, then wait a few minutes. 2) The workspace's capacity region doesn't support Fabric Apps yet: use an app workspace on a capacity in a supported region (Lab 11) or skip Lab 11 |
| `az provider register` permission error | Ask a subscription Owner |

## 8. Shared Key Vault for credentials (needed from Lab 03)

Lab 03 runs a Fabric notebook that downloads reference data with your NROD login. Rather than typing
the password into the notebook, store it in a Key Vault **now**. Lab 05b later re-uses the **same vault**
for the bridge, so you only ever create one.

> This step is optional. If you skip it, Lab 03 lets you type the credentials into the notebook for that
> session only, and Lab 05b creates the vault for you.

### Option A – automated

```bash
# .env must contain AZ_RESOURCE_GROUP, AZ_LOCATION, NAME_PREFIX, NROD_USERNAME, NROD_PASSWORD
./scripts/create-keyvault.sh        # or: ./scripts/create-keyvault.ps1
```

The script:
1. Creates the resource group (if needed).
2. Deploys `infra/keyvault.bicep`: a Key Vault in **RBAC mode** with 7-day soft delete, and grants you
   **Key Vault Secrets Officer** (read and write secrets).
3. Writes the secrets `nrod-username` and `nrod-password`.
4. Prints `KEY_VAULT_NAME` and `KEY_VAULT_URL`. **Copy both into `.env`.**

The vault name is generated from the resource group and `NAME_PREFIX`, and matches the name `infra/main.bicep`
uses in Lab 05b. **Keep `AZ_RESOURCE_GROUP` and `NAME_PREFIX` unchanged between labs**, otherwise Lab 05b
creates a second vault.

### Option B – manual (portal)

1. Create a resource group, for example `rg-rail-fabric-rti` in `uksouth`.
2. **Create a resource → Key Vault**:
   * **Access configuration:** *Azure role-based access control* (not access policies).
   * **Days to retain deleted vaults:** `7` (this can't be changed later, and Lab 05b's template expects 7).
   * **Networking:** public access *enabled* (Fabric notebooks reach it over the public endpoint).
3. In the vault, **Access control (IAM) → Add role assignment → Key Vault Secrets Officer** → yourself.
4. **Secrets → Generate/Import**: create `nrod-username` (your NROD email) and `nrod-password`.
5. In `.env`, set `KEY_VAULT_NAME` to the vault's name and `KEY_VAULT_URL` to its **Vault URI**
   (for example `https://<name>.vault.azure.net/`). Setting `KEY_VAULT_NAME` makes Lab 05b re-use your vault.

### Checkpoint

```bash
az keyvault secret show --vault-name <KEY_VAULT_NAME> -n nrod-username --query value -o tsv
```

You should see your NROD email. If you get *Forbidden*, wait a few minutes for the role assignment to apply.
