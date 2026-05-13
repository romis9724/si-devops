#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_FILE="${ROOT_DIR}/templates/compose/security.yml.tpl"
OUTPUT_COMPOSE_FILE="${ROOT_DIR}/docker-compose.security.yml"
COMMON_LIB="${ROOT_DIR}/scripts/lib/common.sh"
SYSCTL_FILE="/etc/sysctl.d/99-sonarqube.conf"

PROJECT_NAME="${PROJECT_NAME:-devenv}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-devenv-${PROJECT_NAME}}"
TIMEZONE="${TIMEZONE:-Asia/Seoul}"
SONAR_ADMIN_PASSWORD="${SONAR_ADMIN_PASSWORD:-changeme}"
SONAR_PORT="${SONAR_PORT:-9000}"
ZAP_PORT="${ZAP_PORT:-8090}"
SECURITY_ZAP="${SECURITY_ZAP:-y}"
SECURITY_IP="${SECURITY_IP:-localhost}"
OUTPUT_MODE="${OUTPUT_MODE:-compact}"
OBSERVE_PROMTAIL_FILE="${OBSERVE_PROMTAIL_FILE:-${ROOT_DIR}/../devenv-observe/configs/promtail/promtail-config.yml}"
ZAP_IMAGE_FIXED="zaproxy/zap-stable:2.17.0"

RUN_PROFILE=""
QUIET=0
VERBOSE=0
PLAN_ONLY=0
RETRY_COUNT="${RETRY_COUNT:-3}"
RETRY_DELAYS=(5 10 20)

if [[ ! -f "${COMMON_LIB}" ]]; then
  echo "[devenv-security] ERROR: common library not found: ${COMMON_LIB}" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${COMMON_LIB}"

PRESET_FILE="$(devenv_preset_file "${PROJECT_NAME}")"
LOCK_FILE="$(devenv_home_dir "${PROJECT_NAME}")/.devenv.lock"

usage() {
  cat <<'EOF'
Usage: install-security.sh [options]

Options:
  --quiet      최소 출력 모드
  --verbose    상세 출력 모드
  --plan       변경 예정 사항만 출력 (dry-run)
  -h, --help   도움말 출력
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
      --plan)
        PLAN_ONLY=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "[devenv-security] ERROR: 알 수 없는 옵션: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

log() {
  if [[ "${QUIET}" -eq 1 ]]; then
    return
  fi
  echo "[devenv-security] $*"
}

vlog() {
  if [[ "${VERBOSE}" -eq 1 && "${QUIET}" -eq 0 ]]; then
    echo "[devenv-security][verbose] $*"
  fi
}

phase_done() {
  local phase="$1"
  local phs="$2"
  local services="$3"
  local started_at="$4"
  local errors="${5:-[]}"
  local now
  now="$(date +%s)"
  local duration=$((now - started_at))
  echo "[PHASE-DONE] {phase:${phase}, state:${phs}, services:${services}, duration_s:${duration}, errors:${errors}}"
}

save_checkpoint() {
  local current_phase="$1"
  local last_run
  last_run="$(date -Iseconds)"
  mkdir -p "$(dirname "${PRESET_FILE}")"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys,os
path=sys.argv[1];phase=int(sys.argv[2]);stamp=sys.argv[3]
obj={}
if os.path.exists(path):
  try:
    with open(path,"r",encoding="utf-8") as f: obj=json.load(f)
  except Exception:
    obj={}
security=obj.setdefault("security",{})
completed=security.setdefault("completed_steps",[])
if phase not in completed:
  completed.append(phase)
security["current_phase"]=phase
security["last_run_at"]=stamp
with open(path,"w",encoding="utf-8") as f:
  json.dump(obj,f,ensure_ascii=False,indent=2)
' "${PRESET_FILE}" "${current_phase}" "${last_run}" >/dev/null 2>&1 || true
  fi
}

