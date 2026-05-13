#!/usr/bin/env bash
# generate-configs.sh 회귀 방지용 골든 검증
set -euo pipefail

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
TMP_DIR="$(mktemp -d)"
OUT_DIR="${TMP_DIR}/out"
CFG="${TMP_DIR}/config.env"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

cat > "${CFG}" <<'EOF'
PROJECT_NAME="myproject"
OS_TYPE="ubuntu22"
COMPOSE_MODE="single"
INTERNAL_NETWORK="10.0.1.0/24"
DOMAIN=""
TIMEZONE="Asia/Seoul"
SSL_TYPE="none"
SSH_VIA_BASTION="y"
TEAM_SIZE="5"
BASTION_IP="10.0.1.10"
GITLAB_IP="10.0.1.11"
NEXUS_IP="10.0.1.12"
JENKINS_IP="10.0.1.13"
ADMIN_SHARED_PASSWORD="SharedPass123!"
JENKINS_ADMIN_USER="admin"
GITLAB_ROOT_EMAIL="admin@myproject.local"
GITLAB_TOKEN=""
EOF

OUT_DIR="${OUT_DIR}" bash "${ROOT_DIR}/scripts/generate-configs.sh" "${CFG}"

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "${needle}" "${file}"; then
    echo "[FAIL] expected '${needle}' in ${file}" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "${needle}" "${file}"; then
    echo "[FAIL] unexpected '${needle}' in ${file}" >&2
    exit 1
  fi
}

cfg_val() {
  local key="$1"
  grep "^${key}=" "${OUT_DIR}/config.env" | head -1 | cut -d= -f2- | tr -d '"' | tr -d '\r'
}

assert_port_key() {
  local key="$1"
  local val
  val="$(cfg_val "${key}")"
  if [[ ! "${val}" =~ ^[0-9]+$ ]]; then
    echo "[FAIL] ${key} missing or not numeric: '${val}'" >&2
    exit 1
  fi
}

assert_port_key HOST_PORT_BASTION_SSH
assert_port_key HOST_PORT_GITLAB
assert_port_key HOST_PORT_GITLAB_SSH
assert_port_key HOST_PORT_JENKINS
assert_port_key HOST_PORT_NEXUS_UI
assert_port_key HOST_PORT_NEXUS_REGISTRY

# 포트 범위 sanity check (현재 생성기는 실제 점유 시에만 회피하므로 기본 8081/5000도 허용)
nui="$(cfg_val HOST_PORT_NEXUS_UI)"
nreg="$(cfg_val HOST_PORT_NEXUS_REGISTRY)"
[[ "${nui}" -ge 1024 && "${nui}" -le 65535 ]]  || { echo "[FAIL] HOST_PORT_NEXUS_UI out of range: ${nui}" >&2; exit 1; }
[[ "${nreg}" -ge 1024 && "${nreg}" -le 65535 ]] || { echo "[FAIL] HOST_PORT_NEXUS_REGISTRY out of range: ${nreg}" >&2; exit 1; }

NEXUS_UI="$(cfg_val HOST_PORT_NEXUS_UI)"
NEXUS_REG="$(cfg_val HOST_PORT_NEXUS_REGISTRY)"
assert_contains "${OUT_DIR}/docker-compose/docker-compose.nexus.yml" "\"${NEXUS_UI}:8081\""
assert_contains "${OUT_DIR}/docker-compose/docker-compose.nexus.yml" "\"${NEXUS_REG}:5000\""
assert_contains "${OUT_DIR}/config.env" 'GITLAB_ROOT_PASSWORD="SharedPass123!"'
assert_contains "${OUT_DIR}/config.env" 'JENKINS_ADMIN_PASSWORD="SharedPass123!"'
assert_contains "${OUT_DIR}/config.env" 'NEXUS_ADMIN_PASSWORD="SharedPass123!"'
assert_contains "${OUT_DIR}/docker-compose/docker-compose.gitlab.yml" 'image: gitlab/gitlab-ce:17.11.7-ce.0'
assert_contains "${OUT_DIR}/docker-compose/docker-compose.nexus.yml" 'image: sonatype/nexus3:3.78.2'
JENKINS_HP="$(cfg_val HOST_PORT_JENKINS)"
assert_contains "${OUT_DIR}/docker-compose/docker-compose.jenkins.yml" "\"${JENKINS_HP}:8080\""
assert_contains "${OUT_DIR}/docker-compose/docker-compose.jenkins.yml" '10-enforce-admin-user.groovy'
assert_contains "${OUT_DIR}/scripts/install-all-impl.sh" 'wait-for-http.sh "GitLab"'
assert_contains "${OUT_DIR}/scripts/install-all-impl.sh" 'wait-for-http.sh "Nexus"'
assert_contains "${OUT_DIR}/scripts/install-all-impl.sh" 'wait-for-http.sh "Jenkins"'
assert_contains "${OUT_DIR}/scripts/install-all-impl.sh" 'bash scripts/post-install.sh'
assert_contains "${OUT_DIR}/scripts/post-install.sh" 'Nexus admin 비밀번호'
assert_contains "${OUT_DIR}/scripts/post-install.sh" 'Jenkins admin 계정 인증 확인 완료'
assert_contains "${OUT_DIR}/scripts/health-check.sh" 'docker logs "gitlab-${PROJECT_NAME}" --tail 50'
assert_contains "${OUT_DIR}/scripts/backup.sh" 'devenv-${PROJECT_NAME}_gitlab_data'
assert_contains "${OUT_DIR}/scripts/restore.sh" '사용법: bash scripts/restore.sh backups/<timestamp>'
assert_not_contains "${OUT_DIR}/scripts/install-bastion.sh" '--remove-orphans'
assert_not_contains "${OUT_DIR}/scripts/install-gitlab.sh" '--remove-orphans'
assert_not_contains "${OUT_DIR}/scripts/install-nexus.sh" '--remove-orphans'
assert_not_contains "${OUT_DIR}/scripts/install-jenkins.sh" '--remove-orphans'

