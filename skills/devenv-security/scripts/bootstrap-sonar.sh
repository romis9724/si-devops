#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_LIB="${ROOT_DIR}/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "${COMMON_LIB}"

PROJECT_NAME="${PROJECT_NAME:-devenv}"
SECRETS_ENV="$(devenv_secrets_env_file "${PROJECT_NAME}")"
if [[ -f "${SECRETS_ENV}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${SECRETS_ENV}"
  set +a
fi

SONAR_URL="${SONAR_URL:-http://localhost:9000}"
SONAR_ADMIN_PASSWORD="${SONAR_ADMIN_PASSWORD:-changeme}"
SONAR_NEW_ADMIN_PASSWORD="${SONAR_NEW_ADMIN_PASSWORD:-changeme!1}"
TOKEN_NAME="${SONAR_GLOBAL_TOKEN_NAME:-GLOBAL_ANALYSIS_TOKEN}"
DEVENV_HOME_DIR="$(devenv_home_dir "${PROJECT_NAME}")"
SONAR_TOKEN_FILE="${SONAR_TOKEN_FILE:-${DEVENV_HOME_DIR}/secrets/.sonar-global-analysis-token}"

curl -fsS -u "admin:${SONAR_ADMIN_PASSWORD}" -X POST \
  --data-urlencode "login=admin" \
  --data-urlencode "previousPassword=${SONAR_ADMIN_PASSWORD}" \
  --data-urlencode "password=${SONAR_NEW_ADMIN_PASSWORD}" \
  "${SONAR_URL}/api/users/change_password" >/dev/null 2>&1 || true

# 멱등: 동일 이름 토큰 revoke 후 재발급 (조회→삭제→생성)
curl -fsS -u "admin:${SONAR_NEW_ADMIN_PASSWORD}" -X POST \
  --data-urlencode "name=${TOKEN_NAME}" \
  "${SONAR_URL}/api/user_tokens/revoke" >/dev/null 2>&1 || true

token_response="$(curl -fsS -u "admin:${SONAR_NEW_ADMIN_PASSWORD}" -X POST \
  --data-urlencode "name=${TOKEN_NAME}" \
  "${SONAR_URL}/api/user_tokens/generate")"

token_value="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("token",""))' "${token_response}")"
if [[ -z "${token_value}" ]]; then
  echo "[SEC-E801] sonar token missing | cause=token api failed | action=check sonar auth | next=abort"
  exit 1
fi

mkdir -p "$(dirname "${SONAR_TOKEN_FILE}")"
umask 077
printf '%s\n' "${token_value}" > "${SONAR_TOKEN_FILE}"
chmod 600 "${SONAR_TOKEN_FILE}"
echo "SONAR_GLOBAL_ANALYSIS_TOKEN_REF=secrets/.sonar-global-analysis-token"
echo "SONAR_GLOBAL_ANALYSIS_TOKEN_FILE=${SONAR_TOKEN_FILE}"
