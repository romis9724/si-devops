#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_LIB="${ROOT_DIR}/scripts/lib/common.sh"

SECURITY_IP="${SECURITY_IP:-localhost}"
JENKINS_IP="${JENKINS_IP:-localhost}"
SONAR_PORT="${SONAR_PORT:-9000}"
ZAP_PORT="${ZAP_PORT:-8090}"
SECURITY_ZAP="${SECURITY_ZAP:-y}"
STATE_FILE="${ROOT_DIR}/.health-check.last"

RUN_PROFILE=""
ok_count=0
warn_count=0
fail_count=0
QUIET=0
VERBOSE=0
CHANGED_ONLY=0
RETRY_COUNT="${RETRY_COUNT:-3}"
RETRY_DELAYS=(5 10 20)

if [[ ! -f "${COMMON_LIB}" ]]; then
  echo "❌ common library not found: ${COMMON_LIB}" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${COMMON_LIB}"

PROJECT_NAME="${PROJECT_NAME:-devenv}"
PRESET_FILE="$(devenv_preset_file "${PROJECT_NAME}")"
TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:latest}"

declare -A CURRENT_STATUS
declare -A PREVIOUS_STATUS
declare -A CURRENT_DETAIL
declare -A PREVIOUS_DETAIL

usage() {
  cat <<'EOF'
Usage: health-check.sh [options]

Options:
  --quiet         최소 출력 모드
  --verbose       상세 출력 모드
  --changed-only  이전 실행 대비 변경된 결과만 출력
  -h, --help      도움말 출력
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --quiet)
        QUIET=1
        shift
        ;;
      --verbose)
        VERBOSE=1
        shift
        ;;
      --changed-only)
        CHANGED_ONLY=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "❌ 알 수 없는 옵션: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

vlog() {
  if [[ "${VERBOSE}" -eq 1 && "${QUIET}" -eq 0 ]]; then
    echo "ℹ️  $1"
  fi
}

retry_cmd() {
  local description="$1"
  shift
  local attempt=1
  local max_attempts="${RETRY_COUNT}"
  local exit_code=0

  while (( attempt <= max_attempts )); do
    if "$@"; then
      vlog "${description}: attempt ${attempt}/${max_attempts} succeeded"
      return 0
    fi

    exit_code=$?
    if (( attempt == max_attempts )); then
      vlog "${description}: failed after ${max_attempts} attempts"
      return "${exit_code}"
    fi

    local delay="${RETRY_DELAYS[$((attempt - 1))]:-10}"
    vlog "${description}: failed (attempt ${attempt}/${max_attempts}), retry in ${delay}s"
    sleep "${delay}"
    attempt=$((attempt + 1))
  done

  return "${exit_code}"
}

detect_run_profile() {
  RUN_PROFILE="$(devenv_detect_run_profile "${ROOT_DIR}" "${PRESET_FILE}")"
}

mark_ok() {
  ok_count=$((ok_count + 1))
  record_result "$1" "OK" "정상"
}

mark_warn() {
  warn_count=$((warn_count + 1))
  record_result "$1" "WARN" "경고"
}

mark_fail() {
  fail_count=$((fail_count + 1))
  record_result "$1" "FAIL" "장애"
}

load_previous_state() {
  if [[ ! -f "${STATE_FILE}" ]]; then
    return
  fi

  while IFS='|' read -r key st detail; do
    [[ -z "${key}" ]] && continue
    PREVIOUS_STATUS["${key}"]="${st}"
    PREVIOUS_DETAIL["${key}"]="${detail}"
  done < "${STATE_FILE}"
}

save_current_state() {
  : > "${STATE_FILE}"
  local key
  for key in "${!CURRENT_STATUS[@]}"; do
    printf '%s|%s|%s\n' "${key}" "${CURRENT_STATUS[$key]}" "${CURRENT_DETAIL[$key]}" >> "${STATE_FILE}"
  done
}

should_print_result() {
  local key="$1"
  local st="$2"
  local detail="$3"

  if [[ "${QUIET}" -eq 1 ]]; then
    return 1
  fi

  if [[ "${CHANGED_ONLY}" -eq 0 ]]; then
    return 0
  fi

  if [[ -z "${PREVIOUS_STATUS[${key}]:-}" ]]; then
    return 0
  fi

  [[ "${PREVIOUS_STATUS[${key}]}" != "${st}" || "${PREVIOUS_DETAIL[${key}]}" != "${detail}" ]]
}

record_result() {
  local key="$1"
  local st="$2"
  local detail="$3"

  CURRENT_STATUS["${key}"]="${st}"
  CURRENT_DETAIL["${key}"]="${detail}"

  if ! should_print_result "${key}" "${st}" "${detail}"; then
    return
  fi

  case "${st}" in
    OK) echo "✅ ${key}" ;;
    WARN) echo "⚠️  ${key}" ;;
    FAIL) echo "❌ ${key}" ;;
  esac
}

check_url() {
  local label="$1"
  local url="$2"
  if retry_cmd "check ${label}" curl -fsS --max-time 5 "${url}" >/dev/null; then
    mark_ok "${label}"
  else
    mark_fail "${label}"
  fi
}

