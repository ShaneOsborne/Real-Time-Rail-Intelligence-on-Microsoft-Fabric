# gb-rail.geojson goes here

`gb-rail.geojson` (GB railway lines, from OS Open Zoomstack, simplified) is built once with
`python app/tools/build_gb_rail.py` (Lab 11b, step 2) and committed to the lab repo. Vite serves files in `public/`
from the app root, so the map loads it from `<base URL>/data/gb-rail.geojson`.

Contains OS data © Crown copyright and database right. Open Government Licence v3.0.
