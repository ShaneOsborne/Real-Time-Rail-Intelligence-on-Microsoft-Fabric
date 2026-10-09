#!/usr/bin/env bash
# Run the STOMP bridge locally.
#   ./scripts/run-local.sh venv   [console|file|eventstream|eventhub] [--replay|--kafka]
#   ./scripts/run-local.sh docker [console|file|eventstream|eventhub] [--replay|--kafka]
#   ./scripts/run-local.sh test
# --kafka runs the optional RDM Kafka relay (BRIDGE_SOURCE=kafka, Lab 05c) instead of the NROD STOMP source.
source "$(dirname "$0")/_common.sh"
load_env

MODE="${1:-venv}"
SINK="${2:-${BRIDGE_SINK:-console}}"
REPLAY="${3:-}"   # --replay or --kafka
BRIDGE_DIR="$REPO_ROOT/src/bridge"

extra_args=(--sink "$SINK")
if [[ "$REPLAY" == "--replay" ]]; then
  extra_args+=(--source replay --replay-file "$BRIDGE_DIR/tests/fixtures/replay_frames.json")
elif [[ "$REPLAY" == "--kafka" ]]; then
  extra_args+=(--source kafka)
  # The relay sends to the rdm-trust hub, not the nrod-feed hub used by the NROD bridge.
  export EVENTHUB_CONNECTION_STRING="${EVENTHUB_RDM_CONNECTION_STRING:-}"
fi

case "$MODE" in
  venv)
    need_cmd python3
    cd "$BRIDGE_DIR"
    if [[ ! -d .venv ]]; then
      log "Creating virtual environment in src/bridge/.venv"
      python3 -m venv .venv
    fi
    # shellcheck disable=SC1091
    source .venv/bin/activate
    pip install --quiet -r requirements.txt
    log "Starting bridge (sink=$SINK) - Ctrl+C to stop"
    exec python -m rail_bridge "${extra_args[@]}"
    ;;
  docker)
    need_cmd docker
    cd "$BRIDGE_DIR"
    if [[ "$REPLAY" == "--replay" ]]; then
      log "Starting offline replay container"
      exec docker compose --profile offline up --build replay
    fi
    if [[ "$REPLAY" == "--kafka" ]]; then
      log "Starting RDM Kafka relay container (sink=$SINK)"
      export RELAY_SINK="$SINK"
      exec docker compose --profile relay up --build rdm-relay
    fi
    mkdir -p out && chmod a+rwx out   # container runs as uid 10001
    log "Starting bridge container (sink=$SINK)"
    export BRIDGE_SINK="$SINK"
    exec docker compose up --build bridge
    ;;
  test)
    need_cmd python3
    cd "$BRIDGE_DIR"
    [[ -d .venv ]] || python3 -m venv .venv
    # shellcheck disable=SC1091
    source .venv/bin/activate
    pip install --quiet -r requirements-dev.txt
    exec python -m pytest -q
    ;;
  *)
    echo "Usage: $0 {venv|docker|test} [console|file|eventstream|eventhub] [--replay|--kafka]" >&2
    exit 1
    ;;
esac
