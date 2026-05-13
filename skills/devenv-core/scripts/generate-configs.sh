#!/usr/bin/env bash
# ============================================================
# generate-configs.sh — devenv-core 산출물 생성기
#
# 책임 범위(devenv-core 4개 서버만):
#   1) Bastion  2) GitLab  3) Nexus  4) Jenkins (+ JCasC)
#   + 선택: Nginx 리버스 프록시 (DOMAIN 설정 시)
#
# DB / Backend / Frontend / Admin / Security / Observe 산출물은
# 각각 devenv-app / devenv-security / devenv-observe 스킬이 처리합니다.
#
# 사용법:
#   1) config.env를 같은 디렉토리에 준비
#   2) bash generate-configs.sh [config.env 경로]
# ============================================================
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SKILL_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"
DRY_RUN=0
CONFIG_FILE="./config.env"
for arg in "$@"; do
  case "${arg}" in
    --dry-run) DRY_RUN=1 ;;
    *) CONFIG_FILE="${arg}" ;;
  esac
done

# 색상
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; N='\033[0m'
log()  { echo -e "${G}[ OK ]${N} $*"; }
warn() { echo -e "${Y}[WARN]${N} $*"; }
err()  { echo -e "${R}[FAIL]${N} $*" >&2; }
info() { echo -e "${B}[INFO]${N} $*"; }

# envsubst 가용성 점검
if ! command -v envsubst >/dev/null 2>&1; then
  err "envsubst 명령이 필요합니다 (gettext-base 패키지)"
  echo "  Ubuntu/Debian: sudo apt install -y gettext-base" >&2
  echo "  RHEL/CentOS:   sudo dnf install -y gettext"     >&2
  echo "  Alpine:        apk add gettext"                 >&2
  exit 1
fi

# ============================================================
# STEP 1. config.env 로드
# ============================================================
if [[ ! -f "${CONFIG_FILE}" ]]; then
  err "config.env not found: ${CONFIG_FILE}"
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "${CONFIG_FILE}"
set +a

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "source ${CONFIG_FILE}"
  echo "render compose templates to \${OUT_DIR:-\${HOME}/devenv-\${PROJECT_NAME}}"
  echo "emit scripts: preflight/bootstrap/install-all/health-check/backup"
  echo "copy references and write README"
  exit 0
fi

# ============================================================
# STEP 2. 변수 검증 (core에 필요한 것만)
# ============================================================
info "config.env 검증 중..."

# SSL_TYPE 빈 값/미정의 백워드 호환 — REQUIRED_VARS 검증 전에 self-signed로 승격
: "${SSL_TYPE:=self-signed}"

REQUIRED_VARS=(
  PROJECT_NAME OS_TYPE COMPOSE_MODE INTERNAL_NETWORK TIMEZONE
  SSH_VIA_BASTION TEAM_SIZE
  BASTION_IP GITLAB_IP NEXUS_IP JENKINS_IP
  JENKINS_ADMIN_USER GITLAB_ROOT_EMAIL
)

# PROJECT_NAME 형식 검증 (Docker 컨테이너/네트워크 명명 규칙)
if [[ ! "${PROJECT_NAME:-}" =~ ^[a-z][a-z0-9-]{1,30}[a-z0-9]$ ]]; then
  err "PROJECT_NAME 형식 오류: '${PROJECT_NAME:-}' (영문 소문자 시작, 영문소문자/숫자/하이픈, 3~32자)"
  exit 1
fi

ERR=0
for var in "${REQUIRED_VARS[@]}"; do
  val="${!var:-__UNSET__}"
  if [[ "${val}" == "__UNSET__" ]]; then
    err "변수 미정의: ${var}"; ERR=1
  elif [[ "${val}" =~ \{.*\} ]]; then
    err "placeholder 잔존: ${var}=${val}"; ERR=1
  fi
done

# 공통 관리자 비밀번호 1회 입력 정책.
# 기존 config.env 하위 호환을 위해 개별 비밀번호가 있으면 우선 사용하고,
# 없으면 ADMIN_SHARED_PASSWORD로 채운다.
if [[ -n "${ADMIN_SHARED_PASSWORD:-}" ]]; then
  : "${GITLAB_ROOT_PASSWORD:=${ADMIN_SHARED_PASSWORD}}"
  : "${JENKINS_ADMIN_PASSWORD:=${ADMIN_SHARED_PASSWORD}}"
  : "${NEXUS_ADMIN_PASSWORD:=${ADMIN_SHARED_PASSWORD}}"
fi

for secret_var in GITLAB_ROOT_PASSWORD JENKINS_ADMIN_PASSWORD NEXUS_ADMIN_PASSWORD; do
  if [[ -z "${!secret_var:-}" ]]; then
    err "비밀번호 변수 누락: ${secret_var} (또는 ADMIN_SHARED_PASSWORD)"; ERR=1
  fi
done

: "${GITLAB_ROOT_EMAIL:=admin@${PROJECT_NAME}.local}"

# 재현 가능한 설치를 위해 서비스 버전 고정
: "${GITLAB_VERSION:=17.11.7-ce.0}"
: "${NEXUS_VERSION:=3.78.2}"
: "${GITLAB_CE_SHA:=}"
: "${NEXUS_SHA:=}"
: "${PORT_OFFSET:=0}"
: "${BASTION_SSH_PUBKEY:=}"

# 메모리 budget 프로파일 (lean | standard | heavy)
# - 호스트 RAM에 따라 4개 서비스의 mem_limit 기본값을 선택
# - 개별 변수(GITLAB_MEM_LIMIT 등)가 명시되면 그 값이 우선
: "${MEM_BUDGET_PROFILE:=standard}"
case "${MEM_BUDGET_PROFILE}" in
  lean)     def_gitlab=2g; def_nexus=1g;   def_jenkins=768m; def_bastion=128m ;;
  standard) def_gitlab=4g; def_nexus=2g;   def_jenkins=1g;   def_bastion=256m ;;
  heavy)    def_gitlab=6g; def_nexus=3g;   def_jenkins=2g;   def_bastion=512m ;;
  *) err "MEM_BUDGET_PROFILE 잘못됨: ${MEM_BUDGET_PROFILE} (lean | standard | heavy)"; exit 1 ;;
esac
: "${GITLAB_MEM_LIMIT:=${def_gitlab}}"
: "${NEXUS_MEM_LIMIT:=${def_nexus}}"
: "${JENKINS_MEM_LIMIT:=${def_jenkins}}"
: "${BASTION_MEM_LIMIT:=${def_bastion}}"

if [[ -z "${BASTION_SSH_PUBKEY}" ]]; then
  if [[ -f "${HOME}/.ssh/id_ed25519.pub" ]]; then
    BASTION_SSH_PUBKEY="$(tr -d '\r\n' < "${HOME}/.ssh/id_ed25519.pub")"
  elif [[ -f "${HOME}/.ssh/id_rsa.pub" ]]; then
    BASTION_SSH_PUBKEY="$(tr -d '\r\n' < "${HOME}/.ssh/id_rsa.pub")"
  fi
fi

if [[ -z "${GITLAB_CE_SHA}" ]] && command -v docker >/dev/null 2>&1; then
  GITLAB_CE_SHA="$(docker buildx imagetools inspect "gitlab/gitlab-ce:${GITLAB_VERSION}" 2>/dev/null | sed -n 's/^Digest:[[:space:]]*//p' | head -n 1 || true)"
fi
if [[ -z "${NEXUS_SHA}" ]] && command -v docker >/dev/null 2>&1; then
  NEXUS_SHA="$(docker buildx imagetools inspect "sonatype/nexus3:${NEXUS_VERSION}" 2>/dev/null | sed -n 's/^Digest:[[:space:]]*//p' | head -n 1 || true)"
fi

# IP 형식 검증
ip_re='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
for ip_var in BASTION_IP GITLAB_IP NEXUS_IP JENKINS_IP; do
  val="${!ip_var:-}"
  if [[ ! "${val}" =~ ${ip_re} ]]; then
    err "IP 형식 오류: ${ip_var}=${val}"; ERR=1
  fi
done

# COMPOSE_MODE 검증
case "${COMPOSE_MODE}" in
  single|multi) ;;
  *) err "COMPOSE_MODE 잘못됨: ${COMPOSE_MODE} (single|multi)"; ERR=1 ;;
esac

[[ ${ERR} -eq 1 ]] && { err "검증 실패. config.env를 수정 후 재실행하세요."; exit 1; }
log "config.env 검증 통과"

# ============================================================
# STEP 3. 단일 서버 모드 — 호스트 포트 충돌 회피 자동 조정
# ============================================================
# 충돌 매트릭스(단일 서버):
#   호스트 sshd:22         vs Bastion SSH      → Bastion 2222
#   Bastion 2222           vs GitLab SSH       → GitLab  2223
#   호스트 80              vs GitLab HTTP      → GitLab  8082
#   Jenkins 8080           — (충돌 없음, 고정)
#   Nexus   8081 / 5000    — (충돌 없음, 고정)
# ============================================================
if [[ "${COMPOSE_MODE}" == "single" ]]; then
  HOST_PORT_GITLAB=$((8082 + PORT_OFFSET))
  HOST_PORT_GITLAB_SSH=$((2223 + PORT_OFFSET))
  HOST_PORT_BASTION_SSH=$((2222 + PORT_OFFSET))
else
  HOST_PORT_GITLAB=$((80 + PORT_OFFSET))
  HOST_PORT_GITLAB_SSH=$((22 + PORT_OFFSET))
  HOST_PORT_BASTION_SSH=$((22 + PORT_OFFSET))
fi
HOST_PORT_JENKINS=$((8080 + PORT_OFFSET))
HOST_PORT_NEXUS_UI=$((8081 + PORT_OFFSET))
HOST_PORT_NEXUS_REGISTRY=$((5000 + PORT_OFFSET))

