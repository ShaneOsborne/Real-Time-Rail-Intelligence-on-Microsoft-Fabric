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
// A question goes Foundry agent → Fabric IQ tool → data agent (writes and runs KQL) → back, so answers often take
// 20–90 seconds. To avoid timeouts the app uses TWO quick calls instead of one long one:
//   startRailAgent(question)   starts a background run and returns at once with its id
//   pollRailAgent(responseId)  returns the current state; the chat panel calls it every few seconds until it's done
// Each call finishes in a second or two, so no function or client timeout is hit however long the agent takes.
// askRailAgent (one call that waits up to 100 s) is kept for older chat panels and quick tests.
// None of them throw: a deployed function that throws only shows the browser "InternalError: An internal execution error
// occured", which hides the cause. Every failure comes back as a readable "Agent error (…)" text, and the details are also
// written with console.error (visible in the `npm run dev` / `rayfin dev functions apply` terminal).

type FoundryResponse = {
  id?: string;
  status?: string; // queued | in_progress | completed | failed | incomplete | cancelled
  output_text?: string;
  output?: Array<{ content?: Array<{ text?: string }> }>;
  error?: { code?: string; message?: string } | null;
  incomplete_details?: { reason?: string } | null;
};

// What the chat panel receives. status: 'working' → poll again with id; 'done' → show text; 'error' → show text as an error.
type AgentState = { id: string; status: 'working' | 'done' | 'error'; text: string };

const POLL_MS = 2_000;
const MAX_WAIT_MS = 100_000; // askRailAgent only: stay under the client timeout

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const short = (t: string) => t.replace(/\s+/g, ' ').slice(0, 300);
const fail = (text: string, id = ''): AgentState => ({ id, status: 'error', text });

function textOf(body: FoundryResponse): string {
  if (body.output_text) return body.output_text;
  return (body.output ?? []).flatMap((o) => o.content ?? []).map((c) => c.text ?? '').join('\n').trim();
}

// Turns a Foundry response into what the panel shows.
function stateOf(body: FoundryResponse): AgentState {
  const id = body.id ?? '';
  if (body.status === 'queued' || body.status === 'in_progress') return { id, status: 'working', text: '' };
  if (body.status && body.status !== 'completed') {
    const why = body.error?.message ?? body.incomplete_details?.reason ?? body.status;
    console.error('Foundry response not completed', body.status, body.error, body.incomplete_details);
    return fail(`Agent error (${body.status}): ${short(String(why))}`, id);
  }
  return { id, status: 'done', text: textOf(body) || 'The agent returned no text.' };
}

type Foundry = { base: string; headers: Record<string, string> };

// Rayfin 1.36: the audience is declared in the context type and the token read from ctx.Tokens.
// Deployed, the token is for the Fabric app identity (the owner of the App item); locally it's the account you signed in with.
// Grant that identity the Foundry User role on the Foundry project. The Lab 10 Fabric IQ connection runs as a user (UserEntraToken).
function foundry(ctx: RayfinContext<RailSchema, AudienceType.AzureAI>): Foundry | string {
  try {
    const base = `${checkUrl('FOUNDRY_PROJECT_ENDPOINT', FOUNDRY_PROJECT_ENDPOINT)}/openai/v1/responses`;
    if (!FOUNDRY_AGENT_NAME || FOUNDRY_AGENT_NAME.includes('PASTE-')) throw new Error('FOUNDRY_AGENT_NAME isn\'t set');
    const token = ctx.Tokens.AzureAI;
    return { base, headers: { Authorization: ['Bearer', token].join(' '), 'Content-Type': 'application/json' } };
  } catch (e) {
    console.error('Foundry setup failed', e);
    return `Agent error (setup): ${e instanceof Error ? e.message : String(e)}`;
  }
}

async function startRun(f: Foundry, question: string): Promise<AgentState> {
  const q = String(question ?? '').trim().slice(0, 2000);
  if (!q) return fail('Please ask a question.');
  try {
    // TODO(verify): Foundry Responses API with an agent reference and background mode (Lab 10). Check the path and body
    // against https://ai.azure.com/api-reference/responses/ for your API version.
    // background: true returns at once with an id; the run carries on in Foundry and we poll for the result.
    const res = await fetch(f.base, {
      method: 'POST',
      headers: f.headers,
      body: JSON.stringify({
        input: q,
        agent_reference: { type: 'agent_reference', name: FOUNDRY_AGENT_NAME },
        tool_choice: 'required',
        background: true,
      }),
    });
    if (!res.ok) {
      const detail = short(await res.text());
      console.error('Foundry call failed', res.status, detail);
      return fail(`Agent error (HTTP ${res.status}): ${detail}`);
    }
    return stateOf((await res.json()) as FoundryResponse);
  } catch (e) {
    console.error('Foundry start failed', e);
    return fail(`Agent error: ${e instanceof Error ? short(e.message) : 'unexpected failure'}`);
  }
}