acquire_lock() {
  if [[ -e "${LOCK_FILE}" ]]; then
    echo "[SEC-E701] lock exists | cause=concurrent install | action=remove stale lock or wait | next=abort"
    exit 1
  fi
  echo "$$" > "${LOCK_FILE}"
  trap 'rm -f "${LOCK_FILE}"' EXIT
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
      log "ERROR: ${description} failed after ${max_attempts} attempts"
      return "${exit_code}"
    fi

    local delay="${RETRY_DELAYS[$((attempt - 1))]:-10}"
    log "WARN: ${description} failed (attempt ${attempt}/${max_attempts}), retry in ${delay}s"
    sleep "${delay}"
    attempt=$((attempt + 1))
  done

  return "${exit_code}"
}

wait_with_budget() {
  local label="$1"
  local tries="$2"
  local interval="$3"
  shift 3
  local i
  for ((i=1;i<=tries;i++)); do
    if "$@"; then
      return 0
    fi
    sleep "${interval}"
  done
  echo "[SEC-E401] ${label} timeout | cause=service warm-up exceeded budget | action=inspect container logs | next=abort"
  return 1
}

validate_zap_image_fixed() {
  if [[ "${PLAN_ONLY}" -eq 1 ]]; then
    return 0
  fi
  if ! docker manifest inspect "${ZAP_IMAGE_FIXED}" >/dev/null 2>&1; then
    echo "[SEC-E201] zap image unavailable | cause=${ZAP_IMAGE_FIXED} not pullable | action=check docker hub/network | next=abort"
    exit 1
  fi
  log "ZAP 이미지 고정 검증: ${ZAP_IMAGE_FIXED}"
}

detect_run_profile() {
  RUN_PROFILE="$(devenv_detect_run_profile "${ROOT_DIR}" "${PRESET_FILE}")"
  vlog "profile detection: ${RUN_PROFILE}"
}

render_compose_file() {
  if [[ ! -f "${TEMPLATE_FILE}" ]]; then
    log "ERROR: 템플릿 파일이 없습니다: ${TEMPLATE_FILE}"
    exit 1
  fi

  if command -v envsubst >/dev/null 2>&1; then
    export PROJECT_NAME TIMEZONE SONAR_ADMIN_PASSWORD SONAR_PORT ZAP_PORT
    envsubst < "${TEMPLATE_FILE}" > "${OUTPUT_COMPOSE_FILE}"
  else
    cp "${TEMPLATE_FILE}" "${OUTPUT_COMPOSE_FILE}"
    log "WARN: envsubst가 없어 템플릿 치환 없이 복사했습니다."
  fi

  log "compose 파일 생성 완료: ${OUTPUT_COMPOSE_FILE}"
}

ensure_vm_max_map_count() {
  case "$(uname -s 2>/dev/null || echo Unknown)" in
    Darwin)
      log "macOS: vm.max_map_count sysctl 시도 안 함 (compose SONAR_SEARCH_JAVAADDITIONALOPTS로 mmap 비활성화)"
      return 0
      ;;
  esac

  if ! command -v sysctl >/dev/null 2>&1; then
    log "WARN: sysctl 명령이 없어 vm.max_map_count 점검을 건너뜁니다."
    return
  fi

  local current
  current="$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)"
  if [[ "${current}" =~ ^[0-9]+$ ]] && (( current < 262144 )); then
    log "WARN: vm.max_map_count=${current} (권장: 262144 이상)"
    if [[ "${PLAN_ONLY}" -eq 0 && "${EUID}" -eq 0 ]]; then
      echo "vm.max_map_count=262144" > "${SYSCTL_FILE}"
      sysctl -p "${SYSCTL_FILE}" >/dev/null
      log "vm.max_map_count 영속화 적용 완료"
    else
      log "INFO: 자동 영속화 생략 (plan 모드 또는 root 권한 없음)"
    fi
  else
    log "vm.max_map_count 점검 통과 (${current})"
  fi
}

