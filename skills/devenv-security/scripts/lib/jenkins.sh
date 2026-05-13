#!/usr/bin/env bash
set -euo pipefail

JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_TOKEN="${JENKINS_TOKEN:-}"

jenkins_auth_array() {
  if [[ -n "${JENKINS_TOKEN}" ]]; then
    printf '%s\n' "-u" "${JENKINS_USER}:${JENKINS_TOKEN}"
  fi
}

jenkins_get_crumb() {
  local crumb
  local auth_args=()
  while IFS= read -r arg; do
    auth_args+=("${arg}")
  done < <(jenkins_auth_array)
  # xpath에 `[` `]` 포함 — URL에 직접 넣지 말고 curl -G --data-urlencode 사용 (zsh 안전)
  crumb="$(
    curl -fsS "${auth_args[@]}" -G "${JENKINS_URL}/crumbIssuer/api/xml" \
      --data-urlencode 'xpath=concat(//crumbRequestField,":",//crumb)'
  )"
  if [[ -z "${crumb}" ]]; then
    echo "[SEC-E601] jenkins crumb missing | cause=csrf crumbIssuer empty or denied | action=check auth/crumbIssuer | next=abort" >&2
    return 1
  fi
  printf '%s' "${crumb}"
}

jenkins_get() {
  local path="$1"
  local auth_args=()
  while IFS= read -r arg; do
    auth_args+=("${arg}")
  done < <(jenkins_auth_array)
  curl -fsS "${auth_args[@]}" "${JENKINS_URL}${path}"
}

jenkins_post() {
  local path="$1"
  shift || true
  local crumb
  local auth_args=()
  while IFS= read -r arg; do
    auth_args+=("${arg}")
  done < <(jenkins_auth_array)
  crumb="$(jenkins_get_crumb)" || return 1
  curl -fsS -X POST "${auth_args[@]}" -H "${crumb}" "$@" "${JENKINS_URL}${path}"
}
