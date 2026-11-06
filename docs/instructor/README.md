# Instructor path – running the labs as a class

**Who this is for:** the person who sets up and runs a classroom session. Students follow the
[student path](../student/README.md) instead. Working alone with your own accounts? Use the [solo path](../solo/README.md).

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

Read [Start here](../start-here.md) first: architecture, costs, licensing and preview caveats.

## Timeline

| When | Pages |
|---|---|
| **Two weeks before** | [Instructor 1.1](1.1-prepare.md): accounts, tenant settings, capacity, Foundry project |
| **The day before** | [Instructor 1.2](1.2-workspace-and-reference-data.md) to [Instructor 1.5](1.5-student-workspaces-and-handout.md): your workspace and reference data, the bridge, the shared Event Hub, student workspaces, the handout and a dry run |
| **Before the class** | [Part 2](../build/README.md): run the build yourself, so you know every step the students will do |
| **On the day** | [Instructor 1.6](1.6-running-the-class.md) |
| **After the class** | [Instructor 1.7](1.7-after-the-class.md) |

## Part 1 – set up the class

Follow these in order. Several pages ask you to run a **solo** page yourself, then add the class-specific steps.

| Page | What you do | Shared pages you run yourself | Time |
|---|---|---|---|
| [Instructor 1.1 – Prepare](1.1-prepare.md) | Accounts, tenant settings for the student group, capacity sizing, shared Foundry project | [Solo 1.1](../solo/1.1-prerequisites.md) | 60 min (+ approval wait) |
| [Instructor 1.2 – Workspace and reference data](1.2-workspace-and-reference-data.md) | Your workspace, the reference Lakehouse, sharing it with students | [Solo 1.2](../solo/1.2-fabric-workspace.md), [Solo 1.3](../solo/1.3-reference-data.md) (Option A2) | 50 min |
| [Instructor 1.3 – Bridge](1.3-bridge.md) | Test the bridge locally, then deploy it to Azure | [Solo 1.6](../solo/1.6-bridge-local.md), [Solo 1.7](../solo/1.7-bridge-azure.md) | 70 min |
| [Instructor 1.4 – Shared Event Hub](1.4-shared-event-hub.md) | Event Hubs namespace, consumer groups, RDM relay: **the feed for the class** (key sign-in, or workspace identity if a policy blocks keys) | – | 30 min |
| [Instructor 1.5 – Student workspaces and handout](1.5-student-workspaces-and-handout.md) | Student workspaces, Foundry access, the handout, a dry run as a student | [Student 1.1–1.4](../student/README.md) (dry run) | 30 min |
| [Instructor 1.6 – Running the class](1.6-running-the-class.md) | Capacity watch, common student problems, overnight pause | – | – |
| [Instructor 1.7 – After the class](1.7-after-the-class.md) | Keys (or workspace identity roles), Event Hub, Foundry roles, your own clean-up | [Lab 2.10](../build/2.10-cleanup.md) | 15 min |

Students follow [the student path](../student/README.md): Student 1.1–1.4 (and the optional 1.5 if you run the Darwin class feed), then Part 2.

## Part 2 – run the build yourself before the class

Do [Part 2 – the build](../build/README.md) (Lab 2.1 to Lab 2.9; leave Lab 2.10 until after the class) in your own workspace before the
class. Your workspace reads the shared Event Hub with consumer group `$Default`, so you see exactly what the students see.
The few classroom differences are in a **Classroom students** note on Labs 2.6–2.10 and in the
[student path](../student/README.md#part-2--the-build).
