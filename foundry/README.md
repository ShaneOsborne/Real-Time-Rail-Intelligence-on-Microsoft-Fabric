# Foundry agent with the Fabric IQ (OneLake Catalog) tool (Lab 10)

The full steps are in [Lab 10](../docs/labs/10-foundry-agent.md). This folder holds:

| File | Purpose |
|---|---|
| `agent_client.py` | Creates the `rail-network-agent` prompt agent with `FabricIQPreviewTool` and chats with it (background mode by default) |
| `fabric-iq-connection.json` | Body for the project connection to the data agent's MCP endpoint (`RemoteTool`, `UserEntraToken`) |
| `requirements.txt` | `azure-ai-projects>=2.2.0`, `azure-identity` |

Key points (from [Microsoft Learn](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/fabric-iq)):

* The older **Microsoft Fabric data agent** tool stops being supported on **6 November 2026**. Fabric IQ is its replacement (preview).
* Use a model that supports **background mode** – Microsoft recommends **gpt-5.4** or **gpt-5.5** at the time of writing.
  Don't rely on the portal's default model.
* The data agent must be **published**. The connection runs as the signed-in user, who needs read on the data agent and
  **Reader** on `RailKQL`. Same tenant; data agent and sources on F2+ capacity in the same region.
* Roles: **Foundry User** to build and chat; **Foundry Project Manager** to create the Fabric IQ connection.

| Variable | Where to find it |
|---|---|
| `FOUNDRY_PROJECT_ENDPOINT` | Foundry portal → project overview (`https://<resource>.services.ai.azure.com/api/projects/<project>`) |
| `FOUNDRY_MODEL_DEPLOYMENT_NAME` | Your gpt-5.4 / gpt-5.5 deployment name |
| `FABRIC_IQ_PROJECT_CONNECTION_ID` | Full resource ID printed by the `az rest` command in Lab 10 Option A (or use `--connection-name`) |
| `FOUNDRY_AGENT_NAME` | `rail-network-agent` (classroom: your own name) |
