# Lab 10 – Azure AI Foundry agent with the Fabric IQ (OneLake Catalog) tool

**Time:** 30 minutes · **Previous:** [Lab 09](09-fabric-data-agent.md) · **Next:** [Lab 10b](10b-live-semantic-model.md)

> **Path:** Everyone. Classroom students use the instructor's shared Foundry project and their **own** agent name (for
> example `rail-network-agent-student07`).

> **Tool change (Oct 2026).** The older **Microsoft Fabric data agent** tool in Foundry (workspace ID + artifact ID) is
> deprecated and **stops being supported on 6 November 2026**. This lab uses its replacement, the **Fabric IQ (OneLake
> Catalog)** tool (preview), which picks your published data agent from the OneLake Catalog and calls it over MCP.
> If you built an agent with the old tool, see [Migrating an existing agent](#migrating-an-existing-agent).
> Sources: [Fabric IQ tool](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/fabric-iq) ·
> [retirement notice](https://community.fabric.microsoft.com/blog/fbc_fabricupdatesblogs/retiring-the-fabric-data-agent-custom-tool-in-microsoft-foundry-move-to-fabric-i/5374418)

## Objectives

* Deploy a model that suits the Fabric IQ tool, and turn on **background mode**.
* Create a Foundry **prompt agent** that calls the Lab 09 data agent `Rail Network Analyst` through **Fabric IQ (OneLake Catalog)**.
* Chat with it in the playground and from Python (`foundry/agent_client.py`).

## Before you start

* Lab 09 is done: the data agent is **published**, with a clear **description** (the Foundry agent uses it to decide when to
  call the data agent), and shared with the people who'll use it.
* Fabric and Foundry are in the **same tenant**. The data agent and `RailKQL` are on paid **F2+** capacity in the **same
  region**. Fabric IQ isn't available in regions where Power BI is the only Fabric workload.
* Cross-geo processing/storage tenant settings are on if your regions need them (Lab 01).
* Roles on the Foundry project: **Foundry User** for everyone who builds or chats; **Foundry Project Manager** for whoever
  **adds the Fabric IQ tool** (it creates a project connection). Classroom: the instructor can add it once – see the
  [Instructor guide](../instructor-guide.md).
* Every user also needs read access to the data agent and the **Reader** role on `RailKQL` (the tool runs as the signed-in user).

### Which model?

The portal picks a default model for new agents, and it depends on your project and the date – it could be a GPT, Grok,
Claude or other model. **Don't rely on the default.** Data agent calls can take longer than a normal tool call, and only
models that support **background mode** let them finish. At the time of writing Microsoft recommends **gpt-5.4** or
**gpt-5.5** for this (check the [Fabric IQ page](https://learn.microsoft.com/azure/foundry/agents/how-to/tools/fabric-iq#run-a-fabric-data-agent-in-background-mode)
for the current list). Older models such as gpt-4.1-mini may work for quick questions but can time out.

## Option B – manual (portal) – do this first

### 1. Deploy the recommended model (once per project)

1. **Check the region first.** Your project's region must offer **gpt-5.4** or **gpt-5.5**: look it up on
   [Azure OpenAI Model Regional Availability](https://model-availability.azurewebsites.net/) (Lab 01, §5). For example, gpt
   models weren't available in **UK West** when this lab was tested. If your project's region doesn't have them, create a new
   Foundry resource and project in a region that does **before** going further – a project can't change region.
2. In the [Foundry portal](https://ai.azure.com), open **your project** (the one from Lab 01 – check the project name at the top).
3. **Models** (or *Model catalog*) → search **gpt-5.4** (or **gpt-5.5**) → **Deploy** → keep the default settings → **Deploy**.
   If it isn't offered, the project's region doesn't have it (see step 1). As a stop-gap, choose the newest GPT model
   listed and expect slower answers or timeouts on long questions.
4. **Record three values in the repo `.env` now** – Option A and Lab 11 both need them:

   | `.env` variable | Value | Where to find it |
   |---|---|---|
   | `FOUNDRY_PROJECT_ENDPOINT` | `https://<resource>.services.ai.azure.com/api/projects/<project>` | Foundry portal → your project → **Overview** (project home) → **Project endpoint** (copy button). Not the *Azure OpenAI* endpoint, and no trailing `/` |
   | `FOUNDRY_MODEL_DEPLOYMENT_NAME` | e.g. `gpt-5.4` | The deployment name from step 3 |
   | `FOUNDRY_AGENT_NAME` | `rail-network-agent` (classroom: your own name) | The name you give the agent in step 2 |

### 2. Create the agent

1. **Agents** → **Create agent** (or **New agent**). Name it `rail-network-agent` (classroom: your own name, e.g.
   `rail-network-agent-student07`).
2. Expand the **extra options** on the create screen and check the **project** is the one from step 1. If you skip this,
   the agent may be created in a different (default) project, without your model or connection. You aren't asked for a
   model here; you set it next.
3. On the agent page, open the **Model** list and select your **gpt-5.4 / gpt-5.5** deployment, replacing the default.
4. Select the **parameters** icon next to the model and turn on **Background mode**.

### 3. Add the Fabric IQ (OneLake Catalog) tool

1. Under **Tools** → **Add** → **Browse all tools** → **Fabric IQ (OneLake Catalog)** → **Add tool**.
2. In the OneLake Catalog, filter by **Data agent**, select **`Rail Network Analyst`** → **Add**.
   You don't need workspace or artifact IDs. If it isn't listed, it isn't published or not shared with you (Lab 09).
3. If the agent still has the old **Microsoft Fabric** data agent tool, **remove** it.

### 4. Instructions

Paste `INSTRUCTIONS` from [`foundry/agent_client.py`](../../foundry/agent_client.py). It names the data agent and says
when to use it: *"For ANY question about trains, delays, cancellations, stations, operators or punctuality, use the Fabric
IQ tool for the 'Rail Network Analyst' data agent – never guess numbers."* **Save**.

### 5. Test in the playground

* "Which operators had the worst average delay in the last 3 hours?"
* "Which trains are more than 15 minutes late right now?"

The playground shows progress while the background run completes. Expand the run details to see the Fabric IQ tool call.

## Option A – automated (Python), after Option B step 1

Option A creates the same agent from code. It needs a **project connection** to the data agent's MCP endpoint and its
full resource ID.

1. **MCP URL.** In Fabric, open `Rail Network Analyst` → **Settings** → **Model Context Protocol** → copy the **MCP server
   URL**. It looks like `https://api.fabric.microsoft.com/v1/mcp/workspaces/<workspace-id>/dataagents/<data-agent-id>/agent`.
2. **Connection** (needs Foundry Project Manager). Edit the `target` in
   [`foundry/fabric-iq-connection.json`](../../foundry/fabric-iq-connection.json) to that URL, then:

   ```bash
   az login
   az rest --method put \
     --url "https://management.azure.com/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<foundry-account>/projects/<project>/connections/rail-fabric-iq?api-version=2025-04-01-preview" \
     --body @foundry/fabric-iq-connection.json --query id -o tsv
   ```

   Put the printed ID (it starts `/subscriptions/…/connections/rail-fabric-iq`) in `FABRIC_IQ_PROJECT_CONNECTION_ID` in `.env`.
   (Or pass `--connection-name rail-fabric-iq` to the script instead.) PowerShell: put the command on one line, or use backticks.
3. Run:

   ```bash
   python -m venv .venv && source .venv/bin/activate        # Windows: .venv\Scripts\activate
   pip install -r foundry/requirements.txt                  # azure-ai-projects >= 2.2.0
   az login                                                 # as a USER
   python foundry/agent_client.py --create --ask "Which trains are more than 15 minutes late right now?"
   python foundry/agent_client.py                           # interactive chat with the same agent
   ```

   The script uses `PromptAgentDefinition` with `FabricIQPreviewTool(project_connection_id=…, require_approval="never")`,
   then `responses.create(..., background=True)` and polls until the answer is ready. Add `--no-background` if your model
   doesn't support background mode.

## Migrating an existing agent

If you built `rail-network-agent` with the old **Microsoft Fabric** data agent tool:

1. Open the agent → switch the model to gpt-5.4/5.5 and turn on background mode (Option B, step 2.3–2.4).
2. Add **Fabric IQ (OneLake Catalog)** → `Rail Network Analyst` (step 3), and **remove** the old Microsoft Fabric tool.
3. Update the instructions (step 4), save, and test.
4. For code: use the new `foundry/agent_client.py`, set `FABRIC_IQ_PROJECT_CONNECTION_ID`, and delete `FABRIC_PROJECT_CONNECTION_ID`.

Your Fabric data agent doesn't change.

## Checkpoint

* The playground answer includes figures that match the Fabric data agent's own answer for the same question.
* The run details show a **Fabric IQ** tool call to `Rail Network Analyst` (not the old `fabric_dataagent_preview`).
* The agent shows your gpt-5.4/5.5 deployment, with background mode on.

## Troubleshooting

| Error | Fix |
|---|---|
| gpt-5.4 / gpt-5.5 isn't in the model catalog, or deployment fails with *not available in this region* | The project's region doesn't offer it. Check [model availability](https://model-availability.azurewebsites.net/), then create a new Foundry resource and project in a listed region (UK West didn't have them when tested) |
| `Rail Network Analyst` isn't in the OneLake Catalog | Publish it in Fabric (Lab 09), and check it's shared with you. Refresh the catalog |
| You can't add the Fabric IQ tool / connection creation is denied | You need **Foundry Project Manager** on the project. Ask the project owner (or instructor) |
| Agent created in the wrong project, without your model | Create it again and set the **project** in the extra options of the create screen |
| Answers time out, or the run stops while the data agent is working | Use gpt-5.4/5.5 and turn on **Background mode** (portal) or keep the script's default `background=True` |
| `background` isn't supported by the model | Switch to a background-capable model, or run the script with `--no-background` for short questions |
| `CONSENT_REQUIRED` | Open the consent URL in the error, sign in, then retry |
| 401 / unauthorized | The user lacks read on the data agent or **Reader** on `RailKQL`, or the Fabric and Foundry tenants differ |
| 404 / Not Found (code) | The MCP URL in the connection is wrong, or the data agent isn't published |
| Agent doesn't call the tool | Make the instructions name the data agent and the questions it handles. The script keeps `tool_choice="required"` |
| Still using the old tool after 6 Nov 2026 | It's no longer supported. Migrate as above |
