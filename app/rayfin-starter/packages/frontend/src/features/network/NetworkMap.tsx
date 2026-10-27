// Lab 11 – dependency-free map: plots train positions (lat/lon) inside a Great Britain bounding box as SVG.
// Lab 11b swaps this for an Azure Maps map with satellite imagery and railway lines.
import { useState } from 'react';
import { delayColour, DELAY_BANDS } from '../../theme/brand';
import { useSnapshot } from './useSnapshot';
import type { TrainPosition } from './loadSnapshot';

const BOUNDS = { minLat: 49.9, maxLat: 58.7, minLon: -6.4, maxLon: 1.8 };
const W = 420;
const H = 640;
const x = (lon: number) => ((lon - BOUNDS.minLon) / (BOUNDS.maxLon - BOUNDS.minLon)) * W;
const y = (lat: number) => H - ((lat - BOUNDS.minLat) / (BOUNDS.maxLat - BOUNDS.minLat)) * H;

export function NetworkMap() {
  const { trains, error, loading } = useSnapshot();
  const [hover, setHover] = useState<TrainPosition | null>(null);
  const plotted = trains.filter((t) => Number.isFinite(t.lat) && Number.isFinite(t.lon));
  // Draw late trains last so they sit on top.
  const ordered = [...plotted].sort((a, b) => a.delayMinutes - b.delayMinutes);

  return (
    <section className="rp-card">
      <div className="rp-card-head">
        <h2>Live network map</h2>
        <span className="rp-sub">{plotted.length.toLocaleString('en-GB')} trains plotted</span>
      </div>
      {error && <div className="rp-alert" role="alert">{error}</div>}
      <div className="rp-map">
        <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="xMidYMid meet" role="img" aria-label="Map of trains in Great Britain">
          {ordered.map((t) => (
            <circle
              key={t.trainId}
              cx={x(t.lon)}
              cy={y(t.lat)}
              r={t.delayMinutes >= 15 ? 3.6 : 2.8}
              fill={delayColour(t.delayMinutes)}
              stroke="#fff"
              strokeWidth={0.6}
              onMouseEnter={() => setHover(t)}
              onMouseLeave={() => setHover(null)}
            >
              <title>{`${t.trainId} · ${t.location} · ${t.status} ${t.delayMinutes} min`}</title>
            </circle>
          ))}
        </svg>
        {loading && !plotted.length && <div className="rp-overlay">Loading live positions…</div>}
        {hover && (
          <div className="rp-msg agent" style={{ position: 'absolute', left: 12, bottom: 12, maxWidth: 260, fontSize: 12 }}>
            <strong>{hover.trainId}</strong> ({hover.tocId})<br />
            {hover.location}<br />
            {hover.status} · {hover.delayMinutes} min
          </div>
        )}
      </div>
      <div className="rp-legend">
        {DELAY_BANDS.map((b) => (
          <span key={b.key}>
            <i className="rp-swatch" style={{ background: b.colour }} /> {b.label}
          </span>
        ))}
      </div>
    </section>
  );
}
