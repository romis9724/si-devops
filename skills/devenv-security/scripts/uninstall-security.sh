#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.security.yml"
KEEP_VOLUMES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-volumes) KEEP_VOLUMES=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ "${KEEP_VOLUMES}" -eq 1 ]]; then
  docker compose -f "${COMPOSE_FILE}" down
else
  echo "[DECISION-POINT] volume deletion requested"
  docker compose -f "${COMPOSE_FILE}" down -v
fi

echo "security stack uninstalled"
