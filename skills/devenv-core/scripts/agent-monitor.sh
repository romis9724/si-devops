#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
last_state=""
while true; do
  if [[ -f install.pid ]]; then
    pid="$(cat install.pid 2>/dev/null || true)"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      state="running:${pid}"
    else
      state="stopped"
    fi
  else
    state="idle"
  fi
  if [[ "${state}" != "${last_state}" ]]; then
    echo "${state}"
    last_state="${state}"
  fi
  sleep 2
done
