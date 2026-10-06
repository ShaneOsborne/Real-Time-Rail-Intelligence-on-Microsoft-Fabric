// EXPERIMENTAL – Rayfin functions and delegated auth are not available in every tenant/region.
// Merge into rayfin/functions/src/function_app.ts created by `npx rayfin functions init`.
// Pattern: https://rayfin.ai/docs/functions/writing-functions and https://rayfin.ai/docs/functions/connections
import { UserDataFunctions, AudienceType, type RayfinContext } from '@microsoft/fabric-user-data-functions';

const udf = new UserDataFunctions();

// Real values from your Foundry project (Lab 10) – do not leave placeholders in a deployed app.
const FOUNDRY_PROJECT_ENDPOINT = '<https://<resource>.services.ai.azure.com/api/projects/<project>>';
const FOUNDRY_AGENT_NAME = 'rail-network-agent';

udf.func(
  'askRailAgent',
  async (ctx: RayfinContext, question: string): Promise<string> => {
    // On-behalf-of token for Azure AI Foundry as the signed-in user (the Fabric data agent
    // tool in Foundry also requires user identity – service principals are not supported).
    const token = ctx.getToken(AudienceType.AzureAI);

    // TODO(verify): Foundry Responses API with an agent reference. Confirm the path and body shape
    // against https://ai.azure.com/api-reference/responses/ for your API version before relying on it.
    const res = await fetch(`${FOUNDRY_PROJECT_ENDPOINT}/openai/v1/responses`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        input: question,
        agent_reference: { type: 'agent_reference', name: FOUNDRY_AGENT_NAME },
        tool_choice: 'required',
      }),
    });
    if (!res.ok) {
      console.error('Foundry call failed', res.status, await res.text());
      throw new Error(`Foundry agent call failed with HTTP ${res.status}`);
    }
    const body = (await res.json()) as { output_text?: string; output?: Array<{ content?: Array<{ text?: string }> }> };
    if (body.output_text) return body.output_text;
    const text = (body.output ?? []).flatMap((o) => o.content ?? []).map((c) => c.text ?? '').join('\n').trim();
    return text || 'The agent returned no text.';
  },
  [udf.connection({ audienceType: AudienceType.AzureAI })],
);
