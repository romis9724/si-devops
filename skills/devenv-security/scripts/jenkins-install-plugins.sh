#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/lib/jenkins.sh"

PLUGINS=(
  "sonar:2.18.2"
  "dependency-check-jenkins-plugin:5.4.5"
)

xml_payload="<jenkins>"
for plugin in "${PLUGINS[@]}"; do
  xml_payload="${xml_payload}<install plugin=\"${plugin}\" />"
done
xml_payload="${xml_payload}</jenkins>"

jenkins_post "/pluginManager/installNecessaryPlugins" \
  -H "Content-Type: text/xml" \
  --data-binary "${xml_payload}" >/dev/null

echo "[PHASE-DONE] {phase:6, state:ok, services:jenkins-plugins, duration_s:0, errors:[]}"
