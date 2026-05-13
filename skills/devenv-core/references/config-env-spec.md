# config.env 작성 명세 (devenv-core 범위)

`config.env`는 에이전트(PHASE 3/5 수집값) ↔ `generate-configs.sh` 사이의 **인터페이스**입니다.
에이전트는 사용자에게 받은 값을 이 파일에 채워 넣고 generate-configs.sh를 실행합니다.

> 이 명세는 **devenv-core 범위만 다룹니다.**
> DB / Backend / Frontend / Admin / Security / Observe 변수는
> 각각 devenv-app / devenv-security / devenv-observe 스킬에서 별도로 작성합니다.

## 작성 규칙

1. **모든 placeholder가 실제 값으로 채워져야 합니다.** `{...}` 형태가 남아있으면 generate-configs.sh가 즉시 실패합니다.
2. **비밀번호는 PHASE 5에서 공통 1회 입력한 `ADMIN_SHARED_PASSWORD`를 기본값으로 사용합니다.** 필요 시 서비스별 override를 둘 수 있습니다.
3. **IP 변수**: 단일 서버 모드는 모두 같은 IP, 다중 서버 모드는 각각 다른 IP.
4. **파일 위치**: `~/devenv-{project_name}/config.env` (생성기 실행 후)
5. **권한**: 자동으로 `chmod 600` 적용됨. **Git에 커밋 금지.**

## 전체 템플릿 (core 한정)

```bash
# ============================================================
# 프로젝트 / 인프라
# ============================================================
PROJECT_NAME="myproject"                # 영문 소문자 + 하이픈, 3~32자
OS_TYPE="ubuntu22"                    # ubuntu22 | ubuntu20 | macos
COMPOSE_MODE="single"                 # single | multi
INTERNAL_NETWORK="10.0.1.0/24"
DOMAIN=""                             # 예: dev.example.com (없으면 빈 문자열)
TIMEZONE="Asia/Seoul"

# ============================================================
# 접근 보안
# ============================================================
SSL_TYPE="none"                       # none | self-signed | letsencrypt | public
SSH_VIA_BASTION="y"                   # y | n
TEAM_SIZE="5"

# ============================================================
# 서버 IP (4개)
# ============================================================
BASTION_IP="10.0.1.10"
GITLAB_IP="10.0.1.11"
NEXUS_IP="10.0.1.12"
JENKINS_IP="10.0.1.13"

# ============================================================
# 자격증명 (PHASE 5에서 수집)
# ============================================================
ADMIN_SHARED_PASSWORD="<PHASE 5에서 입력 또는 자동 생성된 공통 관리자 비밀번호>"

JENKINS_ADMIN_USER="admin"
JENKINS_ADMIN_PASSWORD=""   # 비워두면 ADMIN_SHARED_PASSWORD 사용

GITLAB_ROOT_PASSWORD=""     # 비워두면 ADMIN_SHARED_PASSWORD 사용
GITLAB_ROOT_EMAIL="admin@myproject.local"   # 비워두면 admin@${PROJECT_NAME}.local

NEXUS_ADMIN_PASSWORD=""     # 비워두면 ADMIN_SHARED_PASSWORD 사용

# ============================================================
# 고정 버전 (비워두면 생성기 기본값 사용)
# ============================================================
GITLAB_VERSION="17.11.7-ce.0"
NEXUS_VERSION="3.78.2"

# ============================================================
# (선택) post-install이 채우는 값 — 처음에는 비워두면 됨
# ============================================================
GITLAB_TOKEN=""
```

## generate-configs.sh가 자동 결정하는 값

다음 값들은 사용자가 입력하지 않고 `COMPOSE_MODE`에 따라 자동 결정되어 최종 `config.env`에 추가됩니다:

```bash
# 단일 서버 모드
HOST_PORT_BASTION_SSH=2222
HOST_PORT_GITLAB=8082
HOST_PORT_GITLAB_SSH=2223
NEXUS_REGISTRY="127.0.0.1:5000"

# 다중 서버 모드
HOST_PORT_BASTION_SSH=22
HOST_PORT_GITLAB=80
HOST_PORT_GITLAB_SSH=22
NEXUS_REGISTRY="${NEXUS_IP}:5000"
```

## 검증 실패 케이스

generate-configs.sh가 다음을 자동 검증합니다:

- `PROJECT_NAME` 형식: `^[a-z][a-z0-9-]{1,30}[a-z0-9]$`
- IP 형식: `^([0-9]{1,3}\.){3}[0-9]{1,3}$`
- `COMPOSE_MODE` ∈ {single, multi}
- 모든 `REQUIRED_VARS` 값 존재 + placeholder(`{...}`) 잔존 없음
- `ADMIN_SHARED_PASSWORD` 또는 비밀번호 3종 중 필요한 값 존재

검증 실패 시 즉시 종료. 산출물은 생성되지 않습니다.
