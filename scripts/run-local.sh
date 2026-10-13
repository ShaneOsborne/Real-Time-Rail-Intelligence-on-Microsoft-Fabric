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

# --- Python virtual environment (works on Linux, macOS and Windows Git Bash) ---------------
# Windows Python puts the activate script in .venv/Scripts, Linux/macOS in .venv/bin.
pick_python() {
  local c
  for c in python3 python py; do
    # Skip the Windows Store "python3" stub, which exists but doesn't run.
    if command -v "$c" >/dev/null 2>&1 && "$c" -c "import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)" >/dev/null 2>&1; then
      PYTHON="$c"; return 0
    fi
  done
  echo "ERROR: Python 3.11+ not found. Install it (Lab 01, step 6) and make sure 'python' or 'python3' is on PATH." >&2
  exit 1
}

activate_venv() {
  local requirements="$1"
  pick_python
  # Re-create a missing or half-created venv (for example after an earlier failed run)
  if [[ ! -f .venv/bin/activate && ! -f .venv/Scripts/activate ]]; then
    [[ -d .venv ]] && { log "Removing incomplete virtual environment"; rm -rf .venv; }
    log "Creating virtual environment in src/bridge/.venv (using $PYTHON)"
    "$PYTHON" -m venv .venv
  fi
  if [[ -f .venv/bin/activate ]]; then
    # shellcheck disable=SC1091
    source .venv/bin/activate
  else
    # shellcheck disable=SC1091
    source .venv/Scripts/activate
  fi
  log "Installing dependencies from $requirements"
  python -m pip install --quiet --disable-pip-version-check -r "$requirements"
}

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
    cd "$BRIDGE_DIR"
    activate_venv requirements.txt
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
    cd "$BRIDGE_DIR"
    activate_venv requirements-dev.txt
    exec python -m pytest -q
    ;;
  *)
    echo "Usage: $0 {venv|docker|test} [console|file|eventstream|eventhub] [--replay|--kafka]" >&2
    exit 1
    ;;
esac
