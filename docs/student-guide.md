# Student guide – classroom path

**Who this is for:** students in an instructor-led class that uses the **shared Event Hub**. Your instructor runs the
connections to Network Rail and the Rail Data Marketplace, so you **don't** need NROD or RDM accounts, an Azure
subscription, Docker or the bridge.

Working alone with your own accounts? Use the solo path in the [README](../README.md#choose-your-path) instead.

## Before you start

Get your **handout** from the instructor. It has your workspace name, the Event Hubs namespace, key name and key, **your own
consumer group**, the reference Lakehouse location and the Foundry details. Keep the key private.

## Your route through the labs

Follow these in order. Each lab page also has a **Path** line that says what to do in it.

| Step | Lab | What you do | Skip |
|---|---|---|---|
| 1 | [00 Overview](labs/00-overview.md) | Read it | The bridge hosting and capacity sections are for the instructor |
| 2 | [01 Prerequisites](labs/01-prerequisites.md#classroom-students) | **Only** the *Classroom students* section: Fabric access check, tools, clone and `.env` | NROD, RDM, Azure, Key Vault (§1–3, §5, §8) |
| 3 | [02 Workspace](labs/02-fabric-workspace.md) | Create your workspace and items, **including the raw tables and mappings** | – |
| 4 | [03 Reference data](labs/03-reference-data.md#option-c--classroom-shortcut-to-the-instructors-reference-data) | **Option C** only: shortcut to the instructor's reference data | Options A1, A2, B (they need an NROD login) |
| – | ~~04, 04b, 05a, 05b~~ | **Skip.** The instructor runs these for the class | All of them |
| 5 | [05c Shared Event Hub](labs/05c-shared-event-hub.md#student-steps-each-student-in-their-own-workspace) | **Student steps** S1, S2 and the student checkpoint | Everything marked *instructor* |
| 6 | [06 KQL transformations](labs/06-kql-transformations.md) | All | – |
| 7 | [07 Activator](labs/07-activator-alerts.md) | All | – |
| 8 | [08 Dashboard and Power BI](labs/08-dashboard-powerbi.md) | All | – |
| 9 | [09 Fabric data agent](labs/09-fabric-data-agent.md) | All | – |
| 10 | [10 Foundry agent](labs/10-foundry-agent.md) | All, in the **shared** Foundry project, with **your own** agent name | Creating a Foundry project |
| 10b | [10b Live semantic model](labs/10b-live-semantic-model.md) | Before Lab 11: your own `RailLiveMap` model | – |
| 11 | [11 Rayfin app](labs/11-rayfin-app.md) | If your instructor says Fabric Apps works in your region | – |
| 11b | [11b Azure Maps map](labs/11b-azure-maps.md) | Optional: steps 3–6, with the token your instructor gives you | Steps 1–2 (instructor) |
| 12 | [12 Clean-up](labs/12-cleanup.md#classroom-students) | The *Classroom students* section only | Deleting Azure resources |

## Settings for your `.env`

```bash
FABRIC_WORKSPACE_NAME=rail-rti-student07   # from the handout
FABRIC_WORKSPACE_ID=                       # from the handout if the instructor created the workspace, else leave empty
FABRIC_CAPACITY_ID=                        # only if you create the workspace yourself (ask the instructor)
KUSTO_QUERY_URI=                           # printed by Lab 02
FOUNDRY_PROJECT_ENDPOINT=                  # from the handout
FOUNDRY_MODEL_DEPLOYMENT_NAME=             # from the handout
FOUNDRY_AGENT_NAME=rail-network-agent-student07
```

Leave the `NROD_*`, `RDM_*`, `AZ_*`, `KEY_VAULT_*` and `EVENTHUB_*` values empty. The Event Hubs key goes into the
Eventstream source in the portal, not into `.env`.

## Golden rules

* Use **your own** consumer group (for example `student07`). Never `$Default` and never a classmate's: the events are
  split between everyone reading the same group.
* Don't let an Eventstream wizard create tables. Use the existing tables and mappings from Lab 02.
* If no data arrives, check the student checkpoint in Lab 05c before asking for help.
