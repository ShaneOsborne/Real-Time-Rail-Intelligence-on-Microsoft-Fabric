// Lab 11 – branded page layout: header with live status, KPI strip, map + chat, and the attribution footer.
// Branding (name, strapline, colours) lives in theme/brand.ts.
import type { CSSProperties, ReactNode } from 'react';
import './theme/rail.css';
import { BRAND } from './theme/brand';
import { KpiStrip } from './features/network/KpiStrip';
import { ChatPanel } from './features/chat/ChatPanel';
import { SNAPSHOT_REFRESH_SECONDS, useSnapshot } from './features/network/useSnapshot';

const c = BRAND.colours;
const cssVars = {
  '--rp-ink': c.ink,
  '--rp-ink-soft': c.inkSoft,
  '--rp-accent': c.accent,
  '--rp-accent-soft': c.accentSoft,
  '--rp-surface': c.surface,
  '--rp-canvas': c.canvas,
  '--rp-border': c.border,
  '--rp-late': c.late,
  '--rp-very-late': c.veryLate,
} as CSSProperties;

function Logo() {
  // Original mark: a track line with a pulse. Not a Network Rail / National Rail logo.
  return (
    <svg width="36" height="36" viewBox="0 0 36 36" aria-hidden="true">
      <rect width="36" height="36" rx="9" fill={c.accent} />
      <path d="M5 21h7l3-8 4 13 3-9 2 4h7" fill="none" stroke="#fff" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function LiveStatus() {
  const { updatedAt, error } = useSnapshot();
  const stale = updatedAt ? Date.now() - updatedAt.getTime() > SNAPSHOT_REFRESH_SECONDS * 2500 : false;
  const cls = error ? 'is-error' : stale || !updatedAt ? 'is-stale' : '';
  const label = error ? 'Data unavailable' : updatedAt ? `Live · ${updatedAt.toLocaleTimeString('en-GB')}` : 'Connecting…';
  return (
    <span className={`rp-live ${cls}`} title={error ?? `Refreshes every ${SNAPSHOT_REFRESH_SECONDS} seconds`}>
      <i className="rp-live-dot" /> {label}
    </span>
  );
}

export function AppShell({ map }: { map: ReactNode }) {
  return (
    <div className="rp" style={cssVars}>
      <header className="rp-header">
        <div className="rp-brand">
          <Logo />
          <div>
            <h1>{BRAND.name}</h1>
            <p>{BRAND.strapline}</p>
          </div>
        </div>
        <div className="rp-header-right">
          <LiveStatus />
          <span className="rp-badge">Demo · not an official service</span>
        </div>
      </header>
      <main className="rp-main">
        <KpiStrip />
        <div className="rp-grid">
          {map}
          <ChatPanel />
        </div>
      </main>
      <footer className="rp-footer">
        <span>Contains data from Network Rail Open Data / Rail Data Marketplace. Not an official service.</span>
        <span>Built on Microsoft Fabric Real-Time Intelligence, Azure AI Foundry and Fabric Apps.</span>
      </footer>
    </div>
  );
}