# Nexus Docker registry — 단일 서버는 127.0.0.1, 다중은 NEXUS_IP
if [[ "${COMPOSE_MODE}" == "single" ]]; then
  NEXUS_REGISTRY="127.0.0.1:${HOST_PORT_NEXUS_REGISTRY}"
else
  NEXUS_REGISTRY="${NEXUS_IP}:${HOST_PORT_NEXUS_REGISTRY}"
fi

# ============================================================
# STEP 4. 출력 디렉토리 준비
# ============================================================
OUT="${OUT_DIR:-${HOME}/devenv-${PROJECT_NAME}}"

# rm -rf 안전 가드
if [[ -z "${OUT}" || "${OUT}" == "/" || "${OUT}" == "${HOME}" || "${OUT}" == "${HOME}/" ]]; then
  err "OUT_DIR이 위험한 경로입니다: '${OUT}'"; exit 1
fi
case "${OUT}" in
  /|/bin*|/etc*|/usr*|/var*|/lib*|/opt*|/root|/root/|/home|/home/)
    err "OUT_DIR이 시스템 경로입니다: '${OUT}'"; exit 1 ;;
esac

# 기존 산출물이 있으면 백업 (실수 방지)
if [[ -d "${OUT}" ]]; then
  BACKUP="${OUT}.bak.previous"
  if [[ -e "${BACKUP}" ]]; then
    rm -rf "${BACKUP}"
  fi
  mv "${OUT}" "${BACKUP}"
  warn "기존 산출물을 백업으로 이동: ${BACKUP}"
fi

mkdir -p "${OUT}"/{docker-compose,scripts,configs/jenkins,references}

info "출력 디렉토리: ${OUT}"

# ============================================================
# STEP 5. config.env 사본 저장 (최종본 — 채워진 값 포함)
# ============================================================
FINAL_CONFIG="${OUT}/config.env"
cat > "${FINAL_CONFIG}" <<EOF
# 자동 생성됨
# 권한: chmod 600 으로 보호. Git에 커밋 금지!

PROJECT_NAME="${PROJECT_NAME}"
OS_TYPE="${OS_TYPE}"
COMPOSE_MODE="${COMPOSE_MODE}"
INTERNAL_NETWORK="${INTERNAL_NETWORK}"
DOMAIN="${DOMAIN:-}"
TIMEZONE="${TIMEZONE}"

SSL_TYPE="${SSL_TYPE}"
SSL_CONTACT_EMAIL="${SSL_CONTACT_EMAIL:-}"
SSH_VIA_BASTION="${SSH_VIA_BASTION}"
TEAM_SIZE="${TEAM_SIZE}"

# 서버 IP
BASTION_IP="${BASTION_IP}"
GITLAB_IP="${GITLAB_IP}"
NEXUS_IP="${NEXUS_IP}"
JENKINS_IP="${JENKINS_IP}"

# 호스트 포트 (단일/다중 모드별 자동 조정 결과)
HOST_PORT_BASTION_SSH="${HOST_PORT_BASTION_SSH}"
HOST_PORT_GITLAB="${HOST_PORT_GITLAB}"
HOST_PORT_GITLAB_SSH="${HOST_PORT_GITLAB_SSH}"
HOST_PORT_JENKINS="${HOST_PORT_JENKINS}"
HOST_PORT_NEXUS_UI="${HOST_PORT_NEXUS_UI}"
HOST_PORT_NEXUS_REGISTRY="${HOST_PORT_NEXUS_REGISTRY}"

# Nexus Docker registry
NEXUS_REGISTRY="${NEXUS_REGISTRY}"

# 자격증명
ADMIN_SHARED_PASSWORD="${ADMIN_SHARED_PASSWORD:-}"
JENKINS_ADMIN_USER="${JENKINS_ADMIN_USER}"
JENKINS_ADMIN_PASSWORD="${JENKINS_ADMIN_PASSWORD}"
GITLAB_ROOT_PASSWORD="${GITLAB_ROOT_PASSWORD}"
GITLAB_ROOT_EMAIL="${GITLAB_ROOT_EMAIL}"
NEXUS_ADMIN_PASSWORD="${NEXUS_ADMIN_PASSWORD}"
BASTION_SSH_PUBKEY="${BASTION_SSH_PUBKEY}"

# 컨테이너 자원 한도 (override 가능)
GITLAB_MEM_LIMIT="${GITLAB_MEM_LIMIT}"
NEXUS_MEM_LIMIT="${NEXUS_MEM_LIMIT}"
JENKINS_MEM_LIMIT="${JENKINS_MEM_LIMIT}"
BASTION_MEM_LIMIT="${BASTION_MEM_LIMIT}"

# 고정 버전
GITLAB_VERSION="${GITLAB_VERSION}"
NEXUS_VERSION="${NEXUS_VERSION}"
GITLAB_CE_SHA="${GITLAB_CE_SHA}"
NEXUS_SHA="${NEXUS_SHA}"
PORT_OFFSET="${PORT_OFFSET}"

# CI/CD 자동 연동 — post-install.sh가 채움
GITLAB_TOKEN="${GITLAB_TOKEN:-}"
EOF
chmod 600 "${FINAL_CONFIG}"
log "config.env 최종본 생성"

cat > "${OUT}/.gitignore" <<'EOF'
config.env
*.log
*.pid
secrets/
.agent-logs/
backups/
EOF

# ============================================================
# STEP 6. envsubst 변수 화이트리스트 (시스템 변수 누설 방지)
# ============================================================
set -a
source "${FINAL_CONFIG}"
set +a

ENVSUBST_VARS='${PROJECT_NAME} ${OS_TYPE} ${COMPOSE_MODE} ${INTERNAL_NETWORK} ${DOMAIN} ${TIMEZONE} ${SSL_TYPE} ${SSL_CONTACT_EMAIL} ${SSH_VIA_BASTION} ${TEAM_SIZE} ${BASTION_IP} ${GITLAB_IP} ${NEXUS_IP} ${JENKINS_IP} ${HOST_PORT_BASTION_SSH} ${HOST_PORT_GITLAB} ${HOST_PORT_GITLAB_SSH} ${HOST_PORT_JENKINS} ${HOST_PORT_NEXUS_UI} ${HOST_PORT_NEXUS_REGISTRY} ${NEXUS_REGISTRY} ${JENKINS_ADMIN_USER} ${JENKINS_ADMIN_PASSWORD} ${GITLAB_ROOT_PASSWORD} ${GITLAB_ROOT_EMAIL} ${NEXUS_ADMIN_PASSWORD} ${GITLAB_TOKEN} ${GITLAB_VERSION} ${NEXUS_VERSION} ${GITLAB_CE_SHA} ${NEXUS_SHA} ${PORT_OFFSET} ${BASTION_SSH_PUBKEY} ${GITLAB_MEM_LIMIT} ${NEXUS_MEM_LIMIT} ${JENKINS_MEM_LIMIT} ${BASTION_MEM_LIMIT}'

render() {
  local src="$1" dst="$2"
  if [[ ! -f "${src}" ]]; then
    err "템플릿 없음: ${src}"; return 1
  fi
  envsubst "${ENVSUBST_VARS}" < "${src}" > "${dst}"
}

# ============================================================
# STEP 7. Docker Compose 생성 (core 4개)
# ============================================================
COMPOSE_TPL="${SKILL_ROOT}/templates/compose"
COMPOSE_OUT="${OUT}/docker-compose"

render "${COMPOSE_TPL}/bastion.yml.tpl" "${COMPOSE_OUT}/docker-compose.bastion.yml"
render "${COMPOSE_TPL}/gitlab.yml.tpl"  "${COMPOSE_OUT}/docker-compose.gitlab.yml"
render "${COMPOSE_TPL}/nexus.yml.tpl"   "${COMPOSE_OUT}/docker-compose.nexus.yml"
render "${COMPOSE_TPL}/jenkins.yml.tpl" "${COMPOSE_OUT}/docker-compose.jenkins.yml"
log "Docker Compose 4종 생성 (bastion/gitlab/nexus/jenkins)"

# ============================================================
# STEP 8. Nginx 리버스 프록시 (DOMAIN 설정 시만)
# ============================================================
if [[ -n "${DOMAIN:-}" ]]; then
  mkdir -p "${OUT}/configs/nginx/ssl"
  render "${COMPOSE_TPL}/nginx.yml.tpl" "${COMPOSE_OUT}/docker-compose.nginx.yml"

  NGINX_CONF_TPL="${SKILL_ROOT}/templates/configs/nginx"
  case "${SSL_TYPE}" in
    none)
      render "${NGINX_CONF_TPL}/nginx-http.conf.tpl" "${OUT}/configs/nginx/nginx.conf" ;;
    letsencrypt|self-signed|public)
      render "${NGINX_CONF_TPL}/nginx-https.conf.tpl" "${OUT}/configs/nginx/nginx.conf" ;;
    *)
      render "${NGINX_CONF_TPL}/nginx-http.conf.tpl" "${OUT}/configs/nginx/nginx.conf"
      warn "SSL_TYPE='${SSL_TYPE}' 미인식 — HTTP only 설정으로 생성됨" ;;
  esac
  log "Nginx 리버스 프록시 설정 생성 (DOMAIN=${DOMAIN}, SSL=${SSL_TYPE})"
fi

# ============================================================
# STEP 9. Jenkins JCasC + plugins.txt + Dockerfile
# ============================================================
JENKINS_TPL="${SKILL_ROOT}/templates/jenkins"

if [[ -f "${JENKINS_TPL}/jenkins.yaml.tpl" ]]; then
  render "${JENKINS_TPL}/jenkins.yaml.tpl" "${OUT}/configs/jenkins/jenkins.yaml"
  log "JCasC (jenkins.yaml) 생성"
fi

if [[ -f "${JENKINS_TPL}/Dockerfile" ]]; then
  cp "${JENKINS_TPL}/Dockerfile" "${OUT}/configs/jenkins/Dockerfile"
fi

