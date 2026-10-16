// EXPERIMENTAL – Rayfin functions and delegated auth are not available in every tenant/region.
// Merge into rayfin/functions/src/function_app.ts created by `npx rayfin functions init`.
// Pattern: https://rayfin.ai/docs/functions/writing-functions and https://rayfin.ai/docs/functions/connections
import { UserDataFunctions, AudienceType, type RayfinContext } from '@microsoft/fabric-user-data-functions';

const udf = new UserDataFunctions();

// ---- Eventhouse (KQL database) – values from Lab 02 / your .env, do not leave placeholders ----
// KUSTO_QUERY_URI: RailKQL > Overview > Query URI, e.g. https://<id>.<region>.kusto.fabric.microsoft.com (also in the repo .env)
// KQL_DATABASE: the database NAME, e.g. RailKQL
const KUSTO_QUERY_URI = '<https://<id>.<region>.kusto.fabric.microsoft.com>';
const KQL_DATABASE = 'RailKQL';

type Row = Record<string, string | number | boolean | null>;

// Map data for the frontend. Runs a FIXED query (only the look-back window comes from the caller, and it's validated),
// so users can't send arbitrary KQL. Runs as the signed-in user: they need at least Viewer on RailKQL.
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

// ---- Foundry agent (Lab 10) ----
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