render_plan() {
  local plan_services="sonar-db sonarqube"
  if [[ "${SECURITY_ZAP}" == "y" ]]; then
    plan_services="${plan_services} zap"
  fi
  echo "[PLAN] compose=${OUTPUT_COMPOSE_FILE}"
  echo "[PLAN] zap_image=${ZAP_IMAGE_FIXED}"
  echo "[PLAN] services=${plan_services}"
  echo "[PLAN] sysctl=${SYSCTL_FILE} (Linux + root only; macOS skip)"
}

wait_phase5_readiness() {
  wait_with_budget "sonar UP" 30 6 curl -fsS "http://${SECURITY_IP}:${SONAR_PORT}/api/system/status" >/dev/null
  if [[ "${SECURITY_ZAP}" == "y" ]]; then
    wait_with_budget "zap API" 12 5 curl -fsS "http://${SECURITY_IP}:${ZAP_PORT}/JSON/core/view/version/" >/dev/null
  fi
}

configure_observe_promtail_label() {
  if [[ -f "${OBSERVE_PROMTAIL_FILE}" ]]; then
    if grep -q "job_name: devenv-security" "${OBSERVE_PROMTAIL_FILE}"; then
      log "devenv-observe 감지: promtail 보안 라벨 이미 구성됨"
      return
    fi
    if [[ "${PLAN_ONLY}" -eq 1 ]]; then
      log "PLAN: promtail 보안 라벨 추가 예정 (${OBSERVE_PROMTAIL_FILE})"
      return
    fi
    cat <<'EOF' >> "${OBSERVE_PROMTAIL_FILE}"

  - job_name: devenv-security
    static_configs:
      - targets:
          - localhost
        labels:
          job: devenv-security
          stack: security
          __path__: /var/log/devenv-security/*.log
EOF
    log "devenv-observe 감지: promtail 보안 라벨 자동 추가 완료"
  fi
}

start_services() {
  if ! command -v docker >/dev/null 2>&1; then
    log "ERROR: docker 명령이 없습니다."
    exit 1
  fi

  if ! docker compose version >/dev/null 2>&1; then
    log "ERROR: docker compose(v2) 사용이 필요합니다."
    exit 1
  fi

  local services=("sonar-db" "sonarqube")
  if [[ "${SECURITY_ZAP}" == "y" ]]; then
    services+=("zap")
  fi

  if [[ "${PLAN_ONLY}" -eq 1 ]]; then
    render_plan
    return 0
  fi

  log "서비스 기동: ${services[*]}"
  retry_cmd "docker compose up" docker compose -p "${COMPOSE_PROJECT_NAME}" -f "${OUTPUT_COMPOSE_FILE}" up -d "${services[@]}"
  wait_phase5_readiness
}

print_profile_summary() {
  if [[ "${QUIET}" -eq 1 ]]; then
    return
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo " 실행 프로필 확정"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if [[ "${RUN_PROFILE}" == "pre-app" ]]; then
    echo " devenv-app 감지: 아니오"
    echo " 적용 프로필 : pre-app (기본 점검 플로우)"
    echo " 후속 처리   : PHASE 7 자동 건너뜀"
  else
    echo " devenv-app 감지: 예"
    echo " 적용 프로필 : post-app (기존 프로젝트 병합 가능)"
    echo " 후속 처리   : PHASE 7에서 병합 여부 확인"
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

load_secrets_env() {
  local secrets
  secrets="$(devenv_secrets_env_file "${PROJECT_NAME}")"
  if [[ ! -f "${secrets}" ]]; then
    return 0
  fi
  set -a
  # shellcheck source=/dev/null
  source "${secrets}"
  set +a
  vlog "secrets 로드: ${secrets}"
}

main() {
  local started_at
  started_at="$(date +%s)"
  parse_args "$@"
  load_secrets_env
  acquire_lock
  detect_run_profile
  print_profile_summary
  validate_zap_image_fixed
  render_compose_file
  ensure_vm_max_map_count
  start_services
  configure_observe_promtail_label
  save_checkpoint 5
  log "설치 1차 단계 완료"
  phase_done 5 ok "sonarqube,zap" "${started_at}" "[]"
}

main "$@"