if [[ -f "${JENKINS_TPL}/plugins.txt" ]]; then
  cp "${JENKINS_TPL}/plugins.txt" "${OUT}/configs/jenkins/plugins.txt"
fi

if [[ -f "${JENKINS_TPL}/10-enforce-admin-user.groovy" ]]; then
  cp "${JENKINS_TPL}/10-enforce-admin-user.groovy" "${OUT}/configs/jenkins/10-enforce-admin-user.groovy"
fi

# ============================================================
# STEP 9-B. 운영 스크립트 인라인 생성
#  - 외부 템플릿 의존 없이 여기서 직접 생성 (산출물 일관성 보장)
#  - 모든 스크립트는 런타임에 config.env를 source 하여 변수 사용
# ============================================================

# ---- 00-preflight.sh ----
cat > "${OUT}/scripts/00-preflight.sh" <<'PREFLIGHT'
#!/usr/bin/env bash
# 사전 점검: Docker / 리소스 / 포트 / 커널 파라미터
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; N='\033[0m'
ok()   { echo -e "${G}[ OK ]${N} $*"; }
fail() { echo -e "${R}[FAIL]${N} $*"; ERR=1; }
warn() { echo -e "${Y}[WARN]${N} $*"; }
ERR=0

# 1) Docker
docker info >/dev/null 2>&1 && ok "Docker 데몬 실행 중" || fail "Docker 데몬을 실행하세요"
docker compose version >/dev/null 2>&1 && ok "docker compose v2 사용 가능" || fail "docker compose v2 필요"

# 2) 리소스
CPU=$(nproc 2>/dev/null || echo 0)
MEM_GB=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)
DISK_GB=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')
[[ ${CPU} -ge 4 ]]    && ok "CPU ${CPU} core"   || warn "CPU ${CPU} core (권장 8+)"
[[ ${MEM_GB} -ge 16 ]]&& ok "RAM ${MEM_GB}GB"   || warn "RAM ${MEM_GB}GB (권장 24+)"
[[ ${DISK_GB} -ge 50 ]]&& ok "디스크 여유 ${DISK_GB}GB" || fail "디스크 부족 ${DISK_GB}GB (최소 50GB)"

# 3) 포트 충돌
check_port() {
  local port="$1" name="$2"
  if ss -tln 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}\$"; then
    echo "[CORE-E040] port-busy | cause=${name}:${port} | action=change host port or stop process | next=abort"
    fail "포트 ${port} 이미 사용 중 (${name})"
  else
    ok "포트 ${port} 사용 가능 (${name})"
  fi
}
check_port "${HOST_PORT_BASTION_SSH}" "Bastion SSH"
check_port "${HOST_PORT_GITLAB}"      "GitLab HTTP"
check_port "${HOST_PORT_GITLAB_SSH}"  "GitLab SSH"
check_port "${HOST_PORT_JENKINS}"       "Jenkins"
check_port "${HOST_PORT_NEXUS_UI}"      "Nexus"
check_port "${HOST_PORT_NEXUS_REGISTRY}" "Nexus Docker"

if ip route 2>/dev/null | rg -q "$(printf "%s" "${INTERNAL_NETWORK}" | sed 's|/.*$||')"; then
  echo "[CORE-E041] subnet-conflict | cause=route overlap | action=choose other INTERNAL_NETWORK cidr | next=abort"
  fail "INTERNAL_NETWORK 충돌 가능: ${INTERNAL_NETWORK}"
fi

# 4) vm.max_map_count (GitLab/Nexus용)
MAP=$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)
[[ ${MAP} -ge 262144 ]] && ok "vm.max_map_count=${MAP}" \
  || warn "vm.max_map_count=${MAP} (권장 262144 — sudo sysctl -w vm.max_map_count=262144)"

# 5) envsubst
command -v envsubst >/dev/null 2>&1 && ok "envsubst 사용 가능" \
  || fail "envsubst 필요 (sudo apt install -y gettext-base)"

# 6) inode 여유
INODE_FREE_PCT=$(df -Pi / | awk 'NR==2 {gsub("%","",$5); print 100-$5}')
[[ ${INODE_FREE_PCT} -ge 10 ]] && ok "inode 여유 ${INODE_FREE_PCT}%" \
  || warn "inode 여유 부족 ${INODE_FREE_PCT}% (권장 10% 이상)"

# 7) DNS 기본 확인
getent hosts localhost >/dev/null 2>&1 && ok "DNS 기본 해석 가능(localhost)" \
  || fail "DNS 해석 실패(localhost)"

# 8) NTP 동기화 확인 (지원 환경에서만)
if command -v timedatectl >/dev/null 2>&1; then
  NTP_SYNC="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)"
  [[ "${NTP_SYNC}" == "yes" ]] && ok "NTP 동기화 정상" || warn "NTP 동기화 미확인 (${NTP_SYNC})"
fi

# 9) Nexus insecure registry 설정 힌트 (single 모드)
if [[ "${COMPOSE_MODE}" == "single" ]]; then
  if docker info 2>/dev/null | grep -q "${NEXUS_REGISTRY}"; then
    ok "Docker insecure registry 확인 (${NEXUS_REGISTRY})"
  else
    warn "Docker insecure registry 미확인 (${NEXUS_REGISTRY}) - Nexus push/login 실패 가능"
  fi
fi

[[ ${ERR} -eq 1 ]] && { echo; echo "사전 점검 실패 — 위 항목을 해결 후 재시도."; exit 1; }
echo; ok "사전 점검 통과"
PREFLIGHT
chmod +x "${OUT}/scripts/00-preflight.sh"

# ---- 00-root-bootstrap.sh ----
cat > "${OUT}/scripts/00-root-bootstrap.sh" <<'ROOTBOOT'
#!/usr/bin/env bash
# root 권한이 필요한 초기 시스템 설정만 수행
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env

if [[ "${EUID}" -ne 0 ]]; then
  echo "[FAIL] root 권한 필요. sudo bash scripts/00-root-bootstrap.sh 로 실행하세요." >&2
  exit 1
fi

echo "[ * ] vm.max_map_count 적용"
sysctl -w vm.max_map_count=262144 >/dev/null

if [[ -f /etc/sysctl.conf ]] && ! grep -q '^vm.max_map_count=262144' /etc/sysctl.conf; then
  echo 'vm.max_map_count=262144' >> /etc/sysctl.conf
fi

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  echo "[ * ] Docker insecure registry 점검 (${NEXUS_REGISTRY})"
  mkdir -p /etc/docker
  EXTRA_REG="127.0.0.1:5000"
  TARGET_REG="${NEXUS_IP}:${HOST_PORT_NEXUS_REGISTRY}"
  if [[ -n "${DOMAIN:-}" ]]; then
    echo "[INFO] DOMAIN 설정 환경 - insecure registry 자동 설정 생략 (TLS 종단으로 처리)"
    TARGET_REG=""
    EXTRA_REG=""
  fi
  if [[ -f /etc/docker/daemon.json ]]; then
    if [[ -n "${TARGET_REG}" ]] && ! grep -q "${TARGET_REG}" /etc/docker/daemon.json; then
      cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak.$(date +%Y%m%d-%H%M%S)"
      python3 - "$TARGET_REG" "$EXTRA_REG" <<'PY'
import json,sys
path="/etc/docker/daemon.json"
reg1=sys.argv[1]
reg2=sys.argv[2]
try:
    with open(path,"r",encoding="utf-8") as f:
        data=json.load(f)
except Exception:
    data={}
regs=data.get("insecure-registries",[])
for reg in (reg1, reg2):
    if reg and reg not in regs:
        regs.append(reg)
data["insecure-registries"]=regs
with open(path,"w",encoding="utf-8") as f:
    json.dump(data,f,indent=2)
PY
      systemctl restart docker 2>/dev/null || service docker restart 2>/dev/null || true
    fi
  else
    cat > /etc/docker/daemon.json <<EOF
{
  "insecure-registries": ["${TARGET_REG}", "${EXTRA_REG}"]
}
EOF
    if [[ -n "${TARGET_REG}" ]]; then
      systemctl restart docker 2>/dev/null || service docker restart 2>/dev/null || true
    fi
  fi
fi

if [[ -n "${http_proxy:-}" || -n "${https_proxy:-}" || -n "${HTTP_PROXY:-}" || -n "${HTTPS_PROXY:-}" ]]; then
  echo "[ * ] proxy 설정 반영(docker/apt)"
  mkdir -p /etc/systemd/system/docker.service.d
  cat > /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=${http_proxy:-${HTTP_PROXY:-}}"
Environment="HTTPS_PROXY=${https_proxy:-${HTTPS_PROXY:-}}"
Environment="NO_PROXY=${no_proxy:-${NO_PROXY:-}}"
EOF
  mkdir -p /etc/apt/apt.conf.d
  cat > /etc/apt/apt.conf.d/95proxy <<EOF
Acquire::http::Proxy "${http_proxy:-${HTTP_PROXY:-}}";
Acquire::https::Proxy "${https_proxy:-${HTTPS_PROXY:-}}";
EOF
  systemctl daemon-reload 2>/dev/null || true
  systemctl restart docker 2>/dev/null || service docker restart 2>/dev/null || true
fi

echo "[ OK ] root bootstrap 완료"
ROOTBOOT
chmod +x "${OUT}/scripts/00-root-bootstrap.sh"

# ---- 00-windows-bootstrap.ps1 ----
cat > "${OUT}/scripts/00-windows-bootstrap.ps1" <<'WINBOOT'
$ErrorActionPreference = "Stop"
$distros = wsl --list --verbose 2>$null
if (-not $distros) {
  Write-Host "[CORE-E020] WSL 미설치 | cause=wsl --list failed | action=wsl --install -d Ubuntu-22.04 --no-launch | next=retry"
  wsl --install -d Ubuntu-22.04 --no-launch
}
$checkSystemd = wsl -d Ubuntu-22.04 -u root -- bash -lc "grep -q '^\[boot\]' /etc/wsl.conf && grep -q '^systemd=true' /etc/wsl.conf"
if ($LASTEXITCODE -ne 0) {
  Write-Host "[CORE-E021] systemd 비활성 | cause=/etc/wsl.conf missing | action=run templates/wsl/setup-wsl.sh | next=retry"
  exit 1
}
WINBOOT
chmod +x "${OUT}/scripts/00-windows-bootstrap.ps1"

