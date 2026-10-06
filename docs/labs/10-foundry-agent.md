# Lab 10 – Azure AI Foundry agent with the Fabric data agent tool

**Time:** 30 minutes · **Previous:** [Lab 09](09-fabric-data-agent.md) · **Next:** [Lab 11](11-rayfin-app.md)

## Objectives

* Connect a Foundry **prompt agent** to the published Fabric data agent through the **Microsoft Fabric data agent tool (preview)**.
* Chat with it from Python (`foundry/agent_client.py`).

## Important constraints (preview)

* **User identity only** (On-Behalf-Of / identity passthrough). **Service principals are not supported**. Every end user needs access to the data agent and its sources.
* **One Fabric data agent per Foundry agent** in this design.
* Paid **F2+** capacity (or P1+). The same tenant for Fabric and Foundry. Data agent and sources on capacities in the same region.
* Configure Fabric **cross-geo** AI tenant settings if your regions require them.
* Users need the **Foundry User** RBAC role on the Foundry project.

Source: <https://learn.microsoft.com/azure/foundry/agents/how-to/tools/fabric>

## Option A – automated (after one portal step)

1. **Create the connection.** In the Foundry portal: project → *Agents* → create or open an agent → **Add tool** → **Microsoft Fabric data agent** → enter the
   `workspace_id` and `artifact_id` (from Lab 09) → finish. Copy the **connection ID** into `FABRIC_PROJECT_CONNECTION_ID`.
   To script this step instead, send the ARM `PUT …/projects/<project>/connections/<name>?api-version=2025-04-01-preview` request documented on the Learn page above
   (category `CustomKeys`, keys `workspace_id` and `artifact_id`).
2. Run:

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r foundry/requirements.txt
az login                                    # as a USER
python foundry/agent_client.py --create --ask "Which trains are more than 15 minutes late right now?"
python foundry/agent_client.py              # interactive chat with the same agent
```

The script uses the documented SDK types `AIProjectClient`, `PromptAgentDefinition`, `MicrosoftFabricPreviewTool`,
`FabricDataAgentToolParameters` and `ToolProjectConnection`, plus `project.get_openai_client(agent_name=...)` and
`responses.create(tool_choice="required")`.

## Option B – manual (portal only)

1. In the Foundry portal: **Agents** → **New agent** → name `rail-network-agent` → choose your model deployment.
2. **Instructions**: copy `INSTRUCTIONS` from `foundry/agent_client.py`. The key line is: *"For ANY question about trains … use the Microsoft Fabric tool"*.
3. **Tools** → **Add** → **Microsoft Fabric data agent** → workspace ID and artifact ID → save.
4. Test it in the **playground**: "Which operators had the worst average delay in the last 3 hours?"

## Checkpoint

* The answer includes figures that match the Fabric data agent's answer for the same question.
* The run details show a `fabric_dataagent_preview` tool call.

## Troubleshooting

| Error | Fix |
|---|---|
| `Artifact Id should not be empty and needs to be a valid GUID` | Recreate the connection with the right `workspace_id` and `artifact_id` |
| `unauthorized` | The end user lacks access to the data agent or KQL database, or you used a service principal |
| `configuration not found` | Publish the data agent again in Fabric |
| Agent doesn't use the tool | Strengthen the instructions. Keep `tool_choice="required"` |
| Timeouts | Narrow the question's time window. Retry with backoff |
