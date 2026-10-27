// Lab 11b: live train map on Azure Maps – road/grayscale/night/satellite basemaps, GB railway lines from OS Open Zoomstack,
// and trains coloured by delay (green on time, amber late, red 15+ min). Same data as Lab 11 (loadSnapshot → RailLiveMap).
import { useEffect, useRef, useState } from 'react';
import * as atlas from 'azure-maps-control';
import 'azure-maps-control/dist/atlas.min.css';
import { loadSnapshot } from './loadSnapshot';
import { getMapAuth } from './mapAuth';

const RAIL_URL = `${import.meta.env.BASE_URL}data/gb-rail.geojson`;
const esc = (v: unknown) =>
  String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c] ?? c);
const STYLES = ['grayscale_light', 'road', 'night', 'grayscale_dark', 'satellite', 'satellite_road_labels'];

export function AzureNetworkMap({ refreshMs = 30000, lookbackMinutes = 60 }: { refreshMs?: number; lookbackMinutes?: number }) {
  const container = useRef<HTMLDivElement>(null);
  const [count, setCount] = useState(0);
  const [updated, setUpdated] = useState<string>('');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let disposed = false;
    let timer: ReturnType<typeof setInterval> | undefined;
    let map: atlas.Map | undefined;

    (async () => {
      try {
        const auth = await getMapAuth();
        if (!auth.configured) throw new Error('Azure Maps is not configured (secret AZURE_MAPS_TOKEN). See Lab 11b.');
        if (disposed || !container.current) return;

        map = new atlas.Map(container.current, {
          center: [-2.6, 54.4],
          zoom: 5.3,
          style: 'grayscale_light',
          language: 'en-GB',
          view: 'Auto',
          authOptions:
            auth.authType === 'sas'
              ? {
                  authType: atlas.AuthenticationType.sas,
                  // Called again when the token nears expiry; the function returns the current secret value.
                  getToken: (resolve, reject) => {
                    getMapAuth(true).then((a) => resolve(a.token)).catch(reject);
                  },
                }
              : { authType: atlas.AuthenticationType.subscriptionKey, subscriptionKey: auth.token },
        });

        map.events.add('ready', () => {
          if (!map || disposed) return;
          map.controls.add(
            [new atlas.control.StyleControl({ mapStyles: STYLES }), new atlas.control.ZoomControl()],
            { position: atlas.ControlPosition.TopRight },
          );

          // Railway lines (OS Open Zoomstack) – drawn under the map labels.
          const rail = new atlas.source.DataSource();
          map.sources.add(rail);
          rail.importDataFromUrl(RAIL_URL).catch(() => setError('Railway lines file not found (data/gb-rail.geojson). See Lab 11b.'));
          const width: atlas.Expression = ['interpolate', ['linear'], ['zoom'], 5, 0.6, 9, 1.5, 13, 3];
          map.layers.add(
            [
              new atlas.layer.LineLayer(rail, 'rail-open', {
                filter: ['!=', ['get', 'type'], 'Tunnel'],
                strokeColor: '#5c2d91',
                strokeWidth: width,
              }),
              new atlas.layer.LineLayer(rail, 'rail-tunnel', {
                filter: ['==', ['get', 'type'], 'Tunnel'],
                strokeColor: '#5c2d91',
                strokeWidth: width,
                strokeDashArray: [2, 2],
              }),
            ],
            'labels',
          );

          // Trains.
          const trains = new atlas.source.DataSource();
          map.sources.add(trains);
          const bubbles = new atlas.layer.BubbleLayer(trains, 'trains', {
            radius: ['interpolate', ['linear'], ['zoom'], 5, 3, 10, 6, 14, 9],
            color: ['step', ['get', 'delay'], '#107c10', 1, '#ffaa44', 15, '#d13438'],
            strokeColor: '#ffffff',
            strokeWidth: 1,
          });
          map.layers.add(bubbles);

          const popup = new atlas.Popup({ pixelOffset: [0, -8] });
          map.events.add('click', bubbles, (e) => {
            const p = (e.shapes?.[0] as atlas.Shape | undefined)?.getProperties();
            if (!p || !map) return;
            popup.setOptions({
              position: (e.shapes![0] as atlas.Shape).getCoordinates() as atlas.data.Position,
              content: `<div style="padding:8px;font:12px Segoe UI">
                <b>${esc(p.trainId)}</b> (${esc(p.tocId)})<br/>${esc(p.location)}<br/>
                ${esc(p.status)} – ${esc(p.delay)} min<br/><span style="color:#666">${esc(p.eventTime)}</span></div>`,
            });
            popup.open(map);
          });

          const load = () =>
            loadSnapshot(lookbackMinutes)
              .then((rows) => {
                if (disposed) return;
                trains.setShapes(
                  rows
                    .filter((t) => Number.isFinite(t.lat) && Number.isFinite(t.lon))
                    .map((t) =>
                      new atlas.data.Feature(new atlas.data.Point([t.lon, t.lat]), {
                        trainId: t.trainId,
                        tocId: t.tocId,
                        location: t.location,
                        status: t.status,
                        delay: t.delayMinutes,
                        eventTime: t.eventTime,
                      }),
                    ),
                );
                setCount(rows.length);
                setUpdated(new Date().toLocaleTimeString('en-GB'));
                setError(null);
              })
              .catch((e: unknown) => !disposed && setError(String(e)));
          load();
          timer = setInterval(load, refreshMs);
        });
        map.events.add('error', (e) => !disposed && setError(`Map error: ${String((e as { error?: unknown }).error ?? e)}`));
      } catch (e) {
        if (!disposed) setError(String(e));
      }
    })();

    return () => {
      disposed = true;
      if (timer) clearInterval(timer);
      map?.dispose();
    };
  }, [refreshMs, lookbackMinutes]);

  return (
    <section>
      <h2>
        Live network ({count} trains){updated && <span style={{ fontSize: 12, fontWeight: 400 }}> · updated {updated}</span>}
      </h2>
      {error && <p role="alert">{error}</p>}
      <div ref={container} style={{ width: '100%', minWidth: 420, height: 640, borderRadius: 8, overflow: 'hidden' }} />
      <p style={{ fontSize: 12 }}>
        <span style={{ color: '#107c10' }}>●</span> on time&nbsp;&nbsp;<span style={{ color: '#ffaa44' }}>●</span> late&nbsp;&nbsp;
        <span style={{ color: '#d13438' }}>●</span> 15+ min late&nbsp;&nbsp;<span style={{ color: '#5c2d91' }}>━</span> railway (dashed: tunnel)
      </p>
      <p style={{ fontSize: 12 }}>
        Contains data from Network Rail Open Data / Rail Data Marketplace. Not an official service. Railway lines: contains OS
        data © Crown copyright and database right {new Date().getFullYear()}. Basemap © Microsoft Azure Maps.
      </p>
    </section>
  );
}
