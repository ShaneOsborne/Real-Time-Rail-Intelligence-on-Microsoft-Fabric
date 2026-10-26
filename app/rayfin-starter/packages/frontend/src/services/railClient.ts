// Lab 11 adapter between the rail features and the Rayfin DEFAULT template's client.
//
// The default template (Rayfin 1.36 "Use default template" = Universal App workspace) creates ONE authenticated client
// behind its sign-in gate, and features get it with `await getRayfinClient()`.
//  * `npm run pack:add -- functions` wires AppFunctionsSchema (from packages/functions/src/function_app.ts) into it,
//    so `client.functions.askRailAgent` is typed.
//  * `npm run pack:add -- connectors` plus `npx rayfin connector add ... --name railmap` wire the Lab 10b semantic model
//    into it (generated packages/frontend/src/lib/connectors.ts), so `client.connectors.railmap.executeQuery` is typed.
//
// The 1.36.x default template exports getRayfinClient from packages/frontend/src/lib/rayfin-client.ts.
// If a later template moves it, find it with:  grep -rl "export.*getRayfinClient" packages/frontend/src
// and change the path below (relative to this services/ folder, without the .ts extension).
import { getRayfinClient } from '../lib/rayfin-client';

export async function railFunctions() {
  const client = await getRayfinClient();
  return client.functions;
}

// The semantic model connector. The name MUST be the --name you gave `rayfin connector add` (lower-case): railmap.
export async function railMap() {
  const client = await getRayfinClient();
  return client.connectors.railmap;
}