check_trivy() {
  if docker run --rm "${TRIVY_IMAGE}" --version >/dev/null 2>&1; then
    mark_ok "Trivy (docker run ${TRIVY_IMAGE})"
  else
    mark_fail "Trivy (docker run ${TRIVY_IMAGE})"
  fi
}

check_dependency_check_plugin() {
  local plugin_api="http://${JENKINS_IP}:8080/pluginManager/api/json?depth=1"
  local plugin_key='"dependency-check-jenkins-plugin"'
  if retry_cmd "check dependency-check plugin" curl -fsS --max-time 5 "${plugin_api}" | grep -q "${plugin_key}"; then
    mark_ok "Dependency-Check Jenkins plugin"
  else
    mark_warn "Dependency-Check Jenkins plugin (미확인)"
  fi
}

check_app_merge_files() {
  local missing=0

  if [[ -f "${ROOT_DIR}/sample-apps/backend/sonar-project.properties" ]]; then
    mark_ok "backend sonar-project.properties"
  else
    mark_fail "backend sonar-project.properties"
    missing=1
  fi

  if [[ -f "${ROOT_DIR}/sample-apps/frontend/sonar-project.properties" ]]; then
    mark_ok "frontend sonar-project.properties"
  else
    mark_fail "frontend sonar-project.properties"
    missing=1
  fi

  if [[ ${missing} -eq 0 ]]; then
    mark_ok "post-app 병합 파일 점검"
  else
    mark_warn "post-app 병합 파일 누락 (PHASE 7 재실행 필요)"
  fi
}

section() {
  [[ "${QUIET}" -eq 0 ]] && echo && echo "## $1"
}

check_containers() {
  section "containers"
  local missing=0
  if docker ps --format '{{.Names}}' | grep -q "sonarqube"; then
    mark_ok "sonarqube container"
  else
    mark_fail "sonarqube container"
    missing=1
  fi
  if docker ps --format '{{.Names}}' | grep -q "sonar-db"; then
    mark_ok "sonar-db container"
  else
    mark_fail "sonar-db container"
    missing=1
  fi
  if [[ "${SECURITY_ZAP}" == "y" ]]; then
    if docker ps --format '{{.Names}}' | grep -q "zap"; then
      mark_ok "zap container"
    else
      mark_fail "zap container"
      missing=1
    fi
  else
    mark_ok "zap container check skipped (SECURITY_ZAP=n)"
  fi
  if [[ "${missing}" -eq 0 ]]; then
    mark_ok "containers"
  fi
}

check_sonar() {
  section "sonar"
  check_url "SonarQube API" "http://${SECURITY_IP}:${SONAR_PORT}/api/system/status"
}

check_db() {
  section "db"
  mark_ok "db check covered by container section"
}

check_zap() {
  section "zap"
  if [[ "${SECURITY_ZAP}" == "y" ]]; then
    check_url "OWASP ZAP API" "http://${SECURITY_IP}:${ZAP_PORT}/JSON/core/view/version/"
  else
    mark_ok "OWASP ZAP API check skipped (SECURITY_ZAP=n)"
  fi
}

check_jenkins() {
  section "jenkins"
  check_url "Jenkins login" "http://${JENKINS_IP}:8080/login"
}

check_plugins() {
  section "plugins"
  check_dependency_check_plugin
}

check_tools() {
  section "tools"
  check_trivy
  if command -v dependency-check.sh >/dev/null 2>&1; then
    mark_ok "Dependency-Check cli"
  else
    mark_warn "Dependency-Check cli"
  fi
}

check_host() {
  section "host"
  case "$(uname -s 2>/dev/null || echo Unknown)" in
    Darwin)
      mark_ok "vm.max_map_count (macOS: sysctl 미사용, Sonar JVM opts로 대응)"
      return 0
      ;;
  esac
  if sysctl -n vm.max_map_count 2>/dev/null | grep -Eq "262144|[3-9][0-9]{5,}"; then
    mark_ok "vm.max_map_count"
  else
    mark_warn "vm.max_map_count"
  fi
}

main() {
  parse_args "$@"
  load_previous_state
  detect_run_profile
  vlog "detected run profile: ${RUN_PROFILE}"

  if [[ "${QUIET}" -eq 0 ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " devenv-security health check"
    echo " run profile: ${RUN_PROFILE}"
    if [[ "${CHANGED_ONLY}" -eq 1 ]]; then
      echo " output mode: changed-only"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  fi

  check_containers
  check_sonar
  check_db
  check_zap
  check_trivy
  check_jenkins
  check_plugins
  check_tools
  check_host

  if [[ "${RUN_PROFILE}" == "post-app" ]]; then
    check_app_merge_files
  else
    mark_ok "pre-app 프로필: 앱 병합 점검 생략"
  fi

  save_current_state

  if [[ "${CHANGED_ONLY}" -eq 1 && "${QUIET}" -eq 0 ]]; then
    echo
    echo "(changed-only 모드: 변경된 항목만 출력)"
  fi

  echo
  echo "결과: ${ok_count} 정상 | ${warn_count} 경고 | ${fail_count} 장애"
  if [[ ${fail_count} -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
