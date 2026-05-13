#!/usr/bin/env bash
set -euo pipefail
WIN_USER="${1:-$USER}"
SRC="/mnt/c/Users/${WIN_USER}/AppData/Roaming/Claude/local-agent-mode-sessions/skills-plugin"
DST="/mnt/c/Users/${WIN_USER}/Documents/project/devenv/core/skill"
if ! ls "${SRC}" >/dev/null 2>&1; then
  mkdir -p "${DST}"
  rsync -a ./ "${DST}/"
  export SKILL_PATH="${DST}"
else
  export SKILL_PATH="${SRC}"
fi
echo "SKILL_PATH=${SKILL_PATH}"
