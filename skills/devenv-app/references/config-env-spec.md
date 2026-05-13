# config.env 작성 명세

`config.env`는 docker-compose / shell script가 `source`해서 사용하는 **평문 변수 파일**입니다. 에이전트는 PHASE 3에서 수집한 값을 이 파일에 채워 PHASE 5/6의 설치·생성 단계에서 사용합니다.

## preset.json과의 관계

같은 정보를 두 형식으로 보관합니다(`${DEVENV_HOME}/` 같은 디렉토리에 위치):

| 파일 | 형식 | 사용 주체 | 책임 |
|------|------|----------|------|
| `preset.json` | 구조화 JSON | 에이전트 (devenv-* 스킬) | 4개 스킬 간 인터페이스, 진행 상태(`phaseProgress`) 기록 |
| `config.env` | KEY=VALUE 평문 | docker-compose / shell script | `source config.env` 또는 `--env-file` 로 변수 주입 |

에이전트는 PHASE 3 응답을 받으면 preset.json `app` 섹션과 config.env를 **동시에** 갱신합니다. 한쪽만 갱신하면 다음 PHASE에서 불일치가 발생합니다.

## 작성 규칙

1. **모든 placeholder가 실제 값으로 채워져야 합니다.** `{...}` 형태가 남아있으면 PHASE 5의 자동 검증이 즉시 실패합니다.
2. **비밀번호 변수는 비워두면 자동 생성**됩니다. (`openssl rand -base64 16`)
3. **IP 변수**: 단일 서버 모드는 모두 같은 IP, 다중 서버 모드는 각각 다른 IP를 입력합니다.
4. **파일 위치**: `${DEVENV_HOME}/config.env` (기본값 `~/devenv-{project_name}/config.env`)
5. **권한**: 생성 후 `chmod 600 config.env` (비밀번호 보호)

## 전체 템플릿

```bash
# ============================================================
# 프로젝트 / 인프라 (그룹 A)
# ============================================================
PROJECT_NAME="myproject"                # 영문 소문자 + 하이픈
SERVER_TYPE="cloud"                   # cloud | onpremise
CLOUD_PROVIDER="aws"                  # aws | gcp | azure | none
OS_TYPE="ubuntu22"                    # ubuntu22 | ubuntu20 | rhel8 | centos8
COMPOSE_MODE="single"                 # single | multi | k8s
INTERNAL_NETWORK="10.0.1.0/24"
DOMAIN=""                             # 예: dev.example.com (없으면 빈 문자열)
TIMEZONE="Asia/Seoul"

# ============================================================
# 개발 스택 (그룹 B)
# ============================================================
DEV_LANG="java"                       # java | nodejs | python | go
DEV_LANG_VERSION="17"                 # 메이저 버전
BUILD_TOOL="gradle"                   # maven | gradle | npm | yarn | pip
APP_PORT="8080"                       # Backend 앱 포트
FRONTEND_PORT="3000"
ADMIN_PORT="3100"                     # Admin(관리자) 앱 포트 (★ 신규)

# DB
DB_TYPE="mysql"                       # mysql | postgresql | mariadb | mongodb
DB_VERSION="8.0"
DB_PORT="3306"                        # mysql=3306, pg=5432, mongo=27017
DB_NAME="${PROJECT_NAME}_db"
DB_USER="${PROJECT_NAME}_user"
DB_PASSWORD=""                        # 비워두면 자동 생성
DB_ROOT_PASSWORD=""                   # 비워두면 자동 생성

# ============================================================
# CI/CD (그룹 C)
# ============================================================
GIT_STRATEGY="gitflow"                # gitflow | trunk | github-flow
DEPLOY_ENVS="dev,staging"             # dev | dev,staging | dev,staging,prod
DEPLOY_METHOD="rolling"               # rolling | blue-green | canary
AUTO_DEPLOY_DEV="y"                   # y | n
AUTO_DEPLOY_STAGING="n"
AUTO_DEPLOY_PROD="n"

# ============================================================
# 보안 / 관측성 (그룹 D)
# ============================================================
SECURITY_SONARQUBE="y"
SECURITY_ZAP="n"
SECURITY_TRIVY="y"
SECURITY_DEPCHECK="n"
MONITORING_STACK="prometheus"         # prometheus | zabbix
APM_TOOL="pinpoint"                   # pinpoint | skywalking | elastic-apm
LOG_STACK="loki"                      # elk | loki

# ============================================================
# 접근 보안 (그룹 E)
# ============================================================
SSL_TYPE="none"                       # letsencrypt | self-signed | public | none
VPN_USED="n"
SSH_VIA_BASTION="y"                   # y | n (n이면 Bastion 미생성)
TEAM_SIZE="5"

# ============================================================
# 서버 IP 매핑
# 단일 서버 모드(single): 모두 동일 IP 또는 127.0.0.1
# 다중 서버 모드(multi): 각각 별도 IP
# ============================================================
BASTION_IP="10.0.1.10"
GITLAB_IP="10.0.1.11"
NEXUS_IP="10.0.1.12"
JENKINS_IP="10.0.1.13"
DB_IP="10.0.1.20"
BACKEND_IP="10.0.1.21"
FRONTEND_IP="10.0.1.22"
ADMIN_IP="10.0.1.23"                  # ★ 신규: Admin(관리자) 앱 호스트 IP
SECURITY_IP="10.0.1.30"
MONITORING_IP="10.0.1.40"
APM_IP="10.0.1.41"
LOGGING_IP="10.0.1.42"

# ============================================================
# 앱 유형 / 프레임워크 (★ v3 신규)
# ============================================================
APP_TYPES="web"                       # web,api,mobile,admin (콤마 구분, 복수 가능)
BACKEND_FRAMEWORK="spring-boot"       # spring-boot|express|nestjs|fastapi|django|gin
FRONTEND_FRAMEWORK="react-vite"       # react-vite|nextjs|vue-vite|nuxt|angular|none
ADMIN_FRAMEWORK="react-vite"          # ★ 신규: react-vite|nextjs|vue-vite|nuxt|angular|none
                                       # (Frontend 템플릿 재사용 — 'admin' 디렉토리로 분리 배포)
MOBILE_FRAMEWORK="none"               # react-native|flutter|none

# ============================================================
# CI/CD 자동 연동 (★ v3 신규)
# ============================================================
SAMPLE_APP_GENERATE="y"               # y/n — y면 Hello World 샘플 앱 자동 생성
AUTO_CICD_SETUP="y"                   # y/n — y면 PHASE 5 완료 후 PHASE 6(GitLab/Jenkins 자동 연동)으로 진입

# ============================================================
# 자동 생성 변수 (비워두면 PHASE 5 검증/생성 단계가 채움)
# ============================================================
JENKINS_ADMIN_USER="admin"
JENKINS_ADMIN_PASSWORD=""
GITLAB_ROOT_PASSWORD=""
GITLAB_ROOT_EMAIL=""                  # 비우면 admin@{project}.local
NEXUS_ADMIN_PASSWORD=""
SONAR_ADMIN_PASSWORD=""
GRAFANA_PASSWORD=""
ELASTIC_PASSWORD=""
KIBANA_PASSWORD=""

# CI/CD 자동 연동 시 PHASE 6 6-0 사전 준비에서 채움 (수동 설정 불필요)
GITLAB_TOKEN=""
SONAR_TOKEN=""
```

