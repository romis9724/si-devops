#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_LIB="${ROOT_DIR}/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "${COMMON_LIB}"
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/lib/jenkins.sh"

PROJECT_NAME="${PROJECT_NAME:-devenv}"
SECRETS_ENV="$(devenv_secrets_env_file "${PROJECT_NAME}")"
if [[ -f "${SECRETS_ENV}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${SECRETS_ENV}"
  set +a
fi

SONAR_NAME="${SONAR_NAME:-sonarqube}"
SONAR_URL="${SONAR_URL:-http://localhost:9000}"
SONAR_CREDENTIALS_ID="${SONAR_CREDENTIALS_ID:-sonar-token}"
JENKINS_PUBLIC_URL="${JENKINS_PUBLIC_URL:-http://localhost:8080}"
SONAR_ADMIN_USER="${SONAR_ADMIN_USER:-admin}"
SONAR_ADMIN_PASSWORD="${SONAR_ADMIN_PASSWORD:-changeme}"
SONAR_WEBHOOK_NAME="${SONAR_WEBHOOK_NAME:-jenkins-qualitygate}"

export SONAR_NAME SONAR_URL SONAR_CREDENTIALS_ID

GROOVY_SCRIPT="$(cat <<'GROOVY'
import hudson.plugins.sonar.SonarGlobalConfiguration
import hudson.plugins.sonar.SonarInstallation
import hudson.plugins.sonar.model.TriggersConfig
import hudson.util.Secret
import jenkins.model.Jenkins
import java.lang.reflect.Array

final String NAME = System.getenv("SONAR_NAME") ?: "sonarqube"
final String URL = System.getenv("SONAR_URL") ?: "http://sonarqube:9000"
final String CRED_ID = System.getenv("SONAR_CREDENTIALS_ID") ?: "sonar-token"

def descriptor = Jenkins.instance.getDescriptorByType(SonarGlobalConfiguration.class)
def triggers = new TriggersConfig()
Secret tokenArg = (Secret) null

SonarInstallation[] before = descriptor.getInstallations()
def kept = (before as List).findAll { it.getName() != NAME }

SonarInstallation[] merged = Array.newInstance(SonarInstallation, kept.size() + 1) as SonarInstallation[]
int idx = 0
for (SonarInstallation s : kept) {
  merged[idx++] = s
}
merged[idx] = new SonarInstallation(
  NAME,
  URL,
  CRED_ID,
  tokenArg,
  "",
  "",
  "",
  "",
  triggers
)

descriptor.setInstallations(merged)
descriptor.save()
println("SonarInstallation idempotent upsert: " + NAME)
GROOVY
)"

jenkins_post "/scriptText" --data-urlencode "script=${GROOVY_SCRIPT}" >/dev/null

sonar_webhook_ensure() {
  local target="${JENKINS_PUBLIC_URL}/sonarqube-webhook/"
  local list_json
  list_json="$(curl -fsS -G -u "${SONAR_ADMIN_USER}:${SONAR_ADMIN_PASSWORD}" \
    --data-urlencode "format=json" \
    "${SONAR_URL}/api/webhooks/list")"
  printf '%s' "${list_json}" | SONAR_WEBHOOK_NAME="${SONAR_WEBHOOK_NAME}" python3 -c '
import json,sys,os
name=os.environ["SONAR_WEBHOOK_NAME"]
data=json.loads(sys.stdin.read())
for w in data.get("webhooks",[]):
  if w.get("name")==name and w.get("key"):
    print(w["key"])
' | while IFS= read -r k; do
    [[ -z "${k}" ]] && continue
    curl -fsS -u "${SONAR_ADMIN_USER}:${SONAR_ADMIN_PASSWORD}" -X POST \
      --data-urlencode "key=${k}" \
      "${SONAR_URL}/api/webhooks/delete" >/dev/null || true
  done
  curl -fsS -u "${SONAR_ADMIN_USER}:${SONAR_ADMIN_PASSWORD}" -X POST \
    --data-urlencode "name=${SONAR_WEBHOOK_NAME}" \
    --data-urlencode "url=${target}" \
    "${SONAR_URL}/api/webhooks/create" >/dev/null
}

sonar_webhook_ensure

echo "[PHASE-DONE] {phase:6, state:ok, services:jenkins-sonar, duration_s:0, errors:[]}"
