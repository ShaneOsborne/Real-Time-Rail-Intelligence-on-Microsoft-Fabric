// Lab 11 adapter between the rail features and the Rayfin DEFAULT template's client.
//
// The default template (Rayfin 1.36 "Use default template" = Universal App workspace) creates ONE authenticated client
// behind its sign-in gate, and features get it with `await getRayfinClient()`. `npm run pack:add -- functions` wires the
// generated AppFunctionsSchema (from packages/functions/src/function_app.ts) into that client, so
// `client.functions.getNetworkSnapshot` and `client.functions.askRailAgent` are typed.
//
// ONE EDIT NEEDED: point the import below at the template module that exports getRayfinClient. Find it with:
//   grep -rl "export.*getRayfinClient" packages/frontend/src
// For example, if that prints packages/frontend/src/services/rayfin.ts, the import is './rayfin'.
import { getRayfinClient } from './rayfin'; // <-- EDIT this path if grep shows a different file

export async function railFunctions() {
  const client = await getRayfinClient();
  return client.functions;
}
