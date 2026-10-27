// Lab 11 – the app. In packages/frontend/src/App.tsx, replace the template's <EmptyStatePreview /> with <RailApp />
// (and its import with `import { RailApp } from './RailApp';`). Sign-in stays with the template's auth gate.
// Layout and branding: AppShell.tsx and theme/brand.ts.
import { AppShell } from './AppShell';
import { NetworkMap } from './features/network/NetworkMap';

export function RailApp() {
  return <AppShell map={<NetworkMap />} />;
}
