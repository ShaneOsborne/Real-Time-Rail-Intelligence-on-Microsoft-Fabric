"""Lab 10: create (optionally) and chat with a Foundry prompt agent that calls the Fabric data agent
"Rail Network Analyst" through the Fabric IQ (OneLake Catalog) tool (preview).

The older Microsoft Fabric data agent tool (MicrosoftFabricPreviewTool / fabric_dataagent_preview) stops
being supported on 6 November 2026; this script uses its replacement, FabricIQPreviewTool.
Docs: https://learn.microsoft.com/azure/foundry/agents/how-to/tools/fabric-iq

Prerequisites
* `az login` as a USER: the connection uses UserEntraToken, so the data agent runs as the signed-in user.
* pip install -r foundry/requirements.txt   (azure-ai-projects >= 2.2.0)
* Env vars (or .env): FOUNDRY_PROJECT_ENDPOINT, FOUNDRY_MODEL_DEPLOYMENT_NAME (e.g. gpt-5.4),
  FABRIC_IQ_PROJECT_CONNECTION_ID (full resource ID; or --connection-name), FOUNDRY_AGENT_NAME.

Usage
    python foundry/agent_client.py --create              # create a new agent version, then chat
    python foundry/agent_client.py                       # chat with the existing agent
    python foundry/agent_client.py --ask "Which trains are 15+ minutes late?"
    python foundry/agent_client.py --create --delete-after
    python foundry/agent_client.py --no-background       # if your model doesn't support background mode
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]

DATA_AGENT_NAME = "Rail Network Analyst"

INSTRUCTIONS = f"""You are the Rail Network Assistant for Great Britain's railway.
For ANY question about trains, delays, cancellations, stations, operators or punctuality, use the Fabric IQ tool for the
'{DATA_AGENT_NAME}' data agent - never guess numbers. It answers from live TRUST train-movement data in the RailKQL
Eventhouse (latest positions, delays, cancellations, operator performance, station boards).
State the time window used and keep answers short (one-sentence summary plus a small table). The data is
near-real-time open data and not official; say so when users ask for authoritative figures."""


def load_dotenv() -> None:
    env = REPO / ".env"
    if env.exists():
        for line in env.read_text(encoding="utf-8").splitlines():
            if line.strip().startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def main() -> int:
    load_dotenv()
    p = argparse.ArgumentParser()
    p.add_argument("--create", action="store_true", help="Create a new agent version with the Fabric IQ tool")
    p.add_argument("--connection-name", help="Foundry project connection NAME (alternative to FABRIC_IQ_PROJECT_CONNECTION_ID)")
    p.add_argument("--ask", help="Ask one question and exit")
    p.add_argument("--delete-after", action="store_true", help="Delete the created agent version on exit")
    p.add_argument("--no-background", action="store_true", help="Don't use background mode (for models without it)")
    p.add_argument("--timeout", type=int, default=300, help="Seconds to wait for a background answer (default 300)")
    a = p.parse_args()

    endpoint = os.getenv("FOUNDRY_PROJECT_ENDPOINT")
    agent_name = os.getenv("FOUNDRY_AGENT_NAME", "rail-network-agent")
    if not endpoint:
        print("ERROR: FOUNDRY_PROJECT_ENDPOINT is required", file=sys.stderr)
        return 2

    from azure.ai.projects import AIProjectClient
    from azure.identity import DefaultAzureCredential

    project = AIProjectClient(endpoint=endpoint, credential=DefaultAzureCredential())

    created = None
    if a.create:
        from azure.ai.projects.models import FabricIQPreviewTool, PromptAgentDefinition

        model = os.getenv("FOUNDRY_MODEL_DEPLOYMENT_NAME")
        conn_id = os.getenv("FABRIC_IQ_PROJECT_CONNECTION_ID")
        if a.connection_name:
            conn_id = project.connections.get(a.connection_name).id
        if not model or not conn_id:
            print("ERROR: FOUNDRY_MODEL_DEPLOYMENT_NAME and FABRIC_IQ_PROJECT_CONNECTION_ID (or --connection-name) required",
                  file=sys.stderr)
            return 2
        created = project.agents.create_version(
            agent_name=agent_name,
            definition=PromptAgentDefinition(
                model=model,
                instructions=INSTRUCTIONS,
                tools=[FabricIQPreviewTool(project_connection_id=conn_id, require_approval="never")],
            ),
        )
        print(f"Agent created: name={created.name} version={created.version} model={model}")

    openai = project.get_openai_client(agent_name=agent_name)

    def ask(question: str) -> None:
        if a.no_background:
            response = openai.responses.create(input=question, tool_choice="required")
        else:
            # Data agent calls can outlast the normal tool-call timeout; background mode lets them finish.
            response = openai.responses.create(input=question, tool_choice="required", background=True)
            deadline = time.monotonic() + a.timeout
            while response.status in ("queued", "in_progress"):
                if time.monotonic() > deadline:
                    print(f"\nStill running after {a.timeout}s (response {response.id}). Try a narrower question.\n")
                    return
                time.sleep(2)
                response = openai.responses.retrieve(response.id)
            if response.status != "completed":
                print(f"\nAgent run ended with status '{response.status}': {getattr(response, 'error', None)}\n")
                return
        print(f"\nAgent: {response.output_text}\n")

    try:
        if a.ask:
            ask(a.ask)
        else:
            print("Ask about the rail network (blank line to quit).")
            while True:
                q = input("You: ").strip()
                if not q:
                    break
                ask(q)
    finally:
        if created is not None and a.delete_after:
            project.agents.delete_version(agent_name=created.name, agent_version=created.version)
            print("Agent version deleted")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
