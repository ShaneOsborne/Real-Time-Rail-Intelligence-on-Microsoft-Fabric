// Loads the latest position of every active train from the Lab 10b semantic model "RailLiveMap" (DirectQuery over
// NetworkSnapshot(4h) in RailKQL) through the Rayfin fabric-semanticmodel connector. Runs as the signed-in user.
import { railMap } from '../../services/railClient';

// The table name in the semantic model (Lab 10b). Change it if your model's table has another name.
const MODEL_TABLE = 'TrainPositions';

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

// Fixed DAX: only the look-back (validated number) is inserted, so users can't send arbitrary queries.
function daxQuery(lookbackMinutes: number): string {
  const t = `'${MODEL_TABLE}'`;
  return `
EVALUATE
SELECTCOLUMNS(
  FILTER(${t}, ${t}[event_time] >= NOW() - ${lookbackMinutes} / 1440 && NOT ISBLANK(${t}[lat])),
  "train_id", ${t}[train_id],
  "toc_id", ${t}[toc_id],
  "event_time", ${t}[event_time],
  "event_type", ${t}[event_type],
  "delay_minutes", ${t}[delay_minutes],
  "variation_status", ${t}[variation_status],
  "location_name", ${t}[location_name],
  "lat", ${t}[lat],
  "lon", ${t}[lon]
)`;
}

// Power BI returns column names such as "[train_id]" or "TrainPositions[train_id]"; keep just train_id.
const plainName = (name: string) => name.replace(/^.*\[/, '').replace(/\]$/, '');

export async function loadSnapshot(lookbackMinutes = 60): Promise<TrainPosition[]> {
  const minutes = Math.round(lookbackMinutes);
  if (!Number.isFinite(minutes) || minutes < 5 || minutes > 240) {
    throw new Error('lookbackMinutes must be between 5 and 240');
  }
  const map = await railMap();
  const result = await map.executeQuery({ query: daxQuery(minutes), resultSetRowCountLimit: 5000 });
  if (result.status === 'error') {
    const hint = result.error.recoveryHint ? ` ${result.error.recoveryHint}` : '';
    throw new Error(`Map query failed (${result.error.category}): ${result.error.message}${hint} [request ${result.requestId}]`);
  }
  const names = result.table.columns.map((c) => plainName(c.name));
  return result.table.rows.map((row) => {
    const r = Object.fromEntries(names.map((n, i) => [n, row[i]]));
    return {
      trainId: String(r.train_id ?? ''),
      tocId: String(r.toc_id ?? ''),
      eventTime: String(r.event_time ?? ''),
      eventType: String(r.event_type ?? ''),
      delayMinutes: Number(r.delay_minutes ?? 0),
      status: String(r.variation_status ?? ''),
      location: String(r.location_name ?? ''),
      lat: Number(r.lat),
      lon: Number(r.lon),
    };
  });
}
