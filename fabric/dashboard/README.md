# Real-Time Dashboard & Power BI assets

* `queries.kql` – one query per tile for the Fabric **Real-Time Dashboard** (Lab 08). Tiles are added manually;
  the dashboard JSON definition is not generated here because hand-authoring it is error-prone.
* Power BI: build the report in Power BI Desktop / the service against the KQL database
  (DirectQuery for live tiles with automatic page refresh) and against the Lakehouse/OneLake copy for history
  (Direct Lake). See `docs/labs/08-dashboard-powerbi.md`.
