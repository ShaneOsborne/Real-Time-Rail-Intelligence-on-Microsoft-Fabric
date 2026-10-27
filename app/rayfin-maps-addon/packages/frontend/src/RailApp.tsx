// Lab 11b version of the app shell: uses the Azure Maps map when the AZURE_MAPS_TOKEN secret is set, otherwise falls back
// to the simple Lab 11 map. Render <RailApp /> from App.tsx as in Lab 11.
import { useEffect, useState } from 'react';
import { NetworkMap } from './features/network/NetworkMap';
import { AzureNetworkMap } from './features/network/AzureNetworkMap';
import { getMapAuth } from './features/network/mapAuth';
import { ChatPanel } from './features/chat/ChatPanel';

export function RailApp() {
  const [mapKind, setMapKind] = useState<'loading' | 'azure' | 'simple'>('loading');

  useEffect(() => {
    getMapAuth()
      .then((a) => setMapKind(a.configured ? 'azure' : 'simple'))
      .catch(() => setMapKind('simple'));
  }, []);

  return (
    <main style={{ display: 'grid', gridTemplateColumns: 'minmax(440px, 1.4fr) 1fr', gap: 24, padding: 24, fontFamily: 'Segoe UI, sans-serif' }}>
      {mapKind === 'azure' ? <AzureNetworkMap /> : mapKind === 'simple' ? <NetworkMap /> : <p>Loading map…</p>}
      <ChatPanel />
    </main>
  );
}
