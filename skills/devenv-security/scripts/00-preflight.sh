#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_LIB="${ROOT_DIR}/scripts/lib/common.sh"

warn_count=0
fail_count=0
QUIET=0
VERBOSE=0

if [[ ! -f "${COMMON_LIB}" ]]; then
  echo "❌ common library not found: ${COMMON_LIB}" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${COMMON_LIB}"

PROJECT_NAME="${PROJECT_NAME:-devenv}"
PRESET_FILE="$(devenv_preset_file "${PROJECT_NAME}")"
TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:latest}"

usage() {
  cat <<'EOF'
Usage: 00-preflight.sh [options]

Options:
  --quiet      최소 출력 모드
  --verbose    상세 출력 모드
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

check_ok() {
  [[ "${QUIET}" -eq 1 ]] && return
  echo "✅ $1"
}

check_warn() {
  warn_count=$((warn_count + 1))
  [[ "${QUIET}" -eq 1 ]] && return
  echo "⚠️  $1"
}

check_fail() {
  fail_count=$((fail_count + 1))
  [[ "${QUIET}" -eq 1 ]] && return
  echo "❌ $1"
}

vlog() {
  if [[ "${VERBOSE}" -eq 1 && "${QUIET}" -eq 0 ]]; then
    echo "ℹ️  $1"
  fi
}

has_cmd() {
  devenv_has_cmd "$1"
}

detect_run_profile() {
  devenv_detect_run_profile "${ROOT_DIR}" "${PRESET_FILE}"
}

check_required_tools() {
  [[ "${QUIET}" -eq 0 ]] && echo "📦 [필수 도구 점검]"

  local tools=("docker" "curl")
  local t
  for t in "${tools[@]}"; do
    if has_cmd "${t}"; then
      check_ok "${t} 설치됨"
    else
      check_fail "${t} 미설치"
    fi
  done

  if has_cmd docker && docker compose version >/dev/null 2>&1; then
    check_ok "docker compose(v2) 사용 가능"
  else
    check_fail "docker compose(v2) 사용 불가"
  fi

  if has_cmd envsubst; then
    check_ok "envsubst 사용 가능"
  else
    check_warn "envsubst 없음 (템플릿 치환 없이 복사 동작 가능)"
  fi

  if docker run --rm "${TRIVY_IMAGE}" --version >/dev/null 2>&1; then
    check_ok "Trivy 이미지 실행 가능 (${TRIVY_IMAGE})"
  else
    check_fail "Trivy docker 실행 불가 (${TRIVY_IMAGE})"
  fi
}

check_system_resources() {
  if [[ "${QUIET}" -eq 0 ]]; then
    echo
    echo "🖥️  [리소스 점검]"
  fi

  if has_cmd nproc; then
    local cpu
    cpu="$(nproc)"
    if (( cpu >= 8 )); then
      check_ok "CPU ${cpu} core (권장 기준 충족)"
    else
      check_warn "CPU ${cpu} core (권장 8 core 이상)"
    fi
  else
    check_warn "CPU 코어 수 확인 불가 (nproc 없음)"
  fi

  if [[ -r /proc/meminfo ]]; then
    local mem_kb mem_gb
    mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
    mem_gb="$((mem_kb / 1024 / 1024))"
    if (( mem_gb >= 24 )); then
      check_ok "메모리 ${mem_gb}GB (single 모드 최소 충족)"
    else
      check_warn "메모리 ${mem_gb}GB (single 모드 최소 24GB 권장)"
    fi
  else
    check_warn "메모리 확인 불가 (/proc/meminfo 접근 불가)"
  fi

  if has_cmd df; then
    local free_kb free_gb
    free_kb="$(df -Pk "${ROOT_DIR}" | awk 'NR==2 {print $4}')"
    free_gb="$((free_kb / 1024 / 1024))"
    if (( free_gb >= 200 )); then
      check_ok "가용 디스크 ${free_gb}GB (권장 기준 충족)"
    else
      check_warn "가용 디스크 ${free_gb}GB (권장 200GB 이상)"
    fi
  else
    check_warn "디스크 확인 불가 (df 없음)"
  fi
}

check_kernel_param() {
  if [[ "${QUIET}" -eq 0 ]]; then
    echo
    echo "⚙️  [커널 파라미터]"
  fi

  case "$(uname -s 2>/dev/null || echo Unknown)" in
    Darwin)
      check_ok "macOS: vm.max_map_count sysctl 점검 생략 (Sonar compose SONAR_SEARCH_JAVAADDITIONALOPTS)"
      return 0
      ;;
  esac

  if has_cmd sysctl; then
    local vm
    vm="$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)"
    if [[ "${vm}" =~ ^[0-9]+$ ]] && (( vm >= 262144 )); then
      check_ok "vm.max_map_count=${vm}"
    else
      check_warn "vm.max_map_count=${vm} (권장: 262144 이상)"
    fi
  else
    check_warn "sysctl 없음 (vm.max_map_count 확인 불가)"
  fi
}

check_secrets_env_optional() {
  local secrets
  secrets="$(devenv_secrets_env_file "${PROJECT_NAME}")"
  if [[ -f "${secrets}" ]]; then
    check_ok "secrets 파일 존재 (${secrets})"
  else
    check_warn "secrets 파일 없음 (${secrets}) — SONAR 등 비밀은 환경변수·기본값 사용. 예: secrets/security.env.example 복사"
  fi
}

check_port_conflicts() {
  if [[ "${QUIET}" -eq 0 ]]; then
    echo
    echo "🌐 [포트 점유 점검]"
  fi

  local ports=(8080 8081 5000 9000 8090)
  local p

  if has_cmd ss; then
    for p in "${ports[@]}"; do
      if ss -tln | grep -q ":${p} "; then
        check_warn "포트 ${p} 사용 중"
      else
        check_ok "포트 ${p} 사용 가능"
      fi
    done
    return
  fi

  if has_cmd netstat; then
    for p in "${ports[@]}"; do
      if netstat -tln 2>/dev/null | grep -q ":${p} "; then
        check_warn "포트 ${p} 사용 중"
      else
        check_ok "포트 ${p} 사용 가능"
      fi
    done
    return
  fi

  check_warn "포트 점유 확인 명령(ss/netstat) 없음"
}

main() {
  parse_args "$@"
  local run_profile
  run_profile="$(detect_run_profile)"
  vlog "detected run profile: ${run_profile}"

  if [[ "${QUIET}" -eq 0 ]]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " devenv-security preflight"
    echo " run profile: ${run_profile}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  fi

  check_required_tools
  check_secrets_env_optional
  check_system_resources
  check_kernel_param
  check_port_conflicts

  echo
  echo "결과: 경고 ${warn_count}건 | 장애 ${fail_count}건"

  if (( fail_count > 0 )); then
    echo "사전 점검 실패: 필수 항목을 먼저 해결하세요."
    exit 1
  fi

  echo "사전 점검 통과"
}

main "$@"
