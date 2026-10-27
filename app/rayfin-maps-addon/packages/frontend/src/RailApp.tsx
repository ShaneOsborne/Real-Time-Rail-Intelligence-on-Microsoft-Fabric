// Lab 11b version of the app: uses the Azure Maps map when the AZURE_MAPS_TOKEN secret is set, otherwise the simple
// Lab 11 map. Same branded layout (AppShell). Render <RailApp /> from App.tsx as in Lab 11.
import { useEffect, useState } from 'react';
import { AppShell } from './AppShell';
import { NetworkMap } from './features/network/NetworkMap';
import { AzureNetworkMap } from './features/network/AzureNetworkMap';
import { getMapAuth } from './features/network/mapAuth';

export function RailApp() {
  const [mapKind, setMapKind] = useState<'loading' | 'azure' | 'simple'>('loading');

  useEffect(() => {
    getMapAuth()
      .then((a) => setMapKind(a.configured ? 'azure' : 'simple'))
      .catch(() => setMapKind('simple'));
  }, []);

  const map =
    mapKind === 'azure' ? (
      <AzureNetworkMap />
    ) : mapKind === 'simple' ? (
      <NetworkMap />
    ) : (
      <section className="rp-card">
        <div className="rp-map"><div className="rp-overlay">Loading map…</div></div>
      </section>
    );
  return <AppShell map={map} />;
}
