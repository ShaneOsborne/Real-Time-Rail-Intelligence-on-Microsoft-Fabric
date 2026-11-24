#!/usr/bin/env bash
# Shared helpers for bash scripts. Sourced, not executed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_env() {
  # Reads KEY=VALUE lines from the repo-root .env without executing them as shell code, so values
  # containing ';' (Event Hubs / Eventstream connection strings) work with or without quotes.
  # Windows (CRLF) line endings, blank lines and # comments are ignored; surrounding quotes are removed.
  # An unquoted value loses a trailing " # comment" (quote the value if it really contains " #").
  # If a key appears more than once, the LAST line wins (as in PowerShell and Docker); a warning names it.
  # Variables already set in the shell win over .env.
  local file="$REPO_ROOT/.env" line key val i j dup
  [[ -f "$file" ]] || return 0
  local -a keys=() vals=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "${line//[[:space:]]/}" || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"; key="${key//[[:space:]]/}"; key="${key#export}"
    val="${line#*=}"
    val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
    if [[ ${#val} -ge 2 && ( ( "${val:0:1}" == '"' && "${val: -1}" == '"' ) || ( "${val:0:1}" == "'" && "${val: -1}" == "'" ) ) ]]; then
      val="${val:1:${#val}-2}"
    elif [[ "${val:0:1}" != '"' && "${val:0:1}" != "'" && "$val" == *[[:space:]]#* ]]; then
      val="${val%%[[:space:]]#*}"; val="${val%"${val##*[![:space:]]}"}"
    fi
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    keys+=("$key"); vals+=("$val")
  done < "$file"
  # Walk backwards so the last occurrence of a key is the one exported.
  for (( i = ${#keys[@]} - 1; i >= 0; i-- )); do
    key="${keys[i]}"; val="${vals[i]}"
    dup=false
    for (( j = i + 1; j < ${#keys[@]}; j++ )); do [[ "${keys[j]}" == "$key" ]] && { dup=true; break; }; done
    if [[ "$dup" == "true" ]]; then
      echo "WARNING: $key is set more than once in .env; the last line is used. Delete the other lines." >&2
      continue
    fi
    if [[ "$val" == *'\$'* ]]; then
      echo "WARNING: $key in .env contains a backslash before \$. .env is read literally, so the backslash is sent too." >&2
      echo "         Remove the backslash (write the value exactly as it is, in single quotes if it has spaces or #)." >&2
    fi
    [[ -n "${!key+x}" ]] || export "$key=$val"
  done
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