## 모드별 작성 차이

### 단일 서버 모드 (single)
- 모든 IP 변수에 동일한 호스트 IP 입력 (예: `127.0.0.1` 또는 서버 단일 IP)
- 단일 호스트 내 포트 충돌 자동 회피: GitLab=8082, Backend=APP_PORT
- PHASE 5 검증/생성 단계가 자동으로 포트 충돌 해결

### 다중 서버 모드 (multi)
- 각 서비스에 별도 IP 입력
- 모든 서비스가 표준 포트 사용 (Jenkins:8080, GitLab:80, Backend:APP_PORT)
- 서버별로 install-{service}.sh를 해당 서버에서 개별 실행

### Kubernetes 모드 (k8s)
- 현재 버전 미지원 — Compose 산출물만 생성하고 K8s manifest는 생성 안 함
- 향후 helm chart로 확장 예정

## 검증 (PHASE 5 검증/생성 단계가 자동 수행)

PHASE 5 검증/생성 단계는 실행 시 다음을 검증합니다:
- 모든 필수 변수가 정의되어 있는지
- 어떤 변수에도 `{...}` 패턴이 남아있지 않은지
- IP 변수가 유효한 IPv4 형식인지
- COMPOSE_MODE 값이 single|multi|k8s 중 하나인지
- **PROJECT_NAME 형식**: 영문 소문자로 시작, 영문소문자/숫자/하이픈, 3~32자
- 비어있어야 할 비밀번호 외에는 빈 값이 없는지

검증 실패 시 어떤 변수가 문제인지 명확히 출력하고 종료합니다.

## 자동 계산 변수 (사용자 입력 불필요)

PHASE 5 검증/생성 단계가 입력값을 기반으로 자동 산출해 `config.env`에 기록합니다:

| 변수 | 계산 기준 |
|------|----------|
| `HOST_PORT_GITLAB` | `single` 모드 = 8082, `multi` 모드 = 80 |
| `HOST_PORT_BACKEND` | 단일+APP_PORT=8080이면 8083, 그 외 APP_PORT |
| `HOST_PORT_LOKI` | 단일+ADMIN_PORT=3100+LOG_STACK=loki이면 3110, 그 외 3100 |
| `HOST_PORT_ADMIN` | 일반적으로 ADMIN_PORT 그대로 |
| `HOST_PORT_BASTION_SSH` | 단일+SSH_VIA_BASTION=y이면 2222, 그 외 22 |
| `NEXUS_REGISTRY` | 단일 모드 = `127.0.0.1:5000`, 다중 모드 = `${NEXUS_IP}:5000` (lessons §3-3) |

이 변수들은 모든 compose 템플릿과 Jenkinsfile에서 `${HOST_PORT_*}` / `${NEXUS_REGISTRY}` 형태로 참조됩니다.
