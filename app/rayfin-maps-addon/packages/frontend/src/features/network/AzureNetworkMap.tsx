// Lab 11b: live train map on Azure Maps – grayscale/road/night/satellite basemaps, GB railway lines from OS Open Zoomstack,
// and trains coloured by delay. Uses the shared snapshot (useSnapshot), so the KPIs and the map share one query.
import { useEffect, useRef, useState } from 'react';
import * as atlas from 'azure-maps-control';
import 'azure-maps-control/dist/atlas.min.css';
import { BRAND, DELAY_BANDS } from '../../theme/brand';
import { useSnapshot } from './useSnapshot';
import { getMapAuth } from './mapAuth';

const RAIL_URL = `${import.meta.env.BASE_URL}data/gb-rail.geojson`;
const STYLES = ['grayscale_light', 'road', 'night', 'grayscale_dark', 'satellite', 'satellite_road_labels'];
const c = BRAND.colours;

const esc = (v: unknown) =>
  String(v ?? '').replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch] ?? ch);

export function AzureNetworkMap() {
  const container = useRef<HTMLDivElement>(null);
  const trainSource = useRef<atlas.source.DataSource | null>(null);
  const [ready, setReady] = useState(false);
  const [mapError, setMapError] = useState<string | null>(null);
  const { trains, error, loading } = useSnapshot();

  // Create the map once.
  useEffect(() => {
    let disposed = false;
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

          // Railway lines (OS Open Zoomstack), under the map labels.
          const rail = new atlas.source.DataSource();
          map.sources.add(rail);
          rail.importDataFromUrl(RAIL_URL).catch(() => setMapError('Railway lines file not found (data/gb-rail.geojson). See Lab 11b.'));
          const width: atlas.Expression = ['interpolate', ['linear'], ['zoom'], 5, 0.6, 9, 1.5, 13, 3];
          map.layers.add(
            [
              new atlas.layer.LineLayer(rail, 'rail-open', { filter: ['!=', ['get', 'type'], 'Tunnel'], strokeColor: c.rail, strokeWidth: width }),
              new atlas.layer.LineLayer(rail, 'rail-tunnel', {
                filter: ['==', ['get', 'type'], 'Tunnel'],
                strokeColor: c.rail,
                strokeWidth: width,
                strokeDashArray: [2, 2],
              }),
            ],
            'labels',
          );

          // Trains.
          const trainsDs = new atlas.source.DataSource();
          map.sources.add(trainsDs);
          trainSource.current = trainsDs;
          const bubbles = new atlas.layer.BubbleLayer(trainsDs, 'trains', {
            radius: ['interpolate', ['linear'], ['zoom'], 5, 3, 10, 6, 14, 9],
            color: ['step', ['get', 'delay'], c.onTime, 1, c.late, 15, c.veryLate],
            strokeColor: '#ffffff',
            strokeWidth: 1,
          });
          map.layers.add(bubbles);

          const popup = new atlas.Popup({ pixelOffset: [0, -8] });
          map.events.add('click', bubbles, (e) => {
            const shape = e.shapes?.[0] as atlas.Shape | undefined;
            const p = shape?.getProperties();
            if (!p || !map || !shape) return;
            popup.setOptions({
              position: shape.getCoordinates() as atlas.data.Position,
              content: `<div style="padding:10px 12px;font:12px Segoe UI;color:${c.ink}">
                <div style="font-weight:600;font-size:13px">${esc(p.trainId)} <span style="color:#6b7a90">(${esc(p.tocId)})</span></div>
                <div>${esc(p.location)}</div>
                <div>${esc(p.status)} · ${esc(p.delay)} min</div>
                <div style="color:#6b7a90">${esc(p.eventTime)}</div></div>`,
            });
            popup.open(map);
          });
          setReady(true);
        });
        map.events.add('error', (e) => !disposed && setMapError(`Map error: ${String((e as { error?: unknown }).error ?? e)}`));
      } catch (e) {
        if (!disposed) setMapError(e instanceof Error ? e.message : String(e));
      }
    })();

    return () => {
      disposed = true;
      trainSource.current = null;
      map?.dispose();
    };
  }, []);

  // Update the trains whenever the shared snapshot refreshes.
  useEffect(() => {
    if (!ready || !trainSource.current) return;
    trainSource.current.setShapes(
      trains
        .filter((t) => Number.isFinite(t.lat) && Number.isFinite(t.lon))
        .sort((a, b) => a.delayMinutes - b.delayMinutes)
        .map(
          (t) =>
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
  }, [trains, ready]);

  const shown = mapError ?? error;
  return (
    <section className="rp-card">
      <div className="rp-card-head">
        <h2>Live network map</h2>
        <span className="rp-sub">{trains.length.toLocaleString('en-GB')} trains · click a train for details</span>
      </div>
      {shown && <div className="rp-alert" role="alert">{shown}</div>}
      <div className="rp-map">
        <div ref={container} style={{ position: 'absolute', inset: 0 }} />
        {(loading || !ready) && !trains.length && !mapError && <div className="rp-overlay">Loading map…</div>}
      </div>
      <div className="rp-legend">
        {DELAY_BANDS.map((b) => (
          <span key={b.key}>
            <i className="rp-swatch" style={{ background: b.colour }} /> {b.label}
          </span>
        ))}
        <span>
          <i className="rp-swatch-line" style={{ background: c.rail }} /> Railway (dashed: tunnel)
        </span>
        <span style={{ marginLeft: 'auto', color: '#6b7a90' }}>
          Railway lines: contains OS data © Crown copyright and database right {new Date().getFullYear()} · Basemap © Microsoft
        </span>
      </div>
    </section>
  );
}
