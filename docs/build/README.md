# Part 2 – the build

Everyone does the same build, whichever Part 1 path you followed ([solo](../solo/README.md),
[instructor](../instructor/README.md) or [student](../student/README.md)). Start once data is arriving in `RawFeed` and
`RdmTrustRaw`.

| Page | What it covers | Time | Automated? |
|---|---|---|---|
| [Lab 2.1 – KQL transformations](2.1-kql-transformations.md) | KQL tables, update policies, materialized views, functions | 40 min | ✅ `apply_kql.py` |
| [Lab 2.2 – Activator alerts](2.2-activator-alerts.md) | Late trains, cancellation spikes, stalled feed, PPM | 30 min | Manual (portal) |
| [Lab 2.3 – Real-Time Dashboard and Power BI report](2.3-dashboard-powerbi.md) | Live dashboard tiles, DirectQuery and Direct Lake report | 45 min | Manual (queries supplied) |
| [Lab 2.4 – Fabric data agent](2.4-fabric-data-agent.md) | Data agent with instructions and example queries | 30 min | Manual (content supplied) |
| [Lab 2.5 – Rail ontology](2.5-rail-ontology.md) (optional) | Fabric IQ ontology and a data agent grounded in it, compared with Lab 2.4 | 50 min | ✅ `09_ontology_tables.kql`; ontology via the ontology agent or by hand |
| [Lab 2.6 – Foundry agent](2.6-foundry-agent.md) | Foundry agent with the Fabric IQ (OneLake Catalog) tool and a Python client | 30 min | ✅ `foundry/agent_client.py` (after the portal steps) |
| [Lab 2.7 – Live semantic model](2.7-live-semantic-model.md) | DirectQuery model over `NetworkSnapshot` for the app map | 25 min | Manual (Power BI Desktop or web) |
| [Lab 2.8 – Rayfin app](2.8-rayfin-app.md) | RailPulse: live map and "chat with the network" | 60 min | CLI + overlay code |
| [Lab 2.9 – Azure Maps](2.9-azure-maps.md) (optional) | Azure Maps basemap, satellite view and railway lines | 45 min | ✅ `create-azure-maps.sh/.ps1`, `new-azure-maps-sas.sh/.ps1` |
| [Lab 2.10 – Clean-up](2.10-cleanup.md) | Stop spending, delete resources | 10 min | ✅ `cleanup.sh/.ps1` |
