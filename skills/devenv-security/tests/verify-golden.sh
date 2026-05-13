#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOLDEN_DIR="${ROOT_DIR}/tests/golden"

check_file() {
  local file="$1"
  if [[ ! -s "${GOLDEN_DIR}/${file}" ]]; then
    echo "missing or empty: ${file}" >&2
    return 1
  fi
  if ! grep -Eq "\\[PHASE|\\[DONE\\]" "${GOLDEN_DIR}/${file}"; then
    echo "invalid golden format: ${file}" >&2
    return 1
  fi
}

for phase in {1..8}; do
  check_file "phase${phase}.txt"
done

echo "golden verification passed"
