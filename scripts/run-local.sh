#!/usr/bin/env bash
# Run the STOMP bridge locally.
#   ./scripts/run-local.sh venv   [console|file|eventstream] [--replay]
#   ./scripts/run-local.sh docker [console|file|eventstream] [--replay]
#   ./scripts/run-local.sh test
source "$(dirname "$0")/_common.sh"
load_env

MODE="${1:-venv}"
SINK="${2:-${BRIDGE_SINK:-console}}"
REPLAY="${3:-}"
BRIDGE_DIR="$REPO_ROOT/src/bridge"

extra_args=(--sink "$SINK")
if [[ "$REPLAY" == "--replay" ]]; then
  extra_args+=(--source replay --replay-file "$BRIDGE_DIR/tests/fixtures/replay_frames.json")
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
    echo "Usage: $0 {venv|docker|test} [console|file|eventstream] [--replay]" >&2
    exit 1
    ;;
esac