# 명시적 SSL_TYPE="none"이 그대로 보존되는지 (백워드 호환)
assert_contains "${OUT_DIR}/config.env" 'SSL_TYPE="none"'

# PR-2: standard 프로파일 default mem_limit이 compose에 envsubst 되어 있는지
assert_contains "${OUT_DIR}/docker-compose/docker-compose.gitlab.yml"  'mem_limit: 4g'
assert_contains "${OUT_DIR}/docker-compose/docker-compose.nexus.yml"   'mem_limit: 2g'
assert_contains "${OUT_DIR}/docker-compose/docker-compose.jenkins.yml" 'mem_limit: 1g'
assert_contains "${OUT_DIR}/docker-compose/docker-compose.bastion.yml" 'mem_limit: 256m'

# PR-2: teardown.sh 옵션
assert_contains "${OUT_DIR}/scripts/teardown.sh" '--dry-run'
assert_contains "${OUT_DIR}/scripts/teardown.sh" '--keep-volumes'
assert_contains "${OUT_DIR}/scripts/teardown.sh" '--purge-secrets'
assert_contains "${OUT_DIR}/scripts/teardown.sh" 'backup.sh'

# PR-3: 신규 운영 스크립트 5종 존재 + 핵심 키워드
assert_contains "${OUT_DIR}/scripts/ssl-init.sh" 'openssl req -x509'
assert_contains "${OUT_DIR}/scripts/ssl-init.sh" 'certbot/certbot'
assert_contains "${OUT_DIR}/scripts/install-all-impl.sh" 'bash scripts/ssl-init.sh'
assert_contains "${OUT_DIR}/scripts/enable-cron-backup.sh" 'devenv-${PROJECT_NAME}-backup'
assert_contains "${OUT_DIR}/scripts/enable-wsl-autostart.sh" 'sg docker'
assert_contains "${OUT_DIR}/scripts/install-windows-task.ps1" 'Register-ScheduledTask'
assert_contains "${OUT_DIR}/scripts/devenv-doctor.sh" '00-preflight.sh'
assert_contains "${OUT_DIR}/scripts/devenv-doctor.sh" 'health-check.sh'
assert_contains "${OUT_DIR}/scripts/devenv-doctor.sh" 'smoke-cross-service.sh'

# PR-3: SSL_CONTACT_EMAIL이 config.env에 기록되는지 (letsencrypt 분기 준비)
assert_contains "${OUT_DIR}/config.env" 'SSL_CONTACT_EMAIL='

# ----- Fixture 2: SSL_TYPE 빈 값 → self-signed 자동 승격 검증 -----
OUT2_DIR="${TMP_DIR}/out2"
CFG2="${TMP_DIR}/config-empty-ssl.env"
cat > "${CFG2}" <<'EOF'
PROJECT_NAME="myproject"
OS_TYPE="ubuntu22"
COMPOSE_MODE="single"
INTERNAL_NETWORK="10.0.1.0/24"
DOMAIN=""
TIMEZONE="Asia/Seoul"
SSL_TYPE=""
SSH_VIA_BASTION="y"
TEAM_SIZE="5"
BASTION_IP="10.0.1.10"
GITLAB_IP="10.0.1.11"
NEXUS_IP="10.0.1.12"
JENKINS_IP="10.0.1.13"
ADMIN_SHARED_PASSWORD="SharedPass123!"
JENKINS_ADMIN_USER="admin"
GITLAB_ROOT_EMAIL="admin@myproject.local"
GITLAB_TOKEN=""
EOF
OUT_DIR="${OUT2_DIR}" bash "${ROOT_DIR}/scripts/generate-configs.sh" "${CFG2}"
assert_contains "${OUT2_DIR}/config.env" 'SSL_TYPE="self-signed"'

# ----- Fixture 3: MEM_BUDGET_PROFILE="lean" → 절반 사이즈 mem_limit 검증 -----
OUT3_DIR="${TMP_DIR}/out3"
CFG3="${TMP_DIR}/config-lean.env"
cat > "${CFG3}" <<'EOF'
PROJECT_NAME="myproject"
OS_TYPE="ubuntu22"
COMPOSE_MODE="single"
INTERNAL_NETWORK="10.0.1.0/24"
DOMAIN=""
TIMEZONE="Asia/Seoul"
SSL_TYPE="none"
SSH_VIA_BASTION="y"
TEAM_SIZE="5"
BASTION_IP="10.0.1.10"
GITLAB_IP="10.0.1.11"
NEXUS_IP="10.0.1.12"
JENKINS_IP="10.0.1.13"
ADMIN_SHARED_PASSWORD="SharedPass123!"
JENKINS_ADMIN_USER="admin"
GITLAB_ROOT_EMAIL="admin@myproject.local"
GITLAB_TOKEN=""
MEM_BUDGET_PROFILE="lean"
EOF
OUT_DIR="${OUT3_DIR}" bash "${ROOT_DIR}/scripts/generate-configs.sh" "${CFG3}"
assert_contains "${OUT3_DIR}/docker-compose/docker-compose.gitlab.yml"  'mem_limit: 2g'
assert_contains "${OUT3_DIR}/docker-compose/docker-compose.nexus.yml"   'mem_limit: 1g'
assert_contains "${OUT3_DIR}/docker-compose/docker-compose.jenkins.yml" 'mem_limit: 768m'
assert_contains "${OUT3_DIR}/docker-compose/docker-compose.bastion.yml" 'mem_limit: 128m'

echo "[OK] verify-generator passed"
