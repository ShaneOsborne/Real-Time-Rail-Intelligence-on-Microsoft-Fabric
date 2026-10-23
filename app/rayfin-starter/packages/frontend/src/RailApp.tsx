// Compose the two panels. In packages/frontend/src/App.tsx, replace the template's <EmptyStatePreview /> with <RailApp />
// (and its import with `import { RailApp } from './RailApp';`). Sign-in stays with the template's auth gate.
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