# ---- bootstrap-skill-mirror.sh ----
cat > "${OUT}/scripts/bootstrap-skill-mirror.sh" <<'SKILLMIRROR'
#!/usr/bin/env bash
set -euo pipefail
USER_NAME="${1:-$USER}"
SRC="/mnt/c/Users/${USER_NAME}/AppData/Roaming/Claude/local-agent-mode-sessions/skills-plugin"
DST_BASE="/mnt/c/Users/${USER_NAME}/Documents/project/devenv"
if ! ls "${SRC}" >/dev/null 2>&1; then
  mkdir -p "${DST_BASE}"
  rsync -a "${PWD}/" "${DST_BASE}/core/skill/"
  export SKILL_PATH="${DST_BASE}/core/skill"
else
  export SKILL_PATH="${SRC}"
fi
echo "SKILL_PATH=${SKILL_PATH}"
SKILLMIRROR
chmod +x "${OUT}/scripts/bootstrap-skill-mirror.sh"

# ---- 01-bootstrap.sh ----
cat > "${OUT}/scripts/01-bootstrap.sh" <<'BOOTSTRAP'
#!/usr/bin/env bash
# Docker 네트워크/볼륨 준비 + Jenkins user GID 패치
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env

# 1) 외부 네트워크 생성 (이미 있으면 무시)
docker network inspect devenv-internal >/dev/null 2>&1 \
  || docker network create --driver bridge --subnet "${INTERNAL_NETWORK}" devenv-internal

# 2) Jenkins Dockerfile의 docker GID 패치 (호스트와 일치시켜야 docker.sock 접근 가능)
DOCKER_GID=$(getent group docker | cut -d: -f3)
if [[ -n "${DOCKER_GID}" ]]; then
  sed -i "s/DOCKER_GID_PLACEHOLDER/${DOCKER_GID}/g" docker-compose/docker-compose.jenkins.yml || true
fi

echo "[ OK ] bootstrap 완료"
BOOTSTRAP
chmod +x "${OUT}/scripts/01-bootstrap.sh"

# ---- agent-monitor.sh ----
cat > "${OUT}/scripts/agent-monitor.sh" <<'MONITOR'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
last=""
while true; do
  if [[ -f install.pid ]]; then
    pid="$(cat install.pid 2>/dev/null || true)"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      now="running:${pid}"
    else
      now="stopped"
    fi
  else
    now="idle"
  fi
  if [[ "${now}" != "${last}" ]]; then
    echo "${now}"
    last="${now}"
  fi
  sleep 2
done
MONITOR
chmod +x "${OUT}/scripts/agent-monitor.sh"

# ---- install-bastion.sh / install-gitlab.sh / install-nexus.sh / install-jenkins.sh ----
for svc in bastion gitlab nexus jenkins; do
  cat > "${OUT}/scripts/install-${svc}.sh" <<INSTALL
#!/usr/bin/env bash
set -euo pipefail
cd "\$(dirname "\$0")/.."
source config.env
echo "[ * ] ${svc} 설치 중..."
docker compose -f docker-compose/docker-compose.${svc}.yml --project-name "devenv-${PROJECT_NAME}" up -d
echo "[ OK ] ${svc} 컨테이너 실행"
INSTALL
  chmod +x "${OUT}/scripts/install-${svc}.sh"
done

# ---- wait-for-http.sh ----
cat > "${OUT}/scripts/wait-for-http.sh" <<'WAITHTTP'
#!/usr/bin/env bash
set -euo pipefail

name="${1:?service name required}"
url="${2:?url required}"
timeout_secs="${3:-900}"
interval_secs="${4:-10}"

elapsed=0
echo "[ * ] ${name} 준비 대기: ${url}"
while (( elapsed < timeout_secs )); do
  if curl -fsS --max-time 5 "${url}" >/dev/null 2>&1; then
    echo "[ OK ] ${name} 준비 완료"
    exit 0
  fi
  sleep "${interval_secs}"
  elapsed=$((elapsed + interval_secs))
done

echo "[ FAIL ] ${name} 준비 시간 초과 (${timeout_secs}s): ${url}" >&2
exit 1
WAITHTTP
chmod +x "${OUT}/scripts/wait-for-http.sh"

# ---- install-all.sh (순차 설치 + 준비 완료 확인) ----
cat > "${OUT}/scripts/install-all.sh" <<'INSTALLALL'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env

if [[ "${1:-}" == "--dry-run" ]]; then
  echo "bash scripts/00-preflight.sh"
  echo "bash scripts/01-bootstrap.sh"
  echo "bash scripts/install-bastion.sh"
  echo "bash scripts/install-gitlab.sh && wait gitlab"
  echo "bash scripts/install-nexus.sh && wait nexus"
  echo "bash scripts/install-jenkins.sh && wait jenkins"
  echo "bash scripts/post-install.sh"
  exit 0
fi

if [[ -f install.pid ]] && kill -0 "$(cat install.pid)" 2>/dev/null; then
  echo "[CORE-E010] install already running | action=tail install.log | next=skip"
  exit 1
fi

if [[ -f install.log ]]; then
  mv install.log "install.log.$(date +%s)"
fi

setsid bash -c 'echo $$ > install.pid; exec bash scripts/install-all-impl.sh' >> install.log 2>&1 &
runner_pid=$!
wait "${runner_pid}"
exit $?

INSTALLALL
chmod +x "${OUT}/scripts/install-all.sh"

# ---- install-all-impl.sh ----
cat > "${OUT}/scripts/install-all-impl.sh" <<'INSTALLIMPL'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env
trap 'rm -f install.pid' EXIT

healthy() {
  local name="$1"
  docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${name}" 2>/dev/null | rg -q "^healthy|running$"
}

if command -v powershell.exe >/dev/null 2>&1 && [[ -x scripts/00-windows-bootstrap.ps1 ]]; then
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$(pwd)/scripts/00-windows-bootstrap.ps1")" || true
fi
if [[ -x scripts/bootstrap-skill-mirror.sh ]]; then
  bash scripts/bootstrap-skill-mirror.sh >/dev/null 2>&1 || true
fi

bash scripts/00-preflight.sh
bash scripts/01-bootstrap.sh

# TLS 인증서 준비 (SSL_TYPE != none 시)
if [[ "${SSL_TYPE:-self-signed}" != "none" ]]; then
  if [[ -x scripts/ssl-init.sh ]]; then
    bash scripts/ssl-init.sh || { echo "[FAIL] ssl-init 실패 — TLS 인증서 준비를 점검하세요"; exit 1; }
  fi
fi

if healthy "bastion-${PROJECT_NAME}"; then
  echo "[PHASE 8] bastion=skip(existing-ok)"
else
  echo "[PHASE 8] bastion=recreate"
  bash scripts/install-bastion.sh
fi
if healthy "gitlab-${PROJECT_NAME}"; then
  echo "[PHASE 8] gitlab=skip(existing-ok)"
  gitlab_changed=0
else
  echo "[PHASE 8] gitlab=recreate"
  bash scripts/install-gitlab.sh
  gitlab_changed=1
fi
if [[ "${gitlab_changed}" -eq 1 ]]; then
  bash scripts/wait-for-http.sh "GitLab" "http://127.0.0.1:${HOST_PORT_GITLAB}/users/sign_in" 1800 15
fi
if healthy "nexus-${PROJECT_NAME}"; then
  echo "[PHASE 8] nexus=skip(existing-ok)"
  nexus_changed=0
else
  echo "[PHASE 8] nexus=recreate"
  bash scripts/install-nexus.sh
  nexus_changed=1
fi
if [[ "${nexus_changed}" -eq 1 ]]; then
  bash scripts/wait-for-http.sh "Nexus" "http://127.0.0.1:${HOST_PORT_NEXUS_UI}/service/rest/v1/status" 900 10
fi
if healthy "jenkins-${PROJECT_NAME}"; then
  echo "[PHASE 8] jenkins=skip(existing-ok)"
  jenkins_changed=0
else
  echo "[PHASE 8] jenkins=recreate"
  bash scripts/install-jenkins.sh
  jenkins_changed=1
fi
if [[ "${jenkins_changed}" -eq 1 ]]; then
  bash scripts/wait-for-http.sh "Jenkins" "http://127.0.0.1:${HOST_PORT_JENKINS}/login" 900 10
fi
bash scripts/post-install.sh

echo
echo "[ OK ] 전체 설치 완료. 헬스체크 → bash scripts/health-check.sh"
INSTALLIMPL
chmod +x "${OUT}/scripts/install-all-impl.sh"

# ---- post-install.sh (계정/인증 강제 동기화) ----
cat > "${OUT}/scripts/post-install.sh" <<'POSTINSTALL'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env

echo "[ * ] post-install: Nexus/Jenkins 계정 설정 강제 동기화"

# --- Nexus admin password ---
if curl -fsS -u "admin:${NEXUS_ADMIN_PASSWORD}" "http://127.0.0.1:${HOST_PORT_NEXUS_UI}/service/rest/v1/status" >/dev/null 2>&1; then
  echo "[ OK ] Nexus admin 비밀번호 이미 동기화됨"
