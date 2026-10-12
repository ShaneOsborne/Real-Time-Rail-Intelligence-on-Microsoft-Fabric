Lab 04b (Darwin Push Port) update - changed and added files
Copy the contents of this folder over the root of your rail-fabric-rti clone (paths are repo-relative).
docs/labs/04-rdm-kafka-eventstream.md has Windows (CRLF) line endings; all other files use LF.

Added:
  docs/labs/04b-darwin-push-port.md
Modified:
  .env.example
  README.md
  docs/labs/00-overview.md
  docs/labs/01-prerequisites.md
  docs/labs/02-fabric-workspace.md
  docs/labs/04-rdm-kafka-eventstream.md
  docs/labs/05c-shared-event-hub.md
  docs/labs/06-kql-transformations.md
  docs/labs/08-dashboard-powerbi.md
  docs/labs/09-fabric-data-agent.md
  fabric/dashboard/queries.kql
  fabric/data-agent/example-queries.json
  fabric/data-agent/instructions.md
  fabric/kql/01_tables.kql
  fabric/kql/02_update_policies.kql
  fabric/kql/04_query_functions.kql
  fabric/kql/08_backfill.kql
  scripts/fabric-setup.ps1
  scripts/fabric-setup.sh

After copying: re-run fabric/kql/01_tables.kql, then 02_update_policies.kql, then 04_query_functions.kql
(python fabric/scripts/apply_kql.py runs 01-04 in order).
