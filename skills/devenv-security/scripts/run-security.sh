#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="${ROOT_DIR}/scripts"

QUIET=0
VERBOSE=0
CHANGED_ONLY=0
PASSTHROUGH=()

usage() {
  cat <<'EOF'
Usage: run-security.sh [options]

Pipeline:
  1) 00-preflight.sh
  2) install-security.sh
  3) health-check.sh

Options:
  --quiet         최소 출력 모드
  --verbose       상세 출력 모드
  --plan          설치 변경 예정 사항만 출력
  --changed-only  health-check에서 변경 항목만 출력
  -h, --help      도움말 출력
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --quiet)
        QUIET=1
        PASSTHROUGH+=("--quiet")
        shift
        ;;
      --verbose)
        VERBOSE=1
        PASSTHROUGH+=("--verbose")
        shift
        ;;
      --changed-only)
        CHANGED_ONLY=1
        shift
        ;;
      --plan)
        PASSTHROUGH+=("--plan")
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

run_step() {
  local name="$1"
  shift
  if [[ "${QUIET}" -eq 0 ]]; then
    echo
    echo "==> ${name}"
  fi
  "$@"
}

main() {
  parse_args "$@"

  local preflight_args=()
  local install_args=()
  local health_args=()
  local arg
  for arg in "${PASSTHROUGH[@]}"; do
    install_args+=("${arg}")
    if [[ "${arg}" == "--plan" ]]; then
      continue
    fi
    preflight_args+=("${arg}")
    health_args+=("${arg}")
  done

  run_step "preflight" "${SCRIPTS_DIR}/00-preflight.sh" "${preflight_args[@]}"
  run_step "install-security" "${SCRIPTS_DIR}/install-security.sh" "${install_args[@]}"

  if [[ "${CHANGED_ONLY}" -eq 1 ]]; then
    health_args+=("--changed-only")
  fi
  run_step "health-check" "${SCRIPTS_DIR}/health-check.sh" "${health_args[@]}"

  if [[ "${QUIET}" -eq 0 ]]; then
    echo
    echo "devenv-security run pipeline completed"
  fi
}

main "$@"
