#!/usr/bin/env bash
# Shared helpers for bash scripts. Sourced, not executed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_env() {
  # Reads KEY=VALUE lines from the repo-root .env without executing them as shell code, so values
  # containing ';' (Event Hubs / Eventstream connection strings) work with or without quotes.
  # Windows (CRLF) line endings, blank lines and # comments are ignored; surrounding quotes are removed.
  local file="$REPO_ROOT/.env" line key val
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "${line//[[:space:]]/}" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"; key="${key//[[:space:]]/}"; key="${key#export}"
    val="${line#*=}"
    val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
    if [[ ${#val} -ge 2 && ( ( "${val:0:1}" == '"' && "${val: -1}" == '"' ) || ( "${val:0:1}" == "'" && "${val: -1}" == "'" ) ) ]]; then
      val="${val:1:${#val}-2}"
    fi
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    # Variables already set in the shell win over .env
    [[ -n "${!key+x}" ]] || export "$key=$val"
  done < "$file"
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
