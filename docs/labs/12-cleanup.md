# Lab 12 – Clean-up

**Time:** 10 minutes · **Previous:** [Lab 11](11-rayfin-app.md)

> **Path:** Solo – all · Instructor – all, plus the [Instructor guide clean-up](../instructor-guide.md#5-after-the-class) · **Classroom student – [Classroom students](#classroom-students) only.**

## Objectives

Stop all spending and release your NROD connection.

## Classroom students

You only clean up **your own** Fabric items. Don't run `cleanup.sh`: you have no Azure resources, and the Event Hub belongs to the instructor.

1. In your workspace, **deactivate** the Eventstreams (Eventstream → **Deactivate all**), so they stop reading the shared hub.
2. Delete your Rayfin app (if any) and your Foundry agent (`FOUNDRY_AGENT_NAME`) in the shared Foundry project.
3. Delete your workspace (*Workspace settings → General → Remove this workspace*), unless the instructor says to keep it.
4. Delete your `.env`, because it may hold connection details.

## Option A – automated

```bash
docker compose -f src/bridge/docker-compose.yml down     # if the bridge is running locally
./scripts/cleanup.sh            # deletes the Azure resource group (asks you to confirm)
./scripts/cleanup.sh --fabric   # also deletes the Fabric workspace (FABRIC_WORKSPACE_ID)
# PowerShell: ./scripts/cleanup.ps1 [-Fabric]
```

## Option B – manual

1. **Bridge**: stop it locally (Ctrl+C or `docker compose down`, plus `docker compose --profile relay down` if you ran the RDM relay). In Azure, delete the resource group `rg-rail-fabric-rti`.
   That also deletes the optional **Event Hubs namespace** and the **RDM relay** app (Lab 05c). If you created the namespace in another
   resource group, delete it with `az eventhubs namespace delete -g <rg> -n <namespace>`. Students should delete their Event Hubs sources
   (or the whole workspace) too, and the instructor should rotate the `students-listen` key if the namespace is kept.
   Key Vault is soft-deleted for 7 days. Purge it with `az keyvault purge -n <name>` if you want to reuse the name.
2. **Fabric**: delete the Rayfin app, data agent, Activator `RailAlerts`, dashboards, Eventstreams (stopping the Kafka consumer),
   Eventhouse, Lakehouse and notebook. Or delete the whole workspace.
3. **Capacity**: first **deactivate** any Eventstreams you're keeping (Eventstream → **Deactivate all**), so they stop
   consuming capacity. If you scaled the capacity up for a class or a back-fill, **scale it back down**. Then **pause**
   pay-as-you-go F-SKU capacity, or delete it if you created it only for these labs. See
   [Capacity planning and sizing](../capacity-planning.md).
4. **Foundry**: delete the agent (`python foundry/agent_client.py --create --delete-after` cleans up automatically) and the Fabric connection.
5. **Subscriptions**: unsubscribe from the RDM products and NROD feeds you no longer need. Durable subscriptions expire on the broker.
6. **Secrets**: delete `.env`, or rotate the NROD password, the Eventstream keys and (Lab 05c) the Event Hubs and RDM keys if you shared them anywhere.
7. **GHCR**: delete the container package if you published one.

## Checkpoint

- [ ] `az group exists -n rg-rail-fabric-rti` returns `false`
- [ ] The Fabric workspace is gone, or the capacity is paused
- [ ] Any Eventstreams you kept are deactivated, and the capacity is back to its normal size
- [ ] No bridge or RDM relay process is running anywhere
- [ ] (Lab 05c) `az eventhubs namespace list -g rg-rail-fabric-rti -o table` returns nothing, or the resource group is gone