async function readRun(f: Foundry, id: string): Promise<AgentState> {
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(id)) return fail('Agent error: invalid response id.', id);
  try {
    const res = await fetch(`${f.base}/${encodeURIComponent(id)}`, { headers: f.headers });
    if (!res.ok) {
      const detail = short(await res.text());
      console.error('Foundry poll failed', res.status, detail);
      return fail(`Agent error while waiting (HTTP ${res.status}): ${detail}`, id);
    }
    return stateOf((await res.json()) as FoundryResponse);
  } catch (e) {
    console.error('Foundry poll failed', e);
    return fail(`Agent error while waiting: ${e instanceof Error ? short(e.message) : 'unexpected failure'}`, id);
  }
}

// Starts the agent run and returns straight away (status 'working' + id), or 'done'/'error' if it already finished.
udf.func(
  'startRailAgent',
  async (ctx: RayfinContext<RailSchema, AudienceType.AzureAI>, question: string): Promise<{ id: string; status: 'working' | 'done' | 'error'; text: string }> => {
    const f = foundry(ctx);
    return typeof f === 'string' ? fail(f) : startRun(f, question);
  },
  [],
);

// Returns the current state of a run started by startRailAgent. One quick request; the chat panel repeats it.
udf.func(
  'pollRailAgent',
  async (ctx: RayfinContext<RailSchema, AudienceType.AzureAI>, responseId: string): Promise<{ id: string; status: 'working' | 'done' | 'error'; text: string }> => {
    const f = foundry(ctx);
    return typeof f === 'string' ? fail(f, responseId) : readRun(f, String(responseId ?? ''));
  },
  [],
);

// One-call version (waits up to 100 s). Kept for older chat panels and quick tests; the current ChatPanel uses start/poll.
udf.func(
  'askRailAgent',
  async (ctx: RayfinContext<RailSchema, AudienceType.AzureAI>, question: string): Promise<string> => {
    const f = foundry(ctx);
    if (typeof f === 'string') return f;
    let state = await startRun(f, question);
    const deadline = Date.now() + MAX_WAIT_MS;
    while (state.status === 'working' && state.id) {
      if (Date.now() > deadline) {
        return 'The agent is still working on that (over 100 seconds). Try a narrower question, e.g. a shorter time window.';
      }
      await sleep(POLL_MS);
      state = await readRun(f, state.id);
    }
    return state.text;
  },
  [],
);

// ---- Lab 11b (optional): Azure Maps credential for the satellite/track map ----
// Returns the value of the Rayfin secret AZURE_MAPS_TOKEN, or { configured: false } if it isn't set (then the app shows the
// simple map). Intended value: an Azure Maps **SAS token** – made to be handed to a browser: it's scoped to map tiles,
// rate-limited and expires within 24 hours (scripts/new-azure-maps-sas.*). A subscription key also works for a quick
// test, but it never expires, so don't use one beyond that. Only signed-in app users can call this function.
// ctx.getSecret() (untyped, deprecated in Rayfin 1.36) is used on purpose: the secret is optional, so Lab 11 still builds
// and runs without it – the function just returns { configured: false } and the Lab 11 app never calls it. Your editor may
// show getSecret struck through as deprecated; that's expected.
udf.func(
  'getMapAuth',
  async (ctx: RayfinContext<RailSchema>): Promise<{ configured: boolean; authType: 'sas' | 'subscriptionKey' | 'none'; token: string }> => {
    const value = (ctx.getSecret('AZURE_MAPS_TOKEN') ?? '').trim();
    if (!value) return { configured: false, authType: 'none', token: '' };
    // SAS tokens are JWTs ("eyJ…"); anything else is treated as a subscription key.
    return { configured: true, authType: value.startsWith('eyJ') ? 'sas' : 'subscriptionKey', token: value };
  },
  [],
);
