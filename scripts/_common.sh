#!/usr/bin/env bash
# Shared helpers for bash scripts. Sourced, not executed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_env() {
  if [[ -f "$REPO_ROOT/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$REPO_ROOT/.env"
    set +a
  fi
}

require() {
  local missing=0
  for v in "$@"; do
    if [[ -z "${!v:-}" ]]; then
      echo "ERROR: environment variable $v is required (set it in .env)" >&2
      missing=1
    fi
  done
  [[ $missing -eq 0 ]] || exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' is not installed or not on PATH" >&2; exit 1; }
}

log() { printf '\n==> %s\n' "$*"; }
