// Runs the NetworkSnapshot() KQL function (created in Lab 06) through the Kusto connector
// as the signed-in user (delegated auth only).
import { toQueryResult } from '@microsoft/rayfin-connector-kusto';
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

export async function loadSnapshot(lookback = '1h'): Promise<TrainPosition[]> {
  const clientRequestId = `KPC.rayfin_kusto_v1;${crypto.randomUUID()}`;
  const response = await client.connectors.rail.executeQuery({
    query: `NetworkSnapshot(${lookback}) | take 2000`,
    clientRequestId,
  });
  const result = toQueryResult(response, { clientRequestId });
  if (result.status === 'error') {
    throw new Error(`${result.error.message} (client request id ${result.clientRequestId})`);
  }
  return result.tables.slice(0, 1).flatMap((table) =>
    table.rows.map((row) => {
      const r = Object.fromEntries(table.columns.map((c, i) => [c.name, row[i]]));
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
    }),
  );
}
