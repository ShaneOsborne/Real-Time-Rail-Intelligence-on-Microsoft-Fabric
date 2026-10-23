// Lab 11 – Rayfin functions for the rail app.
// COPY this file over packages/functions/src/function_app.ts (created by `npm run pack:add -- functions` in the default
// template) – it replaces the starter function. Then set the four constants below. types.ts is regenerated from this file; don't edit it.
// Pattern: https://rayfin.ai/docs/functions/writing-functions and https://rayfin.ai/docs/functions/connections
// Functions aren't available in every Fabric region or tenant.
import { UserDataFunctions, AudienceType, type RayfinContext } from '@microsoft/fabric-user-data-functions';

// ================= SET THESE FOUR VALUES (no placeholders in a deployed app) =================
// Eventhouse: RailKQL > Overview > Query URI (also KUSTO_QUERY_URI in the lab repo .env). No trailing slash.
const KUSTO_QUERY_URI = '<https://<id>.<region>.kusto.fabric.microsoft.com>';
// The KQL database NAME (FABRIC_KQL_DATABASE_NAME in the lab repo .env).
const KQL_DATABASE = 'RailKQL';
// Foundry project endpoint from Lab 10 (FOUNDRY_PROJECT_ENDPOINT in the lab repo .env).
const FOUNDRY_PROJECT_ENDPOINT = '<https://<resource>.services.ai.azure.com/api/projects/<project>>';
// Foundry agent name from Lab 10 (FOUNDRY_AGENT_NAME in the lab repo .env).
const FOUNDRY_AGENT_NAME = 'rail-network-agent';
// =============================================================================================

const udf = new UserDataFunctions();

type Row = Record<string, string | number | boolean | null>;

// Map data for the frontend. Runs a FIXED query (only the look-back window comes from the caller, and it's validated),
// so users can't send arbitrary KQL. Rayfin 1.36 docs say DEPLOYED functions use the app identity, so grant the app
// (the App item, e.g. rail-app) Viewer on RailKQL; locally (npm run dev) it runs as you.
udf.func(
  'getNetworkSnapshot',
  async (ctx: RayfinContext, lookbackMinutes: number): Promise<Row[]> => {
    const minutes = Math.round(Number(lookbackMinutes));
    if (!Number.isFinite(minutes) || minutes < 5 || minutes > 240) {
      throw new Error('lookbackMinutes must be between 5 and 240');
    }
    const token = ctx.getToken(AudienceType.Kusto);
    // Kusto REST API v1 query endpoint (returns { Tables: [{ TableName, Columns, Rows }] }).
    const res = await fetch(`${KUSTO_QUERY_URI}/v1/rest/query`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json; charset=utf-8',
        Accept: 'application/json',
        'x-ms-client-request-id': `rail-app;${crypto.randomUUID()}`,
      },
      body: JSON.stringify({ db: KQL_DATABASE, csl: `NetworkSnapshot(${minutes}m) | take 2000` }),
    });
    if (!res.ok) {
      console.error('Kusto query failed', res.status, await res.text());
      throw new Error(`Eventhouse query failed with HTTP ${res.status}`);
    }
    const body = (await res.json()) as {
      Tables?: Array<{ Columns: Array<{ ColumnName: string }>; Rows: unknown[][] }>;
    };
    const table = body.Tables?.[0];
    if (!table) return [];
    return table.Rows.map((row) =>
      Object.fromEntries(table.Columns.map((c, i) => [c.ColumnName, row[i] as Row[string]])),
    );
  },
  [udf.connection({ audienceType: AudienceType.Kusto })],
);

// ---- Chat: forwards a question to the Foundry agent from Lab 10 ----

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
