// Lab 11 – headline figures computed in the browser from the same snapshot the map uses (no extra query).
import type { CSSProperties } from 'react';
import { BRAND } from '../../theme/brand';
import { useSnapshot } from './useSnapshot';

export function KpiStrip() {
  const { trains, loading } = useSnapshot();
  const total = trains.length;
  const late = trains.filter((t) => t.delayMinutes > 0 && t.delayMinutes < 15).length;
  const veryLate = trains.filter((t) => t.delayMinutes >= 15).length;
  const onTime = total - late - veryLate;
  const pct = total ? Math.round((onTime / total) * 100) : 0;
  const operators = new Set(trains.map((t) => t.tocId).filter(Boolean)).size;
  const dash = loading && !total ? '–' : undefined;

  const items = [
    { label: 'Active trains', value: dash ?? total.toLocaleString('en-GB'), note: 'reported in the last hour', colour: BRAND.colours.accent },
    { label: 'On time', value: dash ?? `${pct}%`, note: `${onTime.toLocaleString('en-GB')} trains`, colour: BRAND.colours.onTime },
    { label: 'Late', value: dash ?? late.toLocaleString('en-GB'), note: '1–14 minutes', colour: BRAND.colours.late },
    { label: 'Very late', value: dash ?? veryLate.toLocaleString('en-GB'), note: '15+ minutes', colour: BRAND.colours.veryLate },
    { label: 'Operators', value: dash ?? operators.toLocaleString('en-GB'), note: 'with trains running', colour: BRAND.colours.ink },
  ];

  return (
    <section className="rp-kpis" aria-label="Network summary">
      {items.map((k) => (
        <div key={k.label} className="rp-kpi" style={{ '--rp-kpi': k.colour } as CSSProperties}>
          <div className="rp-kpi-label">{k.label}</div>
          <div className="rp-kpi-value">{k.value}</div>
          <div className="rp-kpi-note">{k.note}</div>
        </div>
      ))}
    </section>
  );
}
