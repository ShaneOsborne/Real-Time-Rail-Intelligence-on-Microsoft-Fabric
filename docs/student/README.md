# Student path – classroom

**Who this is for:** students in an instructor-led class that uses the **shared Event Hub**. Your instructor runs the
connections to Network Rail and the Rail Data Marketplace, so you **don't** need NROD or RDM accounts, an Azure
subscription, Docker or the bridge.

Working alone with your own accounts? Use the [solo path](../solo/README.md) instead. New to the project? Read
[Start here](../start-here.md) first (about 20 minutes).

Get your **handout** from the instructor before you start. It has your workspace name, the Event Hubs namespace, key name
and key, **your own consumer group**, the reference Lakehouse location and the Foundry details. Keep the key private.
If your handout says **Workspace identity** instead of a key, there's no key: [Student 1.4](1.4-connect-to-the-class-feed.md) shows what to do.

## Part 1 – get data in

Follow these in order.

| Page | What you do | Time |
|---|---|---|
| [Student 1.1 – Get ready](1.1-get-ready.md) | Fabric access check, tools, clone and `.env` | 20 min |
| [Student 1.2 – Fabric workspace](1.2-fabric-workspace.md) | Create your workspace and items, **including the raw tables and mappings** | 20 min |
| [Student 1.3 – Reference data](1.3-reference-data.md) | Shortcut to the instructor's reference data | 10 min |
| [Student 1.4 – Connect to the class feed](1.4-connect-to-the-class-feed.md) | Event Hubs sources with **your own** consumer group | 15 min |
| [Student 1.5 – Darwin class feed](1.5-darwin-class-feed.md) (optional) | Darwin forecasts and platforms → `DarwinLocations`. Only if your handout has an *Optional Darwin feed* row | 15 min |

## Part 2 – the build

Then do the shared build, the same as everyone else. Each page has at most one short **Classroom students** note. They're
listed here too, so you know what to expect.

| Page | Time | Classroom note |
|---|---|---|
| [Lab 2.1 – KQL transformations](../build/2.1-kql-transformations.md) | 40 min | – |
| [Lab 2.2 – Activator alerts](../build/2.2-activator-alerts.md) | 30 min | – |
| [Lab 2.3 – Real-Time Dashboard and Power BI report](../build/2.3-dashboard-powerbi.md) | 45 min | – |
| [Lab 2.4 – Fabric data agent](../build/2.4-fabric-data-agent.md) | 30 min | – |
| [Lab 2.5 – Rail ontology](../build/2.5-rail-ontology.md) (optional) | 50 min | Only if your instructor says the ontology tenant setting is on. Use your own workspace |
| [Lab 2.6 – Foundry agent](../build/2.6-foundry-agent.md) | 30 min | Use the instructor's **shared** Foundry project and **your own** agent name (for example `rail-network-agent-student07`). Don't create a project |
| [Lab 2.7 – Live semantic model](../build/2.7-live-semantic-model.md) | 25 min | Build your own model in your own workspace, unless your instructor shares one |
| [Lab 2.8 – Rayfin app](../build/2.8-rayfin-app.md) | 60 min | Only if your instructor says Fabric Apps works in your region |
| [Lab 2.9 – Azure Maps map](../build/2.9-azure-maps.md) (optional) | 45 min | Only with the Azure Maps token your instructor gives you. Skip steps 1–2 |
| [Lab 2.10 – Clean-up](../build/2.10-cleanup.md) | 10 min | Only the *Classroom students* section: your own items |

## Golden rules

* Use **your own** consumer group (for example `student07`). Never `$Default` and never a classmate's: the events are
  split between everyone reading the same group.
* Don't let an Eventstream wizard create tables. Use the existing tables and mappings from Student 1.2.
* If no data arrives, check the [Student 1.4 checkpoint](1.4-connect-to-the-class-feed.md#checkpoint) before asking for help.
