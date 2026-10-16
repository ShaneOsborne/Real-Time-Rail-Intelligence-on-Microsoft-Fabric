// Loads the latest position of every active train by calling the getNetworkSnapshot Rayfin function,
// which runs NetworkSnapshot() (Lab 06) on the Eventhouse as the signed-in user.
import { client } from '../../services/rayfinClient';

export type TrainPosition = {
  trainId: string;
  tocId: string;
  eventTime: string;
  eventType: string;
  delayMinutes: number;
  status: string;
  location: string;
  lat: number;
  lon: number;
};

export async function loadSnapshot(lookbackMinutes = 60): Promise<TrainPosition[]> {
  const rows = await client.functions.getNetworkSnapshot.invoke({ lookbackMinutes }, { timeoutMs: 60_000 });
  return rows.map((r) => ({
    trainId: String(r.train_id ?? ''),
    tocId: String(r.toc_id ?? ''),
    eventTime: String(r.event_time ?? ''),
    eventType: String(r.event_type ?? ''),
    delayMinutes: Number(r.delay_minutes ?? 0),
    status: String(r.variation_status ?? ''),
    location: String(r.location_name ?? ''),
    lat: Number(r.lat),
    lon: Number(r.lon),
  }));
}