else
  NEXUS_INIT_PW="$(docker exec "nexus-${PROJECT_NAME}" sh -lc 'cat /nexus-data/admin.password 2>/dev/null || true' | tr -d '\r')"
  if [[ -z "${NEXUS_INIT_PW}" ]]; then
    echo "[ FAIL ] Nexus 초기 비밀번호를 찾지 못했습니다. 수동 확인 필요" >&2
    exit 1
  fi

  curl -fsS -u "admin:${NEXUS_INIT_PW}" \
    -X PUT "http://127.0.0.1:${HOST_PORT_NEXUS_UI}/service/rest/v1/security/users/admin/change-password" \
    -H "Content-Type: text/plain" \
    -d "${NEXUS_ADMIN_PASSWORD}" >/dev/null
  echo "[ OK ] Nexus admin 비밀번호 동기화 완료"
fi

# --- Jenkins admin password ---
# init.groovy.d 스크립트가 컨테이너 시작 시 강제 동기화합니다.
if curl -fsS -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" "http://127.0.0.1:${HOST_PORT_JENKINS}/me/api/json" >/dev/null 2>&1; then
  echo "[ OK ] Jenkins admin 계정 인증 확인 완료"
else
  echo "[ FAIL ] Jenkins admin 인증 실패. 컨테이너 로그를 확인하세요: docker logs jenkins-${PROJECT_NAME} --tail 120" >&2
  exit 1
fi

echo "[ OK ] post-install 계정 강제 동기화 완료"
POSTINSTALL
chmod +x "${OUT}/scripts/post-install.sh"

# ---- smoke-cross-service.sh ----
cat > "${OUT}/scripts/smoke-cross-service.sh" <<'SMOKE'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env
echo "[WARN] smoke gate 시작 (실패해도 설치 실패로 처리하지 않음)"
if docker exec "jenkins-${PROJECT_NAME}" sh -lc "docker login ${NEXUS_REGISTRY} -u admin -p \"${NEXUS_ADMIN_PASSWORD}\" >/dev/null 2>&1 && docker pull busybox:latest >/dev/null 2>&1 && docker tag busybox:latest ${NEXUS_REGISTRY}/smoke:latest && docker push ${NEXUS_REGISTRY}/smoke:latest >/dev/null 2>&1"; then
  echo "[WARN] smoke: jenkins->nexus push ok"
else
  echo "[WARN] smoke: jenkins->nexus push failed"
fi
if [[ -n "${GITLAB_TOKEN:-}" ]]; then
  pid="$(curl -fsS -X POST -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" -d "name=smoke-$(date +%s)" "http://127.0.0.1:${HOST_PORT_GITLAB}/api/v4/projects" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p' | head -n 1)"
  if [[ -n "${pid}" ]]; then
    curl -fsS -X DELETE -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" "http://127.0.0.1:${HOST_PORT_GITLAB}/api/v4/projects/${pid}" >/dev/null 2>&1 || true
    echo "[WARN] smoke: gitlab create/delete ok"
  else
    echo "[WARN] smoke: gitlab create failed"
  fi
else
  echo "[WARN] smoke: GITLAB_TOKEN empty; gitlab api gate skipped"
fi
echo "[WARN] smoke gate 완료"
SMOKE
chmod +x "${OUT}/scripts/smoke-cross-service.sh"

# ---- agent-status.sh ----
cat > "${OUT}/scripts/agent-status.sh" <<'AGENTSTATUS'
#!/usr/bin/env bash
# 토큰 절약형 JSON 상태 출력 유틸
set -euo pipefail

phase="${1:-unknown}"
status="${2:-ok}"
action="${3:-none}"
risk="${4:-low}"
message="${5:-}"

printf '{"phase":"%s","status":"%s","action":"%s","risk":"%s","message":"%s"}\n' \
  "${phase}" "${status}" "${action}" "${risk}" "${message//\"/\\\"}"
AGENTSTATUS
chmod +x "${OUT}/scripts/agent-status.sh"

# ---- agent-preflight.sh ----
cat > "${OUT}/scripts/agent-preflight.sh" <<'AGENTPREFLIGHT'
#!/usr/bin/env bash
# 에이전트용 사전점검 래퍼 (저토큰 출력)
set -euo pipefail
cd "$(dirname "$0")/.."

if bash scripts/00-preflight.sh >/tmp/devenv-preflight.log 2>&1; then
  bash scripts/agent-status.sh "preflight" "ok" "install" "low" "preflight passed"
else
  bash scripts/agent-status.sh "preflight" "fail" "fix_and_retry" "medium" "preflight failed; read /tmp/devenv-preflight.log"
  rg "FAIL|WARN" /tmp/devenv-preflight.log || true
  exit 1
fi
AGENTPREFLIGHT
chmod +x "${OUT}/scripts/agent-preflight.sh"

# ---- agent-install.sh ----
cat > "${OUT}/scripts/agent-install.sh" <<'AGENTINSTALL'
#!/usr/bin/env bash
# 에이전트용 설치 래퍼 (구조화 결과 + 저토큰 로그)
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env

LOG_DIR=".agent-logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"

bash scripts/agent-status.sh "install" "running" "install_all" "low" "starting install-all"
if bash scripts/install-all.sh >"${LOG_FILE}" 2>&1; then
  bash scripts/agent-status.sh "install" "ok" "health_check" "low" "install completed"
else
  bash scripts/agent-status.sh "install" "fail" "collect_logs" "high" "install failed; collecting last logs"
  docker logs "gitlab-${PROJECT_NAME}" --tail 40 2>/dev/null || true
  docker logs "nexus-${PROJECT_NAME}" --tail 40 2>/dev/null || true
  docker logs "jenkins-${PROJECT_NAME}" --tail 40 2>/dev/null || true
  echo "log_file=${LOG_FILE}"
  exit 1
fi
AGENTINSTALL
chmod +x "${OUT}/scripts/agent-install.sh"

# ---- agent-verify.sh ----
cat > "${OUT}/scripts/agent-verify.sh" <<'AGENTVERIFY'
#!/usr/bin/env bash
# 에이전트용 헬스체크 래퍼 (요약 JSON)
set -euo pipefail
cd "$(dirname "$0")/.."

if bash scripts/health-check.sh >/tmp/devenv-health.log 2>&1; then
  bash scripts/agent-status.sh "verify" "ok" "complete" "low" "health-check passed"
else
  bash scripts/agent-status.sh "verify" "fail" "inspect_health_log" "medium" "health-check failed; read /tmp/devenv-health.log"
  rg "FAIL|WARN|INFO" /tmp/devenv-health.log || true
  exit 1
fi
AGENTVERIFY
chmod +x "${OUT}/scripts/agent-verify.sh"

