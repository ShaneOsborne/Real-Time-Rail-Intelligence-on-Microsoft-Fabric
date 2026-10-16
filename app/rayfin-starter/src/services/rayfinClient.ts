// Overlay file for a project scaffolded with `npm create @microsoft/rayfin@latest`.
// Pattern from https://rayfin.ai/docs/functions/calling-functions (Rayfin 1.36).
//
// Why no Kusto connector? Rayfin 1.36.2 holds new Kusto connector authoring:
//   `rayfin connector add --type kusto` fails with "Connector type "kusto" is not available in this release".
// So the map reads the Eventhouse through a Rayfin FUNCTION (getNetworkSnapshot in rayfin/functions/src/function_app.ts),
// which calls the KQL database's query endpoint with a delegated token (AudienceType.Kusto).
//
// Prerequisite (in the project root):  npx rayfin functions init
// types.js is GENERATED from function_app.ts when you build/deploy (npx rayfin up / npx rayfin dev).
import { RayfinClient } from '@microsoft/rayfin-client';
import type { AppSchema } from '../../rayfin/data/schema';
import type { AppFunctionsSchema } from '../../rayfin/functions/src/types.js';

export const client = new RayfinClient<AppSchema, AppFunctionsSchema>({
  baseUrl: import.meta.env.VITE_RAYFIN_API_URL,
  publishableKey: import.meta.env.VITE_RAYFIN_PUBLISHABLE_KEY,
});
