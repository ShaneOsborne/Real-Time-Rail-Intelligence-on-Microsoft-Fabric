# Lab 12 – Clean-up

**Time:** 10 minutes · **Previous:** [Lab 11](11-rayfin-app.md)

## Objectives

Stop all spending and release your NROD connection.

## Option A – automated

```bash
docker compose -f src/bridge/docker-compose.yml down     # if the bridge is running locally
./scripts/cleanup.sh            # deletes the Azure resource group (asks you to confirm)
./scripts/cleanup.sh --fabric   # also deletes the Fabric workspace (FABRIC_WORKSPACE_ID)
# PowerShell: ./scripts/cleanup.ps1 [-Fabric]
```

## Option B – manual

1. **Bridge**: stop it locally (Ctrl+C or `docker compose down`). In Azure, delete the resource group `rg-rail-fabric-rti`.
   Key Vault is soft-deleted for 7 days. Purge it with `az keyvault purge -n <name>` if you want to reuse the name.
2. **Fabric**: delete the Rayfin app, data agent, Activator `RailAlerts`, dashboards, Eventstreams (stopping the Kafka consumer),
   Eventhouse, Lakehouse and notebook. Or delete the whole workspace.
3. **Capacity**: **pause** pay-as-you-go F-SKU capacity, or delete it if you created it only for these labs.
4. **Foundry**: delete the agent (`python foundry/agent_client.py --create --delete-after` cleans up automatically) and the Fabric connection.
5. **Subscriptions**: unsubscribe from the RDM products and NROD feeds you no longer need. Durable subscriptions expire on the broker.
6. **Secrets**: delete `.env`, or rotate the NROD password and Eventstream keys if you shared them anywhere.
7. **GHCR**: delete the container package if you published one.

## Checkpoint

- [ ] `az group exists -n rg-rail-fabric-rti` returns `false`
- [ ] The Fabric workspace is gone, or the capacity is paused
- [ ] No bridge process is running anywhere
