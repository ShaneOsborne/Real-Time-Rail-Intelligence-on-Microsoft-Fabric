// Dependency-free map: plots train positions (lat/lon) inside a Great Britain bounding box as SVG.
// Swap for a tile-based map library later if you need a basemap.
import { useEffect, useState } from 'react';
import { loadSnapshot, type TrainPosition } from './loadSnapshot';

const BOUNDS = { minLat: 49.9, maxLat: 58.7, minLon: -6.4, maxLon: 1.8 };
const W = 420;
const H = 640;

function colour(delay: number): string {
  if (delay >= 15) return '#d13438';
  if (delay > 0) return '#ffaa44';
  return '#107c10';
}

export function NetworkMap({ refreshMs = 30000 }: { refreshMs?: number }) {
  const [trains, setTrains] = useState<TrainPosition[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    const load = () =>
      loadSnapshot()
        .then((t) => {
          if (active) {
            setTrains(t);
            setError(null);
          }
        })
        .catch((e: unknown) => {
          if (active) setError(String(e));
        });
    load();
    const id = setInterval(load, refreshMs);
    return () => {
      active = false;
      clearInterval(id);
    };
  }, [refreshMs]);

  const x = (lon: number) => ((lon - BOUNDS.minLon) / (BOUNDS.maxLon - BOUNDS.minLon)) * W;
  const y = (lat: number) => H - ((lat - BOUNDS.minLat) / (BOUNDS.maxLat - BOUNDS.minLat)) * H;

  return (
    <section>
      <h2>Live network ({trains.length} trains)</h2>
      {error && <p role="alert">{error}</p>}
      <svg width={W} height={H} style={{ background: '#eef3f8', borderRadius: 8 }}>
        {trains
          .filter((t) => Number.isFinite(t.lat) && Number.isFinite(t.lon))
          .map((t) => (
            <circle key={t.trainId} cx={x(t.lon)} cy={y(t.lat)} r={3} fill={colour(t.delayMinutes)}>
              <title>{`${t.trainId} ${t.status} ${t.delayMinutes} min – ${t.location}`}</title>
            </circle>
          ))}
      </svg>
      <p style={{ fontSize: 12 }}>
        Contains data from Network Rail Open Data / Rail Data Marketplace. Not an official service.
      </p>
    </section>
  );
}
