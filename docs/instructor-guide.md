# Instructor guide – running the labs as a class

**Who this is for:** the person who sets up and runs a classroom session. Students follow the
[Student guide](student-guide.md) instead. Working alone with your own accounts? Use the solo path in the
[README](../README.md#choose-your-path).

In a class, **you** own all the external connections: one NROD account, one RDM subscription, one shared Azure Event Hubs
namespace and one reference-data Lakehouse. Students build their own Fabric pipeline on top. They don't need NROD or RDM
accounts, or an Azure subscription.

```
 NROD (STOMP) ──► bridge (Container Apps) ──┐
                                            ├──► Azure Event Hubs ──► student01 Eventstream ──► student01 Eventhouse …
 RDM (Kafka) ───► RDM relay (Container Apps)┘   (nrod-feed, rdm-trust;  student02 Eventstream ──► student02 Eventhouse …
                                                one consumer group each)
 Reference data ─► instructor Lakehouse ──(OneLake shortcut, read-only)──► each student's KQL database
```

## 1. Two weeks before

| Task | Where | Notes |
|---|---|---|
| Register for NROD and subscribe to the feeds, including *All Reference Data* | [Lab 01 §1](labs/01-prerequisites.md#1-network-rail-open-data-nrod) | Approval can take days |
| Subscribe to RDM *NWR Train Movements* (and *Darwin Push Port* if you'll demo Lab 04b) | [Lab 01 §2](labs/01-prerequisites.md#2-rail-data-marketplace-rdm) | One subscription feeds the whole class via the relay |
| Azure subscription and resource providers | [Lab 01 §3](labs/01-prerequisites.md#3-azure) | Only you need Azure |
| **Size and buy the Fabric capacity** | [Capacity planning](capacity-planning.md#classrooms-and-shared-capacities) | ~1.5–2 CU per student (10 students ≈ F16–F32). The Foundry tool (Lab 10) needs a **paid** F2+ |
| **Tenant settings** (Fabric admin) | [Lab 01 §4](labs/01-prerequisites.md#4-microsoft-fabric) | Create Fabric items, data agent / Copilot, cross-geo AI settings, Fabric Apps (preview). Enable them for a security group that contains every student |
| **Check Fabric Apps works in your capacity's region** | [Lab 01 §4](labs/01-prerequisites.md#4-microsoft-fabric) | **+ New item → App (preview)**. If it isn't listed, plan the [Lab 11 workaround](labs/11-rayfin-app.md#if-app-preview-isnt-available-in-your-region), run Lab 11 as a demo, or drop it |
| **Foundry project** with a model deployment | [Lab 01 §5](labs/01-prerequisites.md#5-azure-ai-foundry-lab-10) | One shared project. Give every student the **Foundry User** role |
| Student accounts | Entra ID | Each student needs a Fabric licence, and to be in the security groups above |

## 2. The day before

Do these in order, from your own clone with your own `.env`.

1. **Your workspace.** [Lab 02](labs/02-fabric-workspace.md) – for example `rail-instructor`. It holds the reference Lakehouse and your demo pipeline.
2. **Key Vault.** [Lab 01 §8](labs/01-prerequisites.md#8-shared-key-vault-for-credentials-needed-from-lab-03).
3. **Reference data.** [Lab 03](labs/03-reference-data.md) Option A2 (notebook) into **your** `RailLakehouse`, then share it:
   open `RailLakehouse` → **Share** → add the student security group → tick **Read all OneLake data** → **Grant**.
   Students shortcut to it in [Lab 03 Option C](labs/03-reference-data.md#option-c--classroom-shortcut-to-the-instructors-reference-data).
   *Check this in your tenant with one test student before the class.*
4. **Bridge.** [Lab 05a](labs/05a-bridge-local.md) to test locally, then [Lab 05b](labs/05b-bridge-azure-container-apps.md) to deploy it.
5. **Shared Event Hub, consumer groups and RDM relay.** [Lab 05c – instructor parts](labs/05c-shared-event-hub.md#option-a--automated-instructor):
   set `STUDENT_CONSUMER_GROUP_COUNT` to the class size (max 19 per namespace), run `create-eventhub`, then
   `BRIDGE_TARGET=eventhub DEPLOY_RDM_RELAY=true ./scripts/deploy-bridge.sh`. Stop any Apache Kafka source in your own
   workspace that uses the same RDM consumer group.
6. **Student workspaces (optional but recommended).** Either let students create their own in Lab 02 (they need
   permission to assign workspaces to the capacity: *Capacity settings → Contributor permissions*), or create them for them:

   ```bash
   # One workspace per student, with the empty items; then add the student as Admin in the portal (Manage access)
   for n in 01 02 03; do
     FABRIC_WORKSPACE_ID= FABRIC_WORKSPACE_NAME="rail-rti-student$n" ./scripts/fabric-setup.sh
   done
   ```

   Variables set on the command line win over `.env`. Note each workspace ID for the handout.
7. **Dry run as a student.** Using one test account, follow the [Student guide](student-guide.md) up to the Lab 05c student
   checkpoint and confirm rows arrive in `RawFeed` and `RdmTrustRaw`.

## 3. The student handout

Send each student their own copy, **privately** (not in a repo, Teams channel or slide):

| Item | Example | From |
|---|---|---|
| Fabric workspace name (and ID if you pre-created it) | `rail-rti-student07` | Step 2.6 |
| Event Hubs namespace | `railrti-eh-xxxx` | `create-eventhub` output |
| Key name and key | `students-listen` / `…` | `create-eventhub` output (Listen only) |
| **Their** consumer group | `student07` | Step 2.5 |
| Reference Lakehouse | workspace `rail-instructor` → `RailLakehouse` → `Tables/locations` | Step 2.3 |
| Foundry project endpoint and model deployment | `https://…/api/projects/…`, `gpt-4.1-mini` | Foundry portal |
| Their agent name | `rail-network-agent-student07` | Lab 10 (unique per student in the shared project) |

## 4. During the class

* Watch the capacity in the **Capacity Metrics** app. If it throttles, see [Capacity planning](capacity-planning.md).
* Common student problems: using `$Default` or a classmate's consumer group (data is split between them); letting the
  Eventstream wizard create the table (Lab 06 needs the one `payload` column); forgetting Lab 02's raw tables and mappings.
* Overnight: you can pause the capacity. Event Hubs buffers for 7 days and student Eventstreams catch up
  ([Lab 05c – overnight pause](labs/05c-shared-event-hub.md#overnight-pause-checkpoint)). Keep the bridge and relay running.

## 5. After the class

1. Students run their part of [Lab 12](labs/12-cleanup.md#classroom-students) (delete their workspace).
2. **Rotate the `students-listen` key**, or delete the namespace ([Lab 05c – Clean-up](labs/05c-shared-event-hub.md#clean-up)).
3. Run [Lab 12](labs/12-cleanup.md) in full for your resources, and scale the capacity back down or pause it.
4. Remove Foundry User from students if the project stays.
