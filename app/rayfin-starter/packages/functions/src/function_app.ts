// Lab 11 – Rayfin functions for the rail app.
// COPY this file over packages/functions/src/function_app.ts (created by `npm run pack:add -- functions` in the default
// template) – it replaces the starter function. Then set the two values below. types.ts is regenerated from this file; don't edit it.
// Pattern: https://rayfin.ai/docs/functions/writing-functions and https://rayfin.ai/docs/functions/connections
// Functions aren't available in every Fabric region or tenant.
import { UserDataFunctions, AudienceType, type RayfinContext } from '@microsoft/fabric-user-data-functions';

// ================= SET THESE TWO VALUES (no placeholders in a deployed app) =================
// Replace ONLY the text between the single quotes, and keep both quotes and the semicolon.
// (The map doesn't use a function: it reads the Lab 10b semantic model through a connector – see the frontend.)
// Foundry project endpoint from Lab 10 (FOUNDRY_PROJECT_ENDPOINT in the lab repo .env), e.g.
//   'https://my-foundry.services.ai.azure.com/api/projects/my-project'
const FOUNDRY_PROJECT_ENDPOINT = 'PASTE-FOUNDRY-PROJECT-ENDPOINT-HERE';
// Foundry agent name from Lab 10 (FOUNDRY_AGENT_NAME in the lab repo .env).
const FOUNDRY_AGENT_NAME = 'rail-network-agent';
// =============================================================================================

// Fails with a clear message (shown in the app) if a value above wasn't set properly.
function checkUrl(name: string, value: string): string {
  if (!/^https:\/\/[^\s'"<>]+$/.test(value) || value.includes('PASTE-')) {
    throw new Error(`${name} isn't set. Edit the "SET THESE TWO VALUES" block in packages/functions/src/function_app.ts`);
  }
  return value.replace(/\/+$/, ''); // tolerate a trailing slash
}

const udf = new UserDataFunctions();

// This app has no Rayfin data entities, so the data schema is empty (pattern from the Rayfin connections docs).
export type RailSchema = Record<string, never>;

// ---- Chat: forwards a question to the Foundry agent from Lab 10 ----

udf.func(
  'askRailAgent',
  // Rayfin 1.36: the audience is declared in the context type and the token read from ctx.Tokens.
  // Deployed, the token is for the Fabric app identity (the owner of the App item); locally it's the account you signed in with.
  // Grant that identity the Foundry User role on the Foundry project. The Lab 10 Fabric IQ connection runs as a user (UserEntraToken).
  async (ctx: RayfinContext<RailSchema, AudienceType.AzureAI>, question: string): Promise<string> => {
    const token = ctx.Tokens.AzureAI;

    // TODO(verify): Foundry Responses API with an agent reference. Confirm the path and body shape
    // against https://ai.azure.com/api-reference/responses/ for your API version before relying on it.
    const res = await fetch(`${checkUrl('FOUNDRY_PROJECT_ENDPOINT', FOUNDRY_PROJECT_ENDPOINT)}/openai/v1/responses`, {
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
  [],
);

// ---- Lab 11b (optional): Azure Maps credential for the satellite/track map ----
// Returns the value of the Rayfin secret AZURE_MAPS_TOKEN, or { configured: false } if it isn't set (then the app shows the
// simple map). Intended value: an Azure Maps **SAS token** – made to be handed to a browser: it's scoped to map tiles,
// rate-limited and expires within 24 hours (scripts/new-azure-maps-sas.*). A subscription key also works for a quick
// test, but it never expires, so don't use one beyond that. Only signed-in app users can call this function.
// ctx.getSecret() (untyped, deprecated in Rayfin 1.36) is used on purpose: the secret is optional, so Lab 11 still builds
// without it.
udf.func(
  'getMapAuth',
  async (ctx: RayfinContext<RailSchema>): Promise<{ configured: boolean; authType: 'sas' | 'subscriptionKey' | 'none'; token: string }> => {
    // eslint-disable-next-line @typescript-eslint/no-deprecated
    const value = (ctx.getSecret('AZURE_MAPS_TOKEN') ?? '').trim();
    if (!value) return { configured: false, authType: 'none', token: '' };
    // SAS tokens are JWTs ("eyJ…"); anything else is treated as a subscription key.
    return { configured: true, authType: value.startsWith('eyJ') ? 'sas' : 'subscriptionKey', token: value };
  },
  [],
);
