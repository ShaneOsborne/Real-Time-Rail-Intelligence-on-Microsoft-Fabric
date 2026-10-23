// Lab 11 adapter between the rail features and the Rayfin DEFAULT template's client.
//
// The default template (Rayfin 1.36 "Use default template" = Universal App workspace) creates ONE authenticated client
// behind its sign-in gate, and features get it with `await getRayfinClient()`. `npm run pack:add -- functions` wires the
// generated AppFunctionsSchema (from packages/functions/src/function_app.ts) into that client, so
// `client.functions.getNetworkSnapshot` and `client.functions.askRailAgent` are typed.
//
// The default template (Rayfin 1.36.x) exports getRayfinClient from packages/frontend/src/lib/rayfin-client.ts.
// If a later template moves it, find it with:  grep -rl "export.*getRayfinClient" packages/frontend/src
// and change the path below (relative to this services/ folder, without the .ts extension).
import { getRayfinClient } from '../lib/rayfin-client';

export async function railFunctions() {
  const client = await getRayfinClient();
  return client.functions;
}
