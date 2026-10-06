# Foundry agent with the Microsoft Fabric data agent tool (Lab 10)

The Fabric data agent tool is **preview**. Key constraints (from Microsoft Learn,
https://learn.microsoft.com/azure/foundry/agents/how-to/tools/fabric):

* **User identity only** (identity passthrough / On-Behalf-Of). Service principal auth is not supported.
* The Fabric data agent must be **published**; users need at least READ on it and the **Reader** role on the KQL database.
* Paid **F2+** capacity (or P1+ with Fabric enabled); data agent and data sources on capacities in the **same region**;
  Fabric data agent and Foundry project in the **same tenant**.
* Configure Fabric **cross-geo processing/storage** tenant settings for data agents if your deployment needs them.
* Developers and end users need at least the **Foundry User** (formerly Azure AI User) Azure RBAC role.
* This lab uses one Fabric data agent per Foundry agent.

## Values you need

| Variable | Where to find it |
|---|---|
| `FOUNDRY_PROJECT_ENDPOINT` | Foundry portal → project overview (format `https://<resource>.services.ai.azure.com/api/projects/<project>`) |
| `FOUNDRY_MODEL_DEPLOYMENT_NAME` | Your model deployment (used for orchestration only) |
| `FABRIC_PROJECT_CONNECTION_ID` | Created when you add the Fabric data agent tool in the portal (needs `workspace_id` and `artifact_id` from the data agent URL `.../groups/<workspace_id>/aiskills/<artifact_id>...`) |

## Run

```bash
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r foundry/requirements.txt
az login
python foundry/agent_client.py --create --ask "Which trains are more than 15 minutes late right now?"
python foundry/agent_client.py            # interactive chat with the existing agent
```

`tool_choice="required"` forces the Fabric tool on every turn, which is what you want for a data Q&A agent.
