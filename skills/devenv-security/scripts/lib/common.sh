#!/usr/bin/env bash

# 단일 preset 경로: ${DEVENV_HOME}/preset.json 또는 ~/devenv-${PROJECT_NAME}/preset.json
devenv_home_dir() {
  local project_name="${1:-devenv}"
  if [[ -n "${DEVENV_HOME:-}" ]]; then
    printf '%s' "${DEVENV_HOME}"
  else
    printf '%s' "${HOME}/devenv-${project_name}"
  fi
}

devenv_preset_file() {
  printf '%s' "$(devenv_home_dir "$1")/preset.json"
}

devenv_secrets_env_file() {
  printf '%s' "$(devenv_home_dir "$1")/secrets/security.env"
}

devenv_has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

devenv_has_app_section() {
  local preset_file="$1"

  if [[ ! -f "${preset_file}" ]]; then
    return 1
  fi

  if devenv_has_cmd python3; then
    python3 - <<'PY' "${preset_file}"
import json
import sys
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    app = data.get("app")
    sys.exit(0 if isinstance(app, dict) and len(app) > 0 else 1)
except Exception:
    sys.exit(1)
PY
    return $?
  fi

  grep -q '"app"[[:space:]]*:' "${preset_file}"
}

devenv_detect_run_profile() {
  local root_dir="$1"
  local preset_file="$2"

  if devenv_has_app_section "${preset_file}" || [[ -d "${root_dir}/sample-apps/backend" || -d "${root_dir}/sample-apps/frontend" ]]; then
    echo "post-app"
  else
    echo "pre-app"
  fi
}

devenv_retry_cmd() {
  local description="$1"
  local retry_count="$2"
  local delays_csv="$3"
  shift 3

  local attempt=1
  local exit_code=0
  local delays=()
  IFS=',' read -r -a delays <<< "${delays_csv}"

  while (( attempt <= retry_count )); do
    if "$@"; then
      return 0
    fi

    exit_code=$?
    if (( attempt == retry_count )); then
      return "${exit_code}"
    fi

    local delay="${delays[$((attempt - 1))]:-10}"
    sleep "${delay}"
    attempt=$((attempt + 1))
  done

  return "${exit_code}"
}