# ---- agent-orchestrator.py ----
cat > "${OUT}/scripts/agent-orchestrator.py" <<'AGENTORCH'
#!/usr/bin/env python3
"""devenv-core agent orchestrator.

Runs:
  1) agent-preflight.sh
  2) agent-install.sh
  3) agent-verify.sh

Parses the last JSON status line from each step and prints compact summary.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent


def _write_jsonl(path: str | None, obj: dict[str, Any]) -> None:
    if not path:
        return
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    if (not p.exists()) or p.stat().st_size == 0:
        schema_obj = {"event": "schema", "version": 1, "emitted_at": __import__("datetime").datetime.utcnow().isoformat() + "Z"}
        with p.open("a", encoding="utf-8") as f:
            f.write(json.dumps(schema_obj, ensure_ascii=False) + "\n")
    with p.open("a", encoding="utf-8") as f:
        f.write(json.dumps(obj, ensure_ascii=False) + "\n")


def _emit(obj: dict[str, Any], quiet: bool, jsonl_file: str | None) -> None:
    _write_jsonl(jsonl_file, obj)
    if not quiet:
        print(json.dumps(obj, ensure_ascii=False))


def _has_sudo_non_interactive() -> bool:
    check = subprocess.run(
        ["sudo", "-n", "true"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    return check.returncode == 0


def _ensure_privilege(quiet: bool, jsonl_file: str | None) -> int:
    if os.geteuid() == 0:
        _emit(
            {
                "phase": "privilege",
                "status": "ok",
                "action": "root_bootstrap",
                "risk": "low",
                "message": "running as root",
            },
            quiet,
            jsonl_file,
        )
        return 0

    if _has_sudo_non_interactive():
        _emit(
            {
                "phase": "privilege",
                "status": "ok",
                "action": "root_bootstrap",
                "risk": "low",
                "message": "sudo non-interactive available",
            },
            quiet,
            jsonl_file,
        )
        return 0

    _emit(
        {
            "phase": "privilege",
            "status": "fail",
            "action": "sudo_v_required",
            "risk": "high",
            "message": "run 'sudo -v' first or execute as root",
        },
        quiet,
        jsonl_file,
    )
    return 1


def _run_root_bootstrap(quiet: bool, jsonl_file: str | None) -> int:
    script_path = ROOT / "scripts" / "00-root-bootstrap.sh"
    cmd = ["sudo", "bash", str(script_path)]
    if os.geteuid() == 0:
        cmd = ["bash", str(script_path)]
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, check=False)
    if proc.returncode == 0:
        _emit(
            {
                "phase": "root_bootstrap",
                "status": "ok",
                "action": "preflight",
                "risk": "low",
                "message": "root bootstrap completed",
            },
            quiet,
            jsonl_file,
        )
        return 0
    _emit(
        {
            "phase": "root_bootstrap",
            "status": "fail",
            "action": "inspect_root_log",
            "risk": "high",
            "message": "root bootstrap failed",
        },
        quiet,
        jsonl_file,
    )
    log = ((proc.stdout or "") + ("\n" + proc.stderr if proc.stderr else "")).splitlines()[-40:]
    if log and not quiet:
        print("----- failure_tail_start -----")
        print("\n".join(log))
        print("----- failure_tail_end -----")
    return 1


def _run_step(script_name: str) -> dict[str, Any]:
    script_path = ROOT / "scripts" / script_name
    proc = subprocess.run(
        ["bash", str(script_path)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    combined = (proc.stdout or "") + ("\n" + proc.stderr if proc.stderr else "")
    lines = [line.strip() for line in combined.splitlines() if line.strip()]

    status_obj: dict[str, Any] = {
        "phase": script_name,
        "status": "fail" if proc.returncode else "ok",
        "action": "inspect_logs" if proc.returncode else "next",
        "risk": "medium" if proc.returncode else "low",
        "message": "no structured status emitted",
    }
    for line in reversed(lines):
        if not (line.startswith("{") and line.endswith("}")):
            continue
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            status_obj = parsed
            break

    status_obj["exit_code"] = proc.returncode
    status_obj["raw_log"] = combined
    return status_obj


def main() -> int:
    parser = argparse.ArgumentParser(description="devenv-core agent orchestrator")
    parser.add_argument("--quiet", action="store_true", help="Suppress stdout JSON and tail logs")
    parser.add_argument("--jsonl-file", default="", help="Write JSON status events to file")
    args = parser.parse_args()
    jsonl_file = args.jsonl_file or None

    if _ensure_privilege(args.quiet, jsonl_file) != 0:
        return 1
    if _run_root_bootstrap(args.quiet, jsonl_file) != 0:
        return 1

    steps = ["agent-preflight.sh", "agent-install.sh", "agent-verify.sh"]
    results: list[dict[str, Any]] = []

    for step in steps:
        result = _run_step(step)
        results.append(result)
        summary = {
            "phase": result.get("phase", step),
            "status": result.get("status", "unknown"),
            "action": result.get("action", "inspect"),
            "risk": result.get("risk", "unknown"),
            "message": result.get("message", ""),
            "exit_code": result.get("exit_code", 1),
        }
        _emit(summary, args.quiet, jsonl_file)

        if result.get("exit_code", 1) != 0:
            tail_lines = (result.get("raw_log", "") or "").splitlines()[-40:]
            if tail_lines and not args.quiet:
                print("----- failure_tail_start -----")
                print("\n".join(tail_lines))
                print("----- failure_tail_end -----")
            return 1

    _emit(
        {
            "phase": "orchestrator",
            "status": "ok",
            "action": "complete",
            "risk": "low",
            "message": "all agent steps passed",
        },
        args.quiet,
        jsonl_file,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
AGENTORCH
chmod +x "${OUT}/scripts/agent-orchestrator.py"

# ---- health-check.sh ----
cat > "${OUT}/scripts/health-check.sh" <<'HEALTH'
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
source config.env

G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; N='\033[0m'

probe() {
  local name="$1" url="$2"
  if curl -fsS --max-time 5 "${url}" >/dev/null 2>&1; then
    echo -e "${G}[ OK ]${N} ${name} — ${url}"
    return 0
  else
    echo -e "${R}[FAIL]${N} ${name} — ${url}"
    return 1
  fi
}

FAILS=0
probe "GitLab"  "http://127.0.0.1:${HOST_PORT_GITLAB}/users/sign_in" || FAILS=$((FAILS+1))
probe "Nexus"   "http://127.0.0.1:${HOST_PORT_NEXUS_UI}/service/rest/v1/status" || FAILS=$((FAILS+1))
probe "Jenkins" "http://127.0.0.1:${HOST_PORT_JENKINS}/login" || FAILS=$((FAILS+1))

# Bastion: SSH banner 확인 (오탐 방지)
if timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/${HOST_PORT_BASTION_SSH}; head -c 8 <&3 | grep -q '^SSH-'"; then
  echo -e "${G}[ OK ]${N} Bastion — ssh -p ${HOST_PORT_BASTION_SSH} devops@${BASTION_IP}"
else
  echo -e "${R}[FAIL]${N} [CORE-E030] Bastion SSH 배너 응답 없음 (${HOST_PORT_BASTION_SSH})"
  FAILS=$((FAILS+1))
fi

if [[ ${FAILS} -gt 0 ]]; then
  echo
  echo -e "${Y}[INFO]${N} health-check 실패 원인 파악용 로그(최근 50줄)"
  docker ps -a --format 'table {{.Names}}\t{{.Status}}'
  docker logs "gitlab-${PROJECT_NAME}" --tail 50 2>/dev/null || true
  docker logs "nexus-${PROJECT_NAME}" --tail 50 2>/dev/null || true
  docker logs "jenkins-${PROJECT_NAME}" --tail 50 2>/dev/null || true
  exit 1
fi

if [[ -x scripts/smoke-cross-service.sh ]]; then
  bash scripts/smoke-cross-service.sh || true
fi
if [[ -x scripts/backup.sh ]]; then
  bash scripts/backup.sh --dry-run || true
fi
HEALTH
chmod +x "${OUT}/scripts/health-check.sh"

# ---- backup.sh ----
cat > "${OUT}/scripts/backup.sh" <<'BACKUP'
#!/usr/bin/env bash
# 서비스 볼륨 및 config 백업
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env

DRY_RUN=0
RETENTION_DAYS="${RETENTION_DAYS:-7}"
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="backups/${TS}"
mkdir -p "${BACKUP_DIR}"

echo "[ * ] config 백업"
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "[DRY-RUN] cp config.env ${BACKUP_DIR}/config.env"
  echo "[DRY-RUN] cp -r docker-compose ${BACKUP_DIR}/docker-compose"
else
  cp config.env "${BACKUP_DIR}/config.env"
  cp -r docker-compose "${BACKUP_DIR}/docker-compose"
fi

backup_volume() {
  local vol="$1"
  local out="$2"
  echo "[ * ] volume 백업: ${vol}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[DRY-RUN] docker run -v ${vol}:/volume:ro ..."
    return 0
  fi
  docker run --rm \
    -v "${vol}:/volume:ro" \
    -v "$(pwd)/${BACKUP_DIR}:/backup" \
    alpine:3.20 \
    sh -c "tar czf /backup/${out} -C /volume ."
}

backup_volume "devenv-${PROJECT_NAME}_gitlab_data" "gitlab_data.tgz"
backup_volume "devenv-${PROJECT_NAME}_nexus_data" "nexus_data.tgz"
backup_volume "devenv-${PROJECT_NAME}_jenkins_home" "jenkins_home.tgz"
find backups -mindepth 1 -maxdepth 1 -type d -mtime +"${RETENTION_DAYS}" -exec rm -rf {} + 2>/dev/null || true

echo "[ OK ] 백업 완료: ${BACKUP_DIR}"
BACKUP
chmod +x "${OUT}/scripts/backup.sh"

# ---- restore.sh ----
cat > "${OUT}/scripts/restore.sh" <<'RESTORE'
#!/usr/bin/env bash
# 백업 디렉토리에서 볼륨/설정 복원
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env

SRC="${1:-}"
if [[ -z "${SRC}" || ! -d "${SRC}" ]]; then
  echo "사용법: bash scripts/restore.sh backups/<timestamp>" >&2
  exit 1
fi

read -r -p "기존 데이터가 덮어써집니다. 계속할까요? (yes 입력) " ans
[[ "${ans}" == "yes" ]] || { echo "취소됨"; exit 0; }

restore_volume() {
  local vol="$1"
  local arc="$2"
  local path="${SRC}/${arc}"
  if [[ ! -f "${path}" ]]; then
    echo "[WARN] 백업 없음: ${path}"
    return 0
  fi
  echo "[ * ] volume 복원: ${vol}"
  docker volume create "${vol}" >/dev/null
  docker run --rm \
    -v "${vol}:/volume" \
    -v "$(pwd)/${SRC}:/backup:ro" \
    alpine:3.20 \
    sh -c "rm -rf /volume/* && tar xzf /backup/${arc} -C /volume"
}

if [[ -f "${SRC}/config.env" ]]; then
  cp "${SRC}/config.env" ./config.env
fi

restore_volume "devenv-${PROJECT_NAME}_gitlab_data" "gitlab_data.tgz"
restore_volume "devenv-${PROJECT_NAME}_nexus_data" "nexus_data.tgz"
restore_volume "devenv-${PROJECT_NAME}_jenkins_home" "jenkins_home.tgz"

echo "[ OK ] 복원 완료. 다음 권장 명령:"
echo "  bash scripts/install-all.sh"
echo "  bash scripts/health-check.sh"
RESTORE
chmod +x "${OUT}/scripts/restore.sh"

# ---- teardown.sh (안전 가드 + 옵션) ----
cat > "${OUT}/scripts/teardown.sh" <<'TEARDOWN'
#!/usr/bin/env bash
# 위험: 컨테이너/볼륨 삭제 — 데이터 손실
# 사용법:
#   bash scripts/teardown.sh                  # 기본: 컨테이너 + 볼륨 + 네트워크 모두 삭제 (yes 확인 필요)
#   bash scripts/teardown.sh --dry-run        # 실행할 명령만 출력 (안전)
#   bash scripts/teardown.sh --keep-volumes   # 컨테이너만 내리고 볼륨 보존 (데이터 유지)
#   bash scripts/teardown.sh --purge-secrets  # 추가로 secrets/*.env 파일 shred
#   bash scripts/teardown.sh --no-prompt      # 비대화 모드 (CI 등) — 5초 대기 없음
set -uo pipefail
cd "$(dirname "$0")/.."
source config.env

DRY_RUN=0; KEEP_VOLUMES=0; PURGE_SECRETS=0; NO_PROMPT=0
for arg in "$@"; do
  case "${arg}" in
    --dry-run) DRY_RUN=1 ;;
    --keep-volumes) KEEP_VOLUMES=1 ;;
    --purge-secrets) PURGE_SECRETS=1 ;;
    --no-prompt) NO_PROMPT=1 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "[FAIL] 미인식 옵션: ${arg}"; exit 2 ;;
  esac
done

DOWN_FLAG="-v"
[[ ${KEEP_VOLUMES} -eq 1 ]] && DOWN_FLAG=""

run() {
  if [[ ${DRY_RUN} -eq 1 ]]; then
    echo "[DRY-RUN] $*"
  else
    eval "$@"
  fi
}

if [[ ${DRY_RUN} -eq 0 ]]; then
  echo "이 작업은 devenv-${PROJECT_NAME} 의 컨테이너${KEEP_VOLUMES:+}$( [[ ${KEEP_VOLUMES} -eq 0 ]] && echo '와 볼륨' )를 제거합니다."
  if [[ ${NO_PROMPT} -eq 0 && -t 0 ]]; then
    echo "최근 백업이 있나요? 없으면 Ctrl+C 후 'bash scripts/backup.sh' 먼저 실행하세요. (5초 대기)"
    sleep 5
    read -r -p "정말 진행하시겠습니까? (yes 입력) " ans
    [[ "${ans}" == "yes" ]] || { echo "취소됨"; exit 0; }
  fi
fi

# core + security + observe + app 컨테이너 일괄 정리 (미존재 silent skip)
SERVICES=(jenkins nexus gitlab bastion sonarqube sonar-db zap prometheus grafana loki promtail node-exporter cadvisor alertmanager skywalking-oap skywalking-ui backend frontend admin mysql)
for svc in "${SERVICES[@]}"; do
  cf="docker-compose/docker-compose.${svc}.yml"
  [[ -f "${cf}" ]] || continue
  run "docker compose -f '${cf}' --project-name 'devenv-${PROJECT_NAME}' down ${DOWN_FLAG} 2>/dev/null || true"
done

# 네트워크 정리
run "docker network rm devenv-internal 2>/dev/null || true"

if [[ ${PURGE_SECRETS} -eq 1 ]]; then
  for f in secrets/*.env; do
    [[ -f "${f}" ]] || continue
    if command -v shred >/dev/null 2>&1; then
      run "shred -u '${f}'"
    else
      run "rm -f '${f}'"
    fi
  done
fi

if [[ ${DRY_RUN} -eq 1 ]]; then
  echo "[DRY-RUN] 위 명령들이 실행될 예정입니다. 실제 실행은 --dry-run 제거."
else
  echo "[ OK ] teardown 완료"
fi
TEARDOWN
chmod +x "${OUT}/scripts/teardown.sh"

# ---- ssl-init.sh (TLS 인증서 자동 준비: self-signed | letsencrypt | public) ----
cat > "${OUT}/scripts/ssl-init.sh" <<'SSLINIT'
#!/usr/bin/env bash
# SSL 인증서 자동 준비
# - self-signed: openssl req -x509 자체서명 (825일, SAN 포함)
# - letsencrypt: certbot standalone (80 포트 필요, GitLab 정지 후 실행 권장)
# - public:      사용자가 ${SSL_DIR}에 fullchain.pem / privkey.pem 직접 배치
# - none:        skip
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env

SSL_DIR="configs/nginx/ssl"
mkdir -p "${SSL_DIR}"
FORCE="${1:-}"

case "${SSL_TYPE:-self-signed}" in
  self-signed)
    if [[ -f "${SSL_DIR}/fullchain.pem" && -f "${SSL_DIR}/privkey.pem" && "${FORCE}" != "--force" ]]; then
      echo "[ OK ] self-signed 인증서 이미 존재 — 재생성 생략 (강제: --force)"
      exit 0
    fi
    CN="${DOMAIN:-localhost}"
    SAN="DNS:${CN},DNS:localhost,IP:127.0.0.1"
    [[ -n "${BASTION_IP:-}" ]] && SAN="${SAN},IP:${BASTION_IP}"
    [[ -n "${GITLAB_IP:-}" ]]  && SAN="${SAN},IP:${GITLAB_IP}"
    [[ -n "${NEXUS_IP:-}" ]]   && SAN="${SAN},IP:${NEXUS_IP}"
    [[ -n "${JENKINS_IP:-}" ]] && SAN="${SAN},IP:${JENKINS_IP}"
    openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
      -keyout "${SSL_DIR}/privkey.pem" \
      -out   "${SSL_DIR}/fullchain.pem" \
      -subj "/CN=${CN}/O=devenv-${PROJECT_NAME}" \
      -addext "subjectAltName=${SAN}"
    chmod 600 "${SSL_DIR}/privkey.pem"
    echo "[ OK ] self-signed 인증서 생성 — CN=${CN} (825일 유효)"
    ;;
  letsencrypt)
    [[ -z "${DOMAIN:-}" ]] && { echo "[FAIL] letsencrypt은 DOMAIN 필수"; exit 1; }
    [[ -z "${SSL_CONTACT_EMAIL:-}" ]] && { echo "[FAIL] SSL_CONTACT_EMAIL 필요 (config.env)"; exit 1; }
    echo "[INFO] 80 포트가 비어있어야 합니다 (GitLab/Nginx 정지 후 실행 권장)"
    docker run --rm \
      -v "$(pwd)/${SSL_DIR}:/etc/letsencrypt/live/${DOMAIN}" \
      -p 80:80 \
      certbot/certbot:latest certonly --standalone \
      --non-interactive --agree-tos \
      --email "${SSL_CONTACT_EMAIL}" \
      -d "${DOMAIN}"
    echo "[ OK ] letsencrypt 인증서 발급 완료 — ${DOMAIN}"
    ;;
  public)
    if [[ ! -f "${SSL_DIR}/fullchain.pem" || ! -f "${SSL_DIR}/privkey.pem" ]]; then
      echo "[FAIL] public: ${SSL_DIR}/fullchain.pem · privkey.pem 직접 배치 필요"
      exit 1
    fi
    echo "[ OK ] public 인증서 사용 — ${SSL_DIR}"
    ;;
  none)
    echo "[INFO] SSL_TYPE=none — 인증서 생성 생략"
    ;;
  *)
    echo "[FAIL] SSL_TYPE 미인식: ${SSL_TYPE}"
    exit 1 ;;
esac
SSLINIT
chmod +x "${OUT}/scripts/ssl-init.sh"

# ---- enable-cron-backup.sh (백업 자동 실행 등록) ----
cat > "${OUT}/scripts/enable-cron-backup.sh" <<'CRONBACKUP'
#!/usr/bin/env bash
# 백업 자동 실행 등록 — systemd --user timer 우선 → crontab fallback
# WSL2 호스트는 일반적으로 systemd timer 가능. 진정한 24/7은 Windows Task Scheduler 별도 등록 권장.
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env

LOG="${HOME}/devenv-${PROJECT_NAME}/backups/cron.log"
mkdir -p "$(dirname "${LOG}")"

# 1) systemd --user timer (logind 세션 있을 때)
if command -v systemctl >/dev/null 2>&1 && systemctl --user is-system-running --quiet 2>/dev/null; then
  UNIT_DIR="${HOME}/.config/systemd/user"
  mkdir -p "${UNIT_DIR}"
  cat > "${UNIT_DIR}/devenv-${PROJECT_NAME}-backup.service" <<EOF
[Unit]
Description=devenv-${PROJECT_NAME} backup
[Service]
Type=oneshot
WorkingDirectory=${PWD}
ExecStart=/bin/bash scripts/backup.sh
EOF
  cat > "${UNIT_DIR}/devenv-${PROJECT_NAME}-backup.timer" <<EOF
[Unit]
Description=devenv-${PROJECT_NAME} daily backup
[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now "devenv-${PROJECT_NAME}-backup.timer"
  echo "[ OK ] systemd --user timer 등록 (devenv-${PROJECT_NAME}-backup.timer)"
  exit 0
fi

# 2) crontab fallback (PROJECT_NAME 주석으로 다중 프로젝트 충돌 회피)
if command -v crontab >/dev/null 2>&1; then
  TAG="# devenv-${PROJECT_NAME}-backup"
  LINE="0 3 * * * cd ${PWD} && bash scripts/backup.sh >> ${LOG} 2>&1 ${TAG}"
  (crontab -l 2>/dev/null | grep -vF -- "${TAG}" ; echo "${LINE}") | crontab -
  echo "[ OK ] crontab 등록 — '${TAG}'"
  exit 0
fi

echo "[FAIL] systemd --user / crontab 모두 사용 불가 — 수동 등록 필요"
exit 1
CRONBACKUP
chmod +x "${OUT}/scripts/enable-cron-backup.sh"

# ---- enable-wsl-autostart.sh (WSL 재부팅 자동 복구, opt-in) ----
cat > "${OUT}/scripts/enable-wsl-autostart.sh" <<'WSLAUTO'
#!/usr/bin/env bash
# 사용자가 명시적으로 실행해야만 등록됨 (기본 OFF).
# 1) systemd --user unit (sg docker re-exec 적용)
# 2) WSL2 환경에서 .bashrc 가드 라인 (세션당 1회)
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env

UNIT_DIR="${HOME}/.config/systemd/user"
mkdir -p "${UNIT_DIR}"
cat > "${UNIT_DIR}/devenv-${PROJECT_NAME}-autostart.service" <<EOF
[Unit]
Description=devenv-${PROJECT_NAME} containers autostart
After=docker.service
[Service]
Type=oneshot
WorkingDirectory=${PWD}
# lessons-learned §1: sg docker re-exec로 docker 그룹 적용
ExecStart=/usr/bin/sg docker -c 'bash scripts/install-all.sh'
[Install]
WantedBy=default.target
EOF
if command -v systemctl >/dev/null 2>&1 && systemctl --user is-system-running --quiet 2>/dev/null; then
  systemctl --user daemon-reload
  systemctl --user enable "devenv-${PROJECT_NAME}-autostart.service"
  echo "[ OK ] systemd --user unit 등록 — 다음 로그인부터 자동 기동"
else
  echo "[INFO] systemd --user 비활성 — .bashrc 가드만 추가 (WSL2 환경 권장)"
fi

# WSL2 우회: .bashrc에 세션당 1회 가드 라인 추가
if grep -qi microsoft /proc/version 2>/dev/null; then
  GUARD="${HOME}/.devenv-${PROJECT_NAME}-autostart.flag"
  MARK="# devenv-${PROJECT_NAME}-autostart"
  if ! grep -qF -- "${MARK}" "${HOME}/.bashrc" 2>/dev/null; then
    cat >> "${HOME}/.bashrc" <<EOF

${MARK}
if [[ -z "\${DEVENV_${PROJECT_NAME//-/_}_STARTED:-}" && ! -f "${GUARD}" ]]; then
  export DEVENV_${PROJECT_NAME//-/_}_STARTED=1
  touch "${GUARD}"
  ( cd ${PWD} && nohup bash scripts/install-all.sh >/tmp/devenv-${PROJECT_NAME}-autostart.log 2>&1 & )
fi
EOF
    echo "[ OK ] WSL2 .bashrc 가드 라인 추가 — 새 셸 첫 진입 시 1회 기동"
  else
    echo "[ OK ] .bashrc 가드 라인 이미 존재 — 변경 없음"
  fi
fi
echo
echo "비활성화: systemctl --user disable devenv-${PROJECT_NAME}-autostart.service"
echo "          + ~/.bashrc의 '${MARK:-#}' 블록 수동 제거"
WSLAUTO
chmod +x "${OUT}/scripts/enable-wsl-autostart.sh"

# ---- install-windows-task.ps1 (Windows 로그온 시 WSL devenv 자동 기동) ----
cat > "${OUT}/scripts/install-windows-task.ps1" <<'WINTASK'
# Windows 로그온 시 WSL devenv 컨테이너 자동 기동 등록
# 사용법: 관리자 PowerShell에서 .\install-windows-task.ps1
# 비활성: Unregister-ScheduledTask -TaskName "devenv-<project>-autostart" -Confirm:$false
param(
  [string]$Distro = "Ubuntu-22.04",
  [string]$Project = $env:DEVENV_PROJECT
)
if (-not $Project) { Write-Error "DEVENV_PROJECT 환경변수 또는 -Project 인자 필요"; exit 1 }

$WslCmd = "wsl.exe -d $Distro -- bash -lc 'cd ~/devenv-$Project && bash scripts/install-all.sh >/dev/null 2>&1 || true'"
$Action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-NoProfile -WindowStyle Hidden -Command `"$WslCmd`""
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
  -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5)
$TaskName = "devenv-$Project-autostart"
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger `
  -Settings $Settings -RunLevel Highest -Force | Out-Null
Write-Output "[ OK ] Scheduled Task 등록 - $TaskName"
WINTASK
chmod +x "${OUT}/scripts/install-windows-task.ps1"

# ---- devenv-doctor.sh (통합 진단 명령) ----
cat > "${OUT}/scripts/devenv-doctor.sh" <<'DOCTOR'
#!/usr/bin/env bash
# devenv-doctor — 설치 전/중/후 모든 진단을 단일 진입점에서 실행
# 사용법:
#   bash scripts/devenv-doctor.sh             # auto: 컨테이너 상태 보고 분기
#   bash scripts/devenv-doctor.sh preflight   # 설치 전 점검
#   bash scripts/devenv-doctor.sh health      # 설치 후 헬스체크
#   bash scripts/devenv-doctor.sh smoke       # 교차 서비스 통합 테스트
#   bash scripts/devenv-doctor.sh all         # 전체
set -uo pipefail
cd "$(dirname "$0")/.."
source config.env

MODE="${1:-auto}"
EXIT_CODE=0

run_section() {
  local label="$1"; shift
  echo
  echo "===== ${label} ====="
  if "$@"; then
    echo "[ PASS ] ${label}"
  else
    echo "[ FAIL ] ${label}"
    EXIT_CODE=1
  fi
}

# auto 모드: docker network/컨테이너 유무 보고 분기
detect_phase() {
  if ! docker network inspect devenv-internal >/dev/null 2>&1; then
    echo "preflight"
  elif ! docker ps --format '{{.Names}}' | grep -q "${PROJECT_NAME}"; then
    echo "preflight"
  else
    echo "health-and-smoke"
  fi
}

[[ "${MODE}" == "auto" ]] && MODE="$(detect_phase)"

case "${MODE}" in
  preflight)
    run_section "Preflight" bash scripts/00-preflight.sh ;;
  health)
    run_section "Health" bash scripts/health-check.sh ;;
  smoke)
    run_section "Smoke" bash scripts/smoke-cross-service.sh ;;
  health-and-smoke)
    run_section "Health" bash scripts/health-check.sh
    run_section "Smoke"  bash scripts/smoke-cross-service.sh ;;
  all)
    run_section "Preflight" bash scripts/00-preflight.sh
    run_section "Health"    bash scripts/health-check.sh
    run_section "Smoke"     bash scripts/smoke-cross-service.sh ;;
  *)
    echo "사용법: bash scripts/devenv-doctor.sh [auto|preflight|health|smoke|all]"
    exit 2 ;;
esac

echo
echo "===== 컨테이너 상태 ====="
docker ps -a --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null | grep -E "(NAMES|${PROJECT_NAME})" || echo "(컨테이너 없음)"
echo
echo "===== 호스트 자원 ====="
df -h / 2>/dev/null | tail -2 || true
free -h 2>/dev/null | head -2 || true

exit ${EXIT_CODE}
DOCTOR
chmod +x "${OUT}/scripts/devenv-doctor.sh"

log "운영 스크립트 12종 인라인 생성 (root-bootstrap, preflight, bootstrap, install-{4종}, wait-for-http, install-all, post-install, health-check, backup, restore, teardown)"
log "PR-3 운영 스크립트 5종 추가 (ssl-init, enable-cron-backup, enable-wsl-autostart, install-windows-task.ps1, devenv-doctor)"
log "에이전트 스크립트 5종 생성 (agent-status, agent-preflight, agent-install, agent-verify, agent-orchestrator)"

# ============================================================
# STEP 10. references 복사
# ============================================================
if [[ -d "${SKILL_ROOT}/references" ]]; then
  cp -r "${SKILL_ROOT}/references/." "${OUT}/references/"
fi

# ============================================================
# STEP 11. README
# ============================================================
cat > "${OUT}/README.md" <<EOF
# ${PROJECT_NAME} — devenv-core 산출물

구성 모드: ${COMPOSE_MODE}

## 서버 구성

| 서버 | IP | 포트 | URL |
|------|----|------|------|
| Bastion | ${BASTION_IP} | ${HOST_PORT_BASTION_SSH} | ssh -p ${HOST_PORT_BASTION_SSH} devops@${BASTION_IP} |
| GitLab  | ${GITLAB_IP}  | ${HOST_PORT_GITLAB} (HTTP), ${HOST_PORT_GITLAB_SSH} (SSH) | http://${GITLAB_IP}:${HOST_PORT_GITLAB} |
| Nexus   | ${NEXUS_IP}   | ${HOST_PORT_NEXUS_UI}, ${HOST_PORT_NEXUS_REGISTRY} | http://${NEXUS_IP}:${HOST_PORT_NEXUS_UI} |
| Jenkins | ${JENKINS_IP} | ${HOST_PORT_JENKINS} | http://${JENKINS_IP}:${HOST_PORT_JENKINS} |

## 빠른 시작

\`\`\`bash
bash scripts/00-root-bootstrap.sh          # root 권한으로 1회
bash scripts/00-preflight.sh    # 사전 점검
bash scripts/01-bootstrap.sh    # 네트워크/볼륨 준비
bash scripts/install-all.sh     # 순차 설치 + 준비 완료 대기
bash scripts/health-check.sh    # 헬스체크
\`\`\`

## 백업/복구

\`\`\`bash
bash scripts/backup.sh
bash scripts/restore.sh backups/<timestamp>
bash scripts/enable-cron-backup.sh        # 매일 03:00 자동 백업 (systemd timer 또는 crontab)
\`\`\`

WSL2 환경에서 진정한 24/7 백업이 필요하면 호스트 Windows에서:

\`\`\`powershell
# 관리자 PowerShell에서 1회 실행 (DEVENV_PROJECT 환경변수 또는 -Project 인자)
.\scripts\install-windows-task.ps1 -Project ${PROJECT_NAME}
\`\`\`

## TLS 인증서 (자동)

\`\`\`bash
# install-all.sh가 자동 호출. 수동 재발급은:
bash scripts/ssl-init.sh              # SSL_TYPE에 따라 self-signed/letsencrypt/public
bash scripts/ssl-init.sh --force      # 자체서명 강제 재생성
\`\`\`

> **letsencrypt**: 80 포트가 필요하므로 GitLab을 잠시 정지 후 실행하세요.
> \`docker compose -f docker-compose/docker-compose.gitlab.yml stop\` → \`ssl-init.sh\` → GitLab 재기동.

## 통합 진단

\`\`\`bash
bash scripts/devenv-doctor.sh           # auto: 컨테이너 상태 감지 후 적절히 분기
bash scripts/devenv-doctor.sh preflight # 설치 전
bash scripts/devenv-doctor.sh health    # 설치 후 헬스체크
bash scripts/devenv-doctor.sh smoke     # 교차 서비스 통합
bash scripts/devenv-doctor.sh all       # 전체 (preflight + health + smoke)
\`\`\`

## 에이전트 모드 (저토큰)

\`\`\`bash
python3 scripts/agent-orchestrator.py
python3 scripts/agent-orchestrator.py --quiet
python3 scripts/agent-orchestrator.py --jsonl-file .agent-logs/status.jsonl
\`\`\`

## 초기 비밀번호

\`config.env\` (chmod 600). **Git에 커밋 금지.**

## 다음 스킬

- devenv-security : SonarQube, Trivy, OWASP ZAP
- devenv-observe  : Prometheus, Grafana, Loki, APM
- devenv-app      : 앱 서버, DB, 샘플 앱 (마지막)
EOF

log "README.md 생성"

echo ""
echo "============================================"
log "devenv-${PROJECT_NAME} core 산출물 생성 완료"
echo "============================================"
echo "위치: ${OUT}"
echo ""
echo "다음 단계:"
echo "  cd ${OUT}"
echo "  bash scripts/00-preflight.sh"
echo "  bash scripts/01-bootstrap.sh"
echo "  bash scripts/install-all.sh"
