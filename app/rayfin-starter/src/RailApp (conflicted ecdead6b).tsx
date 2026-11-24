// Compose the two panels; render <RailApp /> from the scaffold's root component (e.g. src/App.tsx).
// Sign-in uses Fabric SSO as configured by the scaffold (see https://rayfin.ai/docs/auth/fabric-sso).
import { NetworkMap } from './features/network/NetworkMap';
import { ChatPanel } from './features/chat/ChatPanel';

export function RailApp() {
  return (
    <main style={{ display: 'grid', gridTemplateColumns: '440px 1fr', gap: 24, padding: 24, fontFamily: 'Segoe UI, sans-serif' }}>
      <NetworkMap />
      <ChatPanel />
    </main>
  );
}
