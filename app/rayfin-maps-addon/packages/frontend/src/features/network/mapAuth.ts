// Lab 11b: gets the Azure Maps credential from the getMapAuth Rayfin function (secret AZURE_MAPS_TOKEN).
import { railFunctions } from '../../services/railClient';

export type MapAuth = { configured: boolean; authType: 'sas' | 'subscriptionKey' | 'none'; token: string };

let cache: { auth: MapAuth; at: number } | undefined;

export async function getMapAuth(force = false): Promise<MapAuth> {
  if (!force && cache && Date.now() - cache.at < 10 * 60_000) return cache.auth;
  const functions = await railFunctions();
  const auth: MapAuth = await functions.getMapAuth.invoke(undefined, { timeoutMs: 30_000 });
  cache = { auth, at: Date.now() };
  return auth;
}
