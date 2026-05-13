# devenv-app — PHASE 실행 피드북

PHASE 0~7 대화 스크립트, 검증 절차, 오류 대응, 운영 함정을 모읍니다. 에이전트는 **현재 PHASE**에 해당하는 절만 읽습니다.

## 목차 (PHASE)

에디터에서 `PHASE n` 또는 아래 표의 키워드로 검색해 이동합니다.

| PHASE | 주제 |
|------|------|
| 0 | 프리셋 확인 |
| 1 | 사전 검증 · core · Level 2 감지 |
| 2 | 설치 방식 선택 |
| 3 | 환경 정보 수집(상세) |
| 4 | 구성 검토 |
| 5 | DB · placeholder |
| 6 | 샘플 앱 · GitLab · Jenkins · strict 파이프라인 |
| 7 | 완료 요약 · preset 저장 |
| — | 오류 처리 |
| — | 운영 주의사항 / 함정 |

## PHASE 0: 프리셋 확인

**진입 조건**: 스킬 시작 시 가장 먼저 실행합니다.
**완료 조건**: 사용자 응답을 받은 후 → "1" 선택 시 PHASE 4로, "2" 선택 또는 preset 없음 시 PHASE 1로 이동합니다.

`${DEVENV_HOME}/preset.json`의 `app` 섹션 존재 여부를 확인합니다 (위치 규칙은 [`../SKILL.md`](../SKILL.md)의 **preset.json 공유 메커니즘** 절).

섹션이 존재하면 다음 메시지를 출력하고 사용자 응답을 기다리세요:

> 이전 설정이 있습니다.
>   백엔드: Spring Boot 3.x  |  프론트: React + Vite  |  DB: MySQL 8.0
>   브랜치 전략: GitFlow      |  샘플 앱: 완전 구현
>
> 1. 이전 설정 그대로 사용
> 2. 처음부터 다시 설정

- "1" 응답 → PHASE 4(구성 검토)로 바로 이동
- "2" 응답 또는 preset 없음 → PHASE 1로 이동

---

## PHASE 1: 사전 검증 (devenv-core 확인 + Level 2 스킬 감지)

**진입 조건**: PHASE 0에서 "2" 선택 또는 preset.json에 `app` 섹션이 없을 때 실행합니다.
**완료 조건**: 모든 검증 통과 후 자동으로 PHASE 2로 이동합니다. 검증 실패 시 중단합니다.

### 1-0. 권한 계정 확인 (필수)

PHASE 1 시작 시 먼저 아래 질문을 수행하고 응답을 기다립니다.

> 설치를 수행할 Linux 계정을 확인합니다.
>   1. 현재 계정으로 진행 (sudo 가능)
>   2. root로 전환 후 진행
>
> 계정명(예: ubuntu/root)을 입력해 주세요.

검증 명령(예시):

```bash
whoami
id
sudo -n true >/dev/null 2>&1 || echo "SUDO_PASSWORD_REQUIRED"
```

`sudo -n true` 실패 + root 아님이면 중단하고 계정 전환을 안내합니다.
비밀번호는 preset/config/log에 저장하지 않습니다.

### 1-1. devenv-core 설치 확인

다음 항목을 순서대로 확인하고, 하나라도 실패하면 즉시 중단합니다.

| 확인 항목 | 확인 방법 | 실패 시 조치 |
|---|---|---|
| GitLab 응답 | `curl -s http://<IP>/users/sign_in` | 아래 안내 메시지 출력 후 중단 |
| Jenkins 응답 | `curl -s http://<IP>:8080/login` | 동일 |
| Nexus 응답 | `curl -s http://<IP>:8081/service/rest/v1/status` | 동일 |
| Docker 소켓 | `docker info` | 동일 |

devenv-core 미설치 감지 시 다음 메시지를 출력하고 진행을 멈추세요:

> devenv-core가 설치되어 있지 않습니다.
> devenv-app은 devenv-core 이후에 실행해야 합니다.
>
>   실행 순서:
>   1단계: devenv-core  (GitLab, Jenkins, Nexus, Docker)
>   2단계: devenv-security, devenv-observe  (선택)
>   3단계: devenv-app  (지금 이 스킬)
>
> "devenv-core 시작"이라고 입력하면 바로 이동합니다.

### 1-2. Level 2 스킬 감지

devenv-core 확인 통과 후 자동으로 Level 2 스킬을 감지합니다.
감지 결과는 PHASE 6에서 샘플 앱 생성 시 자동 반영됩니다. 사용자 응답 불필요.

**devenv-security 감지 방법**:
- SonarQube 컨테이너 실행 여부: `docker ps --filter name=sonarqube`
- Trivy 이미지 존재 여부: `docker images aquasec/trivy`
- preset.json `security` 섹션 존재 여부

감지 시 자동 포함 항목:
```
- sonar-project.properties  (프로젝트 루트)
- Jenkinsfile: SonarQube Quality Gate stage 추가 (`waitForQualityGate abortPipeline: true` 강제)
- Jenkinsfile: Trivy 이미지 스캔 stage 추가
```

**devenv-observe 감지 방법**:
- Prometheus 컨테이너 실행 여부: `docker ps --filter name=prometheus`
- Grafana 컨테이너 실행 여부: `docker ps --filter name=grafana`
- preset.json `observe` 섹션 존재 여부

감지 시 자동 포함 항목:
```
- 백엔드: /metrics 엔드포인트 (Spring Boot Actuator / FastAPI /metrics / Express prom-client)
- 백엔드: Promtail 호환 구조화 로그 포맷 설정
- 백엔드: APM 에이전트 의존성 추가
    - observe.apm=skywalking  → skywalking-agent 설정
    - observe.apm=pinpoint    → pinpoint-agent 설정
    - observe.apm=elasticapm  → elastic-apm-agent 의존성
```

### 1-3. 기존 서비스 / 자원 상태 확인

이미 설치된 앱 서비스 + 외부 자원(GitLab repo, Jenkins 잡)을 확인해 처리 방향을 결정합니다.

**컨테이너 상태**:

| 상태 | 처리 |
|---|---|
| 미설치 | 신규 설치 대상으로 표시 |
| 설치 + 정상 응답 | 스킵 (✅ 기존 유지) |
| 설치 + 비정상 응답 | 오류 로그 수집 → 원인 분석 → 자동 재시작 시도 → 실패 시 재설치 (🔧) |

**외부 자원 상태** (PROJECT_NAME 기준 GitLab/Jenkins 조회):

이 단계의 API 호출은 devenv-core가 발급해 preset.json에 저장한 자격증명(`core.gitlabToken`, `core.jenkinsAdminPassword`)을 **읽기 전용**으로 사용합니다. 토큰의 검증/재발급은 PHASE 6 6-0(사전 준비)에서 수행하므로, 여기서 401/403이 발생해도 즉시 중단하지 않고 "외부 자원 미확인" 상태로 표시한 뒤 PHASE 6에서 토큰 갱신 후 재확인합니다.

| 자원 | 확인 방법 | 처리 |
|---|---|---|
| GitLab 그룹 `{project}` | `GET /api/v4/groups/{project}` | 존재 시 그대로 사용 |
| GitLab repo `{project}/{name}` | `GET /api/v4/projects/{id}` + commit count | 미존재/빈 repo는 신규 처리, 커밋 있으면 PHASE 6 6-2에서 사용자 응답 |
| Jenkins 잡 `{project}-{name}` | `GET /job/{name}/api/json` | 존재 시 JCasC 재적용으로 동기화 (덮어쓰기) |

**preset.json 진행 상태 확인** (이전 실행 부분 실패 감지):

`app.phaseProgress`가 존재하고 모든 항목이 완료(✅)가 아니면 다음 메시지를 출력하고 사용자 응답을 기다리세요:

> 이전 실행이 PHASE [N]에서 부분 완료 상태입니다.
>   GitLab push:  backend ✅ / frontend ✅ / admin ❌
>   Jenkins 잡:   backend ✅ / frontend ⏭ / admin ⏭
>
> 1. 미완료 항목만 이어서 진행
> 2. 처음부터 재실행 (PHASE 0으로)
> 3. 작업 중단

**Level 2 감지 불일치** (컨테이너는 없지만 preset에 기록됨)를 감지하면:

> preset에는 [security/observe]가 기록되어 있지만 현재 실행 중이 아닙니다.
> 감지 목록에서 제외할까요? (y/n)

응답을 기록한 후 PHASE 2로 이동합니다.

---

## PHASE 2: 설치 방식 선택

**진입 조건**: PHASE 1 검증이 모두 통과된 후 실행합니다.
**완료 조건**: 사용자 응답을 받은 후 → "1" 선택 시 PHASE 4로, "2" 선택 시 PHASE 3으로 이동합니다.

다음 메시지를 출력하고 사용자 응답을 기다리세요:

> 설치 방식을 선택해주세요.
>
> 1. 빠른 시작  (기본값으로 자동 설치)
>    → Spring Boot 3.x + React + Vite + MySQL 8.0 + GitFlow
>
> 2. 상세 설정  (직접 구성)
>    → 앱 유형·스택·DB·CI/CD 전략을 단계별로 선택

응답을 install_mode에 저장합니다.

- "1" 응답 → 기본값으로 설정 확정 후 PHASE 4로 이동
- "2" 응답 → PHASE 3으로 이동

---

## PHASE 3: 환경 정보 수집 (상세 설정 선택 시)

**진입 조건**: PHASE 2에서 "2. 상세 설정"을 선택했을 때만 실행합니다.
**완료 조건**: B-1 ~ C-2까지 모든 질문에 응답을 받은 후 PHASE 4로 이동합니다.

질문은 [그룹 B]와 [그룹 C]로 나뉩니다. 각 질문은 반드시 순서대로 하나씩 진행하며, 이전 응답을 받은 후에만 다음 질문으로 넘어갑니다.

수집한 응답은 `config.env`에 기록되어 PHASE 5/6의 설치·생성 스크립트가 참조합니다. 변수 전체 명세 및 single/multi 모드별 자동 계산 규칙은 `references/config-env-spec.md` 참조.

### [그룹 B] 앱 유형 + 개발 스택

**B-1. 앱 유형**

**진입 조건**: PHASE 3 시작 시 첫 번째로 실행합니다.
**완료 조건**: 응답을 app_types에 저장 후 B-2로 이동합니다.

다음 메시지를 출력하고 사용자 응답을 기다리세요:

> 앱 유형을 선택해주세요. (복수 선택: 1,3 형태로 입력)
>
> 1. 웹 (Backend API + Frontend SPA)
> 2. API only
> 3. 관리자(Admin) 백오피스
> 4. 모바일 포함 (API only + 앱 빌드 파이프라인)

응답을 app_types에 저장 후 B-2로 이동합니다.

- "3" 포함 시 → Admin 프론트엔드는 Frontend와 동일 프레임워크, 별도 포트·저장소로 배포 예정임을 내부 기록
- "4" 포함 시 → 모바일 빌드 파이프라인(React Native / Flutter) placeholder 생성 예정임을 내부 기록

---

**B-2. 백엔드 프레임워크**

**진입 조건**: B-1 응답을 받은 후 실행합니다.
**완료 조건**: 응답을 backend_framework에 저장 후 B-3으로 이동합니다. placeholder 선택 시 확인 응답을 추가로 받습니다.

다음 메시지를 출력하고 사용자 응답을 기다리세요:

> 백엔드 프레임워크를 선택해주세요.
>
> 1. Java + Spring Boot 3.x   (기본, 완전 구현: auth + JWT + user 관리)
> 2. Node.js + Express         (완전 구현: helmet + JWT + bcrypt)
> 3. Python + FastAPI          (Hello World + DB 연결 확인)
> 4. Go + Gin                  (placeholder 생성)
> 5. Node.js + NestJS          (placeholder 생성)
> 6. Python + Django           (placeholder 생성)

응답을 backend_framework에 저장합니다.

4, 5, 6번 선택 시 다음 메시지를 출력하고 사용자 응답을 기다리세요:

> 선택하신 프레임워크는 현재 기본 구조만 생성됩니다.
> 핵심 파일(Dockerfile, Jenkinsfile, README)은 완전히 생성되며,
> 비즈니스 로직은 TODO 주석으로 표시됩니다.
> 계속 진행하시겠습니까? (y/n)

- "n" 응답 → B-2 질문으로 돌아갑니다.
- "y" 응답 → B-3으로 이동합니다.

---

**B-3. 프론트엔드**

**진입 조건**: B-2 응답을 받은 후 실행합니다. app_types에 "2. API only"만 선택된 경우 이 질문을 건너뜁니다(자동으로 "없음" 처리).
**완료 조건**: 응답을 frontend_framework에 저장 후 B-4로 이동합니다.

다음 메시지를 출력하고 사용자 응답을 기다리세요:

> 프론트엔드를 선택해주세요.
>
> 1. React + Vite              (기본, 완전 구현)
> 2. Next.js                   (SSR, 완전 구현)
> 3. Vue 3 + Vite              (완전 구현)
> 4. Nuxt 3                    (SSR)
> 5. Angular
> 6. 없음 (API only)

응답을 frontend_framework에 저장 후 B-4로 이동합니다.

---

**B-4. Admin 프레임워크**

**진입 조건**: B-3 응답을 받은 후 실행합니다. app_types에 "3. 관리자(Admin)"가 포함된 경우에만 실행합니다. 미포함 시 admin_framework="none"으로 자동 설정 후 B-5로 이동합니다.
**완료 조건**: 응답을 admin_framework에 저장 후 B-5로 이동합니다.

다음 메시지를 출력하고 사용자 응답을 기다리세요:

> 관리자(Admin) 프레임워크를 선택해주세요.
>
> 1. Frontend와 동일       (기본, frontend_framework 그대로 사용)
> 2. React + Vite
> 3. Next.js
> 4. Vue 3 + Vite
> 5. Nuxt 3
> 6. Angular

- "1" 응답 → admin_framework = frontend_framework 값으로 자동 설정
- 그 외 → 선택값을 admin_framework에 저장

Admin은 Frontend와 별도 저장소·별도 컨테이너로 배포됩니다(스타일/기능만 분리). B-5로 이동합니다.

---

**B-5. DB**

**진입 조건**: B-4 응답을 받은 후(또는 Admin 미선택으로 건너뛴 후) 실행합니다.
**완료 조건**: 응답을 db_type에 저장 후 C-1으로 이동합니다.

다음 메시지를 출력하고 사용자 응답을 기다리세요:

> DB를 선택해주세요.
>
> 1. MySQL 8.0       (기본)
> 2. PostgreSQL 15
> 3. MariaDB 10.11
> 4. MongoDB 7.0

응답을 db_type에 저장 후 C-1으로 이동합니다.

---

### [그룹 C] CI/CD 전략

**C-1. Git 브랜치 전략**

**진입 조건**: B-5 응답을 받은 후 실행합니다.
**완료 조건**: 응답을 branch_strategy에 저장 후 C-2로 이동합니다.

다음 메시지를 출력하고 사용자 응답을 기다리세요:

> Git 브랜치 전략을 선택해주세요.
>
> 1. GitFlow       (기본: main / develop / feature / release / hotfix)
> 2. Trunk-based   (main 단일 브랜치, feature flag 방식)
> 3. GitHub Flow   (main + feature 브랜치)

응답을 branch_strategy에 저장합니다.

전략별 Jenkinsfile 분기 로직 (내부 기록):
- GitFlow: `develop` 푸시 → Dev 배포, `main` 푸시 → Prod 배포
- Trunk-based: `main` 푸시 → Dev 자동 배포, 태그 → Prod 배포
- GitHub Flow: PR merge to main → Dev 배포, 수동 트리거 → Prod 배포

C-2로 이동합니다.

---

**C-2. 샘플 앱 기능 수준**

**진입 조건**: C-1 응답을 받은 후 실행합니다.
**완료 조건**: 응답을 sample_app_level에 저장 후 PHASE 4로 이동합니다.

다음 메시지를 출력하고 사용자 응답을 기다리세요:

> 샘플 앱 기능 수준을 선택해주세요.
>
> 1. Hello World + DB 연결 확인   (최소, 빠른 시작)
>    → GET /health, GET /db-check 엔드포인트만 구현
>
> 2. 사용자 로그인 + 관리자 + JWT  (완전 구현)
>    [Frontend] 내 프로필 보기·수정, 비밀번호 변경 / Tailwind CSS 네오브루탈리즘 소프트 / 라우팅(/profile, /users) / 테스트
>    [Admin]    사용자 CRUD, 역할 변경(USER↔ADMIN), 검색·정렬·페이지네이션 / Bootstrap 다크블루 / 테스트
>    [Backend]  Frontend·Admin에서 필요한 REST API 전체 + 테스트
>    → Spring Boot, Express만 완전 지원 (나머지는 skeleton)

응답을 sample_app_level에 저장 후 PHASE 4로 이동합니다.

---

## PHASE 4: 구성 검토

**진입 조건**: PHASE 2에서 "1. 빠른 시작" 선택 후, 또는 PHASE 3의 모든 질문에 응답을 받은 후, 또는 PHASE 0에서 "1. 이전 설정 그대로 사용" 선택 후 실행합니다.
**완료 조건**: 사용자 응답을 받은 후 → "y" 시 PHASE 5로, "n" 시 PHASE 2로, "수정" 시 해당 항목 질문 재실행 후 PHASE 4로 돌아옵니다.

수집된 설정을 표로 출력하고 다음 메시지를 출력한 후 사용자 응답을 기다리세요:

> ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
>  구성 요약
> ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
>  항목              선택값
>  ─────────────────────────────────────────
>  앱 유형           [app_types 값]
>  백엔드            [backend_framework 값]
>  프론트엔드        [frontend_framework 값]
>  Admin             [admin_framework 값 또는 "미사용"]
>  DB                [db_type 값]
>  브랜치 전략       [branch_strategy 값]
>  샘플 앱           [sample_app_level 값]
>  ─────────────────────────────────────────
>  감지된 Level 2 스킬
>    devenv-security  [감지 여부] → [포함 항목]
>    devenv-observe   [감지 여부] → [포함 항목]
> ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
>
> 이 설정으로 진행할까요? (y/n/수정)

- "y" 응답 → PHASE 5로 이동
- "n" 응답 → PHASE 2로 돌아가기
- "수정" 응답 → 변경할 항목 번호를 추가로 물어보고, 해당 질문만 재실행한 후 PHASE 4로 돌아옵니다

---

## PHASE 5: 인프라 준비 (DB + placeholder 컨테이너)

**진입 조건**: PHASE 4에서 "y" 응답을 받은 후 실행합니다.
**완료 조건**: DB 정상 응답 + placeholder 컨테이너 3개 기동 후 자동으로 PHASE 6으로 이동합니다. 포트 충돌 감지 시 사용자 응답을 먼저 받습니다.

### PHASE 5의 책임 범위 (PHASE 6과 명확히 분리)

PHASE 5는 **앱 코드를 빌드하지 않습니다.** 빌드는 PHASE 6에서 Jenkins가 수행합니다.

| 단계 | PHASE 5 책임 | PHASE 6 책임 |
|------|------------|------------|
| DB 컨테이너 | ✅ 가동 + 스키마 생성 | — |
| 호스트 디렉토리/네트워크 | ✅ 생성 | — |
| docker-compose (앱 placeholder) | ✅ Nexus 이미지 pull 시도 → 없으면 비어있는 상태로 대기 | — |
| 앱 소스 코드 | — | ✅ 생성 |
| GitLab 저장소/push | — | ✅ |
| Jenkins 잡/Webhook | — | ✅ |
| 첫 빌드 (이미지 생성) | — | ✅ Jenkinsfile이 수행 |
| 컨테이너 교체 (배포) | — | ✅ Jenkinsfile Deploy stage가 placeholder를 교체 |

placeholder 컨테이너 패턴: docker-compose에 `image: ${NEXUS_REGISTRY}/${PROJECT_NAME}-backend:latest` + `pull_policy: always`로 등록. 첫 실행 시 Nexus에 이미지가 없어 컨테이너는 생성되지만 ImagePullBackOff 상태로 대기. PHASE 6에서 Jenkins가 이미지를 push한 후 `docker-compose pull && up -d`로 교체.

### 포트 충돌 사전 확인

설치 시작 전 포트 사용 여부를 사전 확인합니다. 충돌 감지 시 다음 메시지를 출력하고 사용자 응답을 기다리세요:

> 포트 [충돌 포트]이 이미 사용 중입니다.
> → [대체 포트] 포트로 변경할까요? (y/n)

**이 표는 devenv-app 자체 서비스(DB/Backend/Frontend/Admin)가 다른 무관한 프로세스와 충돌할 때 사용합니다.** Level 2 도구(cAdvisor, Loki, SkyWalking 등)와의 알려진 충돌은 "운영 주의사항 / 포트 충돌 빈발 매핑"에서 별도로 처리됩니다.

| 서비스 | 기본 포트 | 충돌 시 대체 포트 |
|---|---|---|
| DB (MySQL/MariaDB/PG) | 3306 / 5432 | 13306 / 15432 |
| MongoDB | 27017 | 27117 |
| 백엔드 | 8083 | 8084, 8085 |
| 프론트엔드 | 3000 | 3001, 3002 |
| Admin | 3100 | 3101, 3102 |

응답을 받은 후 설치를 진행합니다.

### 병렬 처리 구조

```
[병렬 그룹 A]  DB 컨테이너 가동
               ├─ docker-compose로 DB 컨테이너 실행
               ├─ DB 헬스체크 (최대 60초 대기)
               └─ 초기 스키마/사용자 생성

[순차 후속] DB 응답 확인 후
[병렬 그룹 B]  앱 placeholder 컨테이너 생성 (동시 실행)
               ├─ [backend]   compose up (Nexus 이미지 pull 시도)
               ├─ [frontend]  compose up
               └─ [admin]     compose up

※ 이 단계에서 컨테이너는 ImagePullBackOff/CreateContainerError 상태가 정상.
   PHASE 6 Jenkins 첫 빌드 후 이미지가 Nexus에 push되면 자동 교체됨.
```

### 진행 상태 출력 예시

```
[PHASE 5 진행 중]

  DB (MySQL 8.0)       ██████████  완료 ✅
  Backend placeholder  ██████████  대기 중 (이미지 미존재) ⏳
  Frontend placeholder ██████████  대기 중 (이미지 미존재) ⏳
  Admin placeholder    ██████████  대기 중 (이미지 미존재) ⏳

→ PHASE 6에서 Jenkins가 이미지를 빌드하면 자동 교체됩니다.
```

---

## PHASE 6: 샘플 앱 생성 + CI/CD 연동

**진입 조건**: PHASE 5 인프라 준비 완료 후 실행합니다.
**완료 조건**: 6-0 ~ 6-4까지 모든 단계 통과 후 PHASE 7로 이동합니다. 부분 실패 시 진행 상태를 preset.json에 기록하고 사용자 응답을 받습니다.

진행 단계: **6-0 사전 준비 → 6-1 코드 생성 → 6-2 GitLab push → 6-3 Jenkins 잡 등록 → 6-4 첫 빌드 모니터링**

### 6-0. 사전 준비 (자격증명 / 토큰 수집)

이 단계는 코드 생성 전에 필요한 자격증명을 모두 확보합니다. 누락 시 6-2/6-3에서 401/403으로 실패하므로 먼저 처리합니다.

| 항목 | 출처 | 미존재 시 처리 |
|------|------|---------------|
| `GITLAB_TOKEN` | preset.json `core.gitlabToken` | devenv-core가 발급해 저장한 값을 그대로 읽음. 없으면 Rails 콘솔로 신규 발급 (`references/auto-cicd-setup.md` §1) |
| `NEXUS_PASSWORD` | preset.json `core.nexusPassword` | devenv-core가 저장. 없으면 Nexus 컨테이너의 `/nexus-data/admin.password` 추출 후 변경 |
| `SONAR_TOKEN` | preset.json `security.sonarToken` (devenv-security 감지 시에만) | devenv-security가 저장한 값 우선. 없으면 SonarQube API로 발급 후 preset.json `app.sonarToken`에 기록 (책임 영역 분리) |
| `JENKINS_ADMIN_PASSWORD` | preset.json `core.jenkinsAdminPassword` | devenv-core가 저장 |

자격증명은 **읽기 전용**이 원칙입니다. devenv-app은 자기 영역(`app.sonarToken` 등)만 새로 기록할 수 있고, 다른 스킬의 영역은 변경하지 않습니다.

### 6-1. 샘플 앱 코드 생성

세 저장소(backend / frontend / admin)를 병렬로 생성합니다.

**공통 파일 구조 (모든 프레임워크)**:
```
<project>/
├── Dockerfile
├── Jenkinsfile              ← 브랜치 전략 + Level 2 감지 결과 반영
├── sonar-project.properties ← devenv-security 감지 시에만 생성
├── .gitignore
└── README.md
```

**sample_app_level에 따른 분기**:

| level | backend | frontend | admin |
|---|---|---|---|
| 1 (minimal) | health/db-check만 | Hello + API 호출 1개 | 로그인 폼만(또는 미생성) |
| 2 (full) | Spring Boot/Express는 완전 구현, FastAPI/Go/NestJS/Django는 minimal로 폴백 | 완전 구현 (프로필/사용자 페이지) | 완전 구현 (사용자 CRUD/역할 변경) |

level=2이지만 backend가 완전 구현 미지원 프레임워크(FastAPI/Go/NestJS/Django)인 경우, 해당 backend는 자동으로 minimal로 떨어지고 frontend/admin도 그에 맞춰 minimal 트리로 생성합니다(완전 구현은 backend의 JWT/사용자 API에 의존하므로 함께 다운그레이드).

---

**백엔드 minimal 트리 (level=1 또는 미지원 framework)**

```
backend/
├── (언어별 entry: Application.java / app.js / main.py / main.go)
│   ├── GET /health      → {"status":"UP"}
│   └── GET /db-check    → DB 연결 ping (성공 200 / 실패 500)
├── src/test/java/.../HealthControllerTest.java (최소 3개 케이스)
│   ├── `/health` 200
│   ├── `/db-check` 성공/실패 분기 중 1개
│   └── 인증 필요 엔드포인트 401
├── (의존성 매니페스트: pom.xml / build.gradle / package.json / requirements.txt / go.mod)
└── Dockerfile           ← multi-stage (test → builder → runtime)
```

프레임워크별 포트/헬스체크:

| 프레임워크 | 포트 | 헬스체크 |
|-----------|------|----------|
| spring-boot | 8080 | `/actuator/health` (Actuator 자동) + `/health` (커스텀) |
| express / nestjs | 3000 | `/health` |
| fastapi / django | 8000 | `/health` |
| gin | 8080 | `/health` |

**프론트엔드 minimal 트리 (level=1)**

```
frontend/
├── src/
│   ├── App.tsx                    ← Hello + Backend API 호출 1개
│   └── api/health.ts              ← GET /health 표시
├── nginx.conf                     ← SPA 라우팅 + /api proxy_pass
├── package.json
└── Dockerfile                     ← Node builder → nginx serve, ARG API_BASE_URL 주입
```

**Admin minimal 트리 (level=1, app_types에 admin 포함 시)**

```
admin/
├── src/
│   ├── pages/LoginPage.tsx        ← 로그인 폼 (POST /api/auth/login)
│   ├── App.tsx
│   └── api/client.ts              ← Bearer 토큰 인터셉터
├── package.json
└── Dockerfile                     ← frontend와 동일 구조, 컨테이너명/포트만 다름
```

---

**백엔드 생성 상세 (level=2, 완전 구현)**

토큰 절약을 위해 상세 파일 트리는 본문에서 축약합니다.

- 완전 구현 대상: `spring-boot`, `express`
  - 핵심 API: `auth`, `profile`, `admin-users`, `health`
  - 핵심 테스트: controller/service 단위 **최소 5개 이상**
    - auth 성공/실패
    - profile 인증 필요
    - health/db-check
    - admin 권한 경계(403/401)
- 폴백 대상: `fastapi/go/nestjs/django`
  - minimal 트리로 생성 (`/health`, `/db-check` 중심)
- observe 감지 시:
  - metrics/APM 의존성 자동 삽입
  - 구조화 로그 설정 포함

정확한 파일 구조/샘플 코드는 생성 스크립트 산출물을 단일 기준으로 사용합니다.

**프론트엔드 생성 상세 (level=2 완전 구현)**

상세 트리/스타일 샘플은 반복 토큰이 커서 축약합니다.

- 공통 페이지: `/login`, `/profile`, `/users`
- 공통 기능: JWT 인증, 프로필 수정, 사용자 목록 조회
- 프레임워크 치환:
  - `react-vite/nextjs/vue-vite/nuxt/angular` 중 선택 시 디렉토리 관용만 치환
  - API 흐름/라우팅/테스트 기준은 동일 유지
- 테스트 기본: 컴포넌트 + 페이지 단위 스모크
- 최소 테스트 수: **3개 이상**
  - App 라우팅/로그인 진입
  - ProtectedRoute 인증 분기
  - NavBar 로그인/로그아웃 UI 분기

---

**Admin 생성 상세 (level=2 완전 구현)**

- 핵심 기능만 유지:
  - 사용자 CRUD
  - 역할 변경(USER/ADMIN)
  - 검색/정렬/페이지네이션
- 프레임워크 치환 규칙은 frontend와 동일
- 테스트는 사용자 관리 흐름 중심으로 최소 세트 유지
- 최소 테스트 수: **3개 이상**
  - 로그인 진입
  - ProtectedRoute 권한(USER 차단/ADMIN 통과)
  - NavBar role badge/로그아웃 표시

---

**Jenkinsfile 생성 규칙**

- 기본 stage:
  - `Checkout`, `Test`, `SonarQube Analysis`, `Quality Gate`, `Dependency Check`, `Docker Build`, `Trivy Scan`, `Push`, `Deploy`, `Smoke`, `Notify`
- Test stage 필수 규칙:
  - backend: Docker Maven 컨테이너로 `mvn -B -ntp clean test`
  - frontend/admin: Docker Node 컨테이너로 `npm install --no-audit --no-fund && npm run test`
  - 테스트 실패 시 즉시 파이프라인 중단 (continue 금지)
- security 감지 시:
  - `SonarQube Analysis`, `Trivy Scan` 추가
  - `Quality Gate`는 반드시 `waitForQualityGate abortPipeline: true` 사용
  - Trivy는 `--exit-code 1 --severity HIGH,CRITICAL` 기준으로 실패 시 즉시 중단
  - Dependency-Check 결과가 `FAIL/UNSTABLE`이면 다음 stage로 진행하지 않음
  - `|| true`, `--exit-code 0` 패턴은 금지
- observe 감지 시:
  - metrics/APM 관련 의존성 및 endpoint 자동 포함

상세 Jenkinsfile/프로퍼티 샘플은 토큰 절약을 위해 본문에서 생략하고, 생성 산출물과 references를 단일 기준으로 사용합니다.

### 6-2. GitLab 저장소 생성 + 푸시

3-repo 분리 구조(`{project}/backend`, `{project}/frontend`, `{project}/admin`)로 그룹 + 3개 프로젝트를 생성하고 각각 push합니다. 세 저장소는 병렬 처리.

**idempotency (재실행 시 처리)**:

각 자원에 대해 GitLab API로 존재 여부를 먼저 확인하고 분기합니다.

| 자원 | 미존재 | 존재 + 비어있음 | 존재 + 커밋 있음 |
|------|-------|--------------|----------------|
| 그룹 `{project}` | 신규 생성 | 그대로 사용 | 그대로 사용 |
| repo `{project}/{name}` | 신규 생성 | 그대로 사용 + push | 사용자 응답 대기 |

repo에 이미 커밋이 있는 경우 다음 메시지를 출력하고 사용자 응답을 기다리세요:

> GitLab 저장소 `{project}/{name}`에 이미 커밋이 있습니다.
> 1. 그대로 두기 (push 스킵)
> 2. 백업 브랜치 생성 후 병합 진행 (권장)
> 3. 작업 중단

세 저장소 각각 응답을 받아 처리하고, 결과를 preset.json `app.phaseProgress.gitlab[<repo>]`에 기록합니다.

옵션 2 처리 규칙:
- 원격 기본 브랜치의 현재 HEAD를 `backup/pre-devenv-app-<timestamp>`로 먼저 보존
- 이후 병합/치환을 수행하고 일반 push(비강제) 우선
- non-fast-forward가 지속되면 사용자에게 수동 병합 가이드를 제시하고 중단

구체 절차(Rails 콘솔 토큰 발급, root 계정 폴백, GitLab API 호출 패턴, NTFS chmod 우회)는 `references/auto-cicd-setup.md` §1~4 참조. PAT가 401을 반환하면 root 비밀번호 Basic Auth로 폴백 (`references/troubleshooting.md` §2 참조).

### 6-3. Jenkins 파이프라인 잡 생성

JCasC로 3개 `pipelineJob`을 자동 등록하고 GitLab Webhook 3개를 등록합니다.

- 잡 URL: `http://<jenkins-ip>:8080/job/<project>-{backend|frontend|admin}/`
- SCM URL은 컨테이너명(`http://gitlab-${PROJECT_NAME}:80/...`) 사용 — 호스트 IP는 라우팅 불가
- Webhook URL의 잡명은 JCasC 등록 잡명과 정확히 일치 (`…/project/${PROJECT_NAME}-${repo}`)

**idempotency (재실행 시 처리)**:

| 자원 | 미존재 | 존재 |
|------|-------|------|
| Jenkins 잡 `{project}-{name}` | JCasC 적용 후 신규 생성 | JCasC 재적용으로 정의 동기화 (덮어쓰기, 빌드 이력은 보존) |
| Webhook | 신규 등록 | URL 일치 시 스킵, 불일치 시 갱신 |

JCasC yaml 구조, credentials 등록, Webhook API 호출은 `references/auto-cicd-setup.md` §6~8 참조.

### 6-4. 첫 빌드 트리거 + 모니터링

3개 잡을 동시 트리거하고 결과를 한 루프에서 폴링합니다 (10분 타임아웃).

- 트리거 직후 `Location:` 헤더의 queueItem URL을 받아 build number를 추적 (`references/lessons-learned.md` §8-1)
- Webhook이 자동 트리거하는 빌드와 수동 트리거가 충돌하지 않도록, 6-3에서 Webhook 등록을 마친 후 **수동 build API 호출은 생략**하고 **6-2의 push 자체가 첫 빌드를 트리거**하도록 정렬
- 각 잡 결과를 preset.json `app.phaseProgress.builds[<repo>]`에 SUCCESS/FAILURE/TIMEOUT로 기록

폴링 로직은 `references/auto-cicd-setup.md` §9 참조.

추가 검증 게이트:
- Build Gate: Jenkins result=SUCCESS
- Security Gate: Sonar Quality Gate=PASS + Trivy HIGH/CRITICAL=0 + Dependency-Check 실패 없음
- Artifact Gate: Nexus 이미지 태그 조회 성공
- Deploy Gate: 대상 컨테이너 `Up` + restart loop 없음
- Smoke Gate: backend `/health`, frontend `/`, admin `/`(선택 시) 200

게이트 실패 시 해당 repo만 실패로 기록하고, 다른 repo는 계속 진행합니다.

### 부분 실패 처리

6-2 / 6-3 / 6-4 중 하나라도 일부 자원에서 실패하면 PHASE 7로 진행하지 않고 다음 메시지를 출력합니다:

> [부분 실패]
>   GitLab push:   backend ✅ / frontend ✅ / admin ❌
>   Jenkins 잡:    backend ✅ / frontend ✅ / admin ⏭ (skip)
>   첫 빌드:        backend ✅ / frontend ❌ / admin ⏭
>
> 1. 실패 항목만 재시도 (preset.json의 진행 상태에서 이어가기)
> 2. 모든 항목 처음부터 재실행
> 3. 현재 상태 그대로 PHASE 7로 진행 (수동 복구 예정)

응답을 받아 처리한 후 다시 6-2부터 재진입하거나 PHASE 7로 이동합니다. 진행 상태는 기본적으로 `preset.json app.phaseProgress`를 사용하고, 전역 계약의 런타임 섹션(`preset.json runtime.*`)에도 동기화해 다음 실행의 PHASE 0/1에서 미완료 항목을 감지합니다.

#### 부분 실패 재시도 표준 응답 문구

부분 실패 시 사용자 안내는 아래 고정 문구를 사용합니다(재현성 확보 목적).

```text
[부분 실패 감지]
실패 범위: <repo>/<stage>
원인 요약: <한 줄>
권장 조치: 1) 실패 항목만 재시도  2) 전체 재실행  3) PHASE 7 진행
입력 형식: 1 | 2 | 3
```

선택지 후속 동작:
- `1`: 실패 repo만 재시도 (`phaseProgress` 기준)
- `2`: PHASE 6 6-0부터 전체 재실행
- `3`: 현재 상태를 `⚠️ 주의`로 요약해 PHASE 7 진행

#### PHASE 6 실행 예시 템플릿

정상 케이스:

```text
[PHASE 6 실행]
repo=backend/frontend/admin
gate.build=PASS
gate.artifact=PASS
gate.deploy=PASS
gate.smoke=PASS
result=SUCCESS(all)
next=PHASE 7
```

부분 실패 케이스:

```text
[PHASE 6 실행]
backend: PASS/PASS/PASS/PASS  => SUCCESS
frontend: PASS/PASS/PASS/FAIL => FAILURE(smoke)
admin: SKIP                   => NOT_RUN
retry-plan=frontend-only
next=사용자 선택 대기(1|2|3)
```

---

## PHASE 7: 완료 요약 + 프리셋 저장

**진입 조건**: PHASE 6의 모든 작업이 완료된 후 실행합니다.
**완료 조건**: 요약 출력 및 preset.json 저장 후 스킬을 종료합니다.

### 완료 요약 출력

다음 형식으로 결과를 출력합니다:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 devenv-app 설치 완료
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 서비스       상태       URL / 위치
 ──────────────────────────────────────────────
 DB          [상태]    [IP]:[PORT]  ([DB 유형])
 Backend     [상태]    http://[IP]:[PORT]/health
 Frontend    [상태]    http://[IP]:[PORT]
 Admin       [상태]    http://[IP]:[PORT]
 ──────────────────────────────────────────────
 GitLab 저장소
   http://[gitlab-ip]/<project>/backend
   http://[gitlab-ip]/<project>/frontend
   http://[gitlab-ip]/<project>/admin
 ──────────────────────────────────────────────
 Jenkins 파이프라인
   http://[jenkins-ip]:8080/job/<project>-backend/
   http://[jenkins-ip]:8080/job/<project>-frontend/
   http://[jenkins-ip]:8080/job/<project>-admin/
 ──────────────────────────────────────────────
 Level 2 연동 현황
   SonarQube    [감지 여부] [결과]
   Trivy        [감지 여부] [결과]
   Prometheus   [감지 여부] [결과]
   APM          [감지 여부] [결과]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

다음 단계:
  1. 백엔드 첫 빌드 결과 확인: http://[jenkins-ip]:8080/job/<project>-backend/
  2. 프론트엔드 접속 확인:      http://[frontend-ip]:[PORT]
  3. API 헬스체크:              curl http://[backend-ip]:[PORT]/health
```

상태 표시 기준:
- `✅ 신규` : 이번 실행에서 새로 설치됨
- `✅ 기존` : 이미 정상 실행 중이었으므로 스킵됨
- `🔧 복구` : 비정상 상태에서 자동 복구됨
- `⚠️ 주의` : 설치는 완료됐으나 확인 필요한 항목 있음

### preset.json 저장

`${DEVENV_HOME}/preset.json`의 `app` 섹션을 갱신합니다(다른 섹션 `core`/`security`/`observe`는 절대 수정하지 않습니다). 저장 직후 `chmod 600` 적용.

```json
{
  "app": {
    "savedAt": "2026-04-28T09:00:00+09:00",
    "appType": ["web", "admin"],
    "backend": "spring-boot",
    "frontend": "react-vite",
    "admin": "react-vite",
    "db": "mysql-8.0",
    "branchStrategy": "gitflow",
    "sampleApp": "full",
    "ports": {
      "db": 3306,
      "backend": 8083,
      "frontend": 3000,
      "admin": 3100
    },
    "detectedSkills": {
      "security": true,
      "observe": true,
      "observeApm": "skywalking"
    },
    "sonarToken": "<masked>",
    "phaseProgress": {
      "gitlab":  { "backend": "ok", "frontend": "ok", "admin": "ok" },
      "jenkins": { "backend": "ok", "frontend": "ok", "admin": "ok" },
      "builds":  { "backend": "SUCCESS", "frontend": "SUCCESS", "admin": "SUCCESS" }
    }
  }
}
```

---

## 오류 처리

| 오류 상황 | 감지 방법 | 대응 |
|---|---|---|
| devenv-core 미설치 | GitLab/Jenkins 응답 없음 | "먼저 devenv-core를 실행해주세요" 안내 후 즉시 중단 |
| DB 포트 충돌 | `ss -tlnp` 또는 `netstat` | 대체 포트 자동 제안 후 사용자 응답 대기 (예: 3306 → 13306) |
| DB 헬스체크 타임아웃 | 60초 이내 응답 없음 | 로그 수집 → 원인 출력 → 재시작 1회 시도 |
| GitLab API 인증 실패 | HTTP 401 응답 | preset.json의 토큰 확인 요청 안내 |
| Jenkins 잡 생성 실패 | HTTP 4xx/5xx | 수동 생성 가이드 출력 (Jenkinsfile 경로 포함) |
| 백엔드 빌드 실패 | 컨테이너 exit code != 0 | 빌드 로그 마지막 50줄 출력 + 원인 분석 |
| placeholder 프레임워크 선택 | B-2에서 4번 이상 선택 | 진행 전 안내 메시지 출력 후 사용자 응답 대기 (y/n) |
| Level 2 감지 불일치 | 컨테이너는 없지만 preset에 기록됨 | "preset에는 있지만 실행 중이 아닙니다. 감지 제외할까요?" 사용자 응답 대기 |

---

## 운영 주의사항 / 알려진 함정

실제 배포에서 검증된 비자명한 함정들. 자세한 사례·코드·재현 절차는 `references/lessons-learned.md`, `references/troubleshooting.md` 참조.

### OS별 적용 범위

PHASE 1에서 호스트 OS를 감지하고(`uname -s` / `$OSTYPE`), 다음 표대로 항목을 적용/스킵합니다.

| 항목 | Linux 호스트 (Ubuntu/RHEL) | Windows + WSL | macOS |
|------|---------------------------|---------------|-------|
| MSYS 경로 자동 변환 | ⏭ 스킵 | ✅ 적용 (`MSYS_NO_PATHCONV=1`) | ⏭ 스킵 |
| PowerShell BOM 함정 | ⏭ 스킵 | ✅ 적용 | ⏭ 스킵 |
| NTFS chmod 우회 | ⏭ 스킵 | ✅ 적용 (`/mnt/c` 사용 시) | ⏭ 스킵 |
| systemd-run 백그라운드 패턴 | ✅ systemd 있는 배포판만 | ✅ 적용 | ⏭ launchd 사용 (별도 가이드 없음) |
| Nexus DockerToken / 127.0.0.1 hardcode | ✅ 모든 OS 공통 | ✅ | ✅ |
| insecure-registries 등록 | ✅ `/etc/docker/daemon.json` | ✅ Docker Desktop UI | ✅ Docker Desktop UI |
| Spring Boot 3.2 + Prometheus 406 | ✅ 모든 OS 공통 | ✅ | ✅ |

Linux/macOS 호스트에서는 Windows/WSL 전용 항목을 명시적으로 스킵하고 진행 로그에 `[OS=linux] MSYS 항목 스킵` 같이 출력합니다.

### Windows / WSL 환경

- **MSYS 경로 자동 변환**: Git Bash에서 `wsl bash /mnt/c/...sh` 호출 시 첫 인자가 `/`로 시작하면 Windows 경로로 자동 변환됨. `MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -- bash ...` 패턴 사용.
- **PowerShell BOM 함정**: `Out-File -Encoding utf8`은 UTF-8 BOM(`\xEF\xBB\xBF`)을 삽입해 Jenkinsfile 파싱 실패. `[System.IO.File]::WriteAllText(path, content, [System.Text.UTF8Encoding]::new($false))` 사용.
- **NTFS 마운트(`/mnt/c`)에서 git chmod 실패**: `core.fileMode=false` + `core.autocrlf=false` 미리 설정하거나 WSL 네이티브 경로(`/tmp`)에서 git 작업.
- **WSL 백그라운드 프로세스 죽음**: `wsl -- bash -lc "(... &)"` 패턴은 wsl 명령 종료 시 함께 종료. 장시간 작업은 `systemd-run --user --unit=...` 으로 transient unit 가동.

### Nexus Docker Registry (3가지 모두 충족 필요)

- **docker-hosted 저장소가 생성되어야 5000 포트 listen**: Nexus는 docker repo 정의 후에야 해당 포트 listen. `writePolicy: ALLOW` (NOT `ALLOW_ONCE` — `latest` 태그 덮어쓰기 필수).
- **DockerToken realm 활성화**: 기본 realm은 Basic auth만 — Docker registry는 Bearer Token. `["NexusAuthenticatingRealm","DockerToken"]` PUT.
- **푸시/pull 주소는 항상 `127.0.0.1:5000` hardcode**: Jenkins 안의 docker CLI는 호스트 daemon에 명령 전달, 호스트는 `nexus:5000` hostname 모름. `insecure-registries`에도 `127.0.0.1:5000` 등록.
- **Nexus 3.61+ EULA 자동 수락 필수**: 미동의 시 모든 API 차단. `POST /service/rest/v1/system/eula`.

### GitLab

- **main branch는 기본 protected → force push 거부**: clone → 파일 교체 → 일반 push (fast-forward) 패턴 사용.
- **GitLab 18.x PAT 401**: feature flag (`personal_access_tokens`, `api_personal_access_token_auth`, `pat_authentication`)가 비활성화된 채 배포되는 경우 — Rails 콘솔에서 활성화 또는 root 비밀번호 Basic Auth 폴백.
- **Webhook "URL is blocked"**: GitLab Admin → Settings → Network → "Allow requests to the local network from web hooks" 활성화.
- **GitLab 헬스체크는 `/users/sign_in`으로**: `/-/health`는 마이그레이션 중에도 200 반환해 신뢰 불가.

### Jenkins

- **Jenkins agent에 빌드 도구 없음**: gradle/npm/mvn/node 어떤 것도 없음 → Jenkinsfile에서 직접 로컬 툴 실행 금지. 테스트/분석은 반드시 Docker 컨테이너(`maven`, `node`, `sonar-scanner`, `trivy`, `dependency-check`)로 실행.
- **CSRF crumb은 cookie 세션과 묶임**: 별도 curl로 crumb만 받고 다른 curl로 build trigger 시 403. `curl -c jar / -b jar`로 cookie jar 공유 필수.
- **Groovy GString credentials 이스케이프**: `sh """..."""` 안에서 `\$NEXUS_PASS`로 이스케이프해야 쉘이 환경변수로 해석 (이스케이프 없으면 Groovy가 빈 문자열로 치환).
- **`--build-arg`에 공백 포함 값 금지**: shell expansion으로 quoting 깨짐. 코드에 hardcode 또는 `.env` 파일 사용.
- **JCasC `pipelineJob` SCM URL은 컨테이너명 사용**: `http://gitlab-${PROJECT_NAME}:80/...` (호스트 IP 사용 시 Jenkins 컨테이너 내부에서 라우팅 불가).
- **Webhook URL의 잡명 정확히 일치**: `…/project/${PROJECT_NAME}-${repo}` 형식이 JCasC 등록 잡명과 일치해야 트리거 동작.

### Docker Build / 배포

- **순차 빌드 기본 (containerd race 회피)**: 같은 base image로 동시 빌드 시 `failed to export layer ... rename ingest` 오류. `backend → frontend → admin` 순차 + 각 잡 완료 대기. `--parallel`은 디버깅 옵션으로만.
- **Trivy `-v .trivyignore` DinD 미동작**: Jenkins 안에서 `${env.WORKSPACE}` 마운트는 호스트 daemon이 호스트 경로를 모름. `--ignore-unfixed`만 사용 (Maven Central 미출시 CVE 자동 억제).
- **insecure-registries 등록 필수**: `/etc/docker/daemon.json`에 `127.0.0.1:5000` 추가 후 docker 재시작.

### 관측성

- **Spring Boot 3.2 + Prometheus 자체 scrape 시 406**: 같은 호스트에서 curl/wget은 200인데 Prometheus만 406. SkyWalking을 default APM으로 권장 (HTTP/DB/GC/heap 자동 수집). 또는 `io.prometheus:simpleclient_servlet`로 `/metrics` 별도 노출 (Actuator 우회).
- **SonarQube Webhook URL은 컨테이너명으로**: `localhost:8080`은 SonarQube 자신을 가리킴. `http://jenkins-${PROJECT_NAME}:8080/sonarqube-webhook/` 사용.
- **Grafana 대시보드 provisioning**: datasource 자동 등록과 별개. `provisioning/dashboards/dashboards.yml` provider 정의 + `dashboards/` 마운트 필요.
- **SkyWalking agent volume 패턴**: `01-bootstrap.sh`에서 미리 volume 생성, init 컨테이너가 agent jar 복사, backend는 read-only 마운트. `--hostname` / `--network-alias` 누락 시 Prometheus가 hostname 접근 불가.

### 단일/다중 서버 모드별 자동 계산 변수

| 변수 | single 모드 | multi 모드 |
|------|------------|-----------|
| `HOST_PORT_GITLAB` | 8082 (호스트 80 충돌) | 80 |
| `HOST_PORT_BACKEND` | 8083 (APP_PORT=8080 시 Jenkins 충돌) | APP_PORT |
| `HOST_PORT_LOKI` | 3110 (Admin 3100 충돌) | 3100 |
| `HOST_PORT_BASTION_SSH` | 2222 | 22 |
| `NEXUS_REGISTRY` | `127.0.0.1:5000` | `${NEXUS_IP}:5000` |

### 포트 충돌 빈발 매핑

이 표는 **Level 1/2 도구 사이의 알려진 충돌**을 사전에 회피하기 위한 권장 변경 내역입니다 (devenv-app 자체 인스턴스 충돌은 PHASE 5의 별도 표 참조).

| 서비스 (기본 포트) | 충돌 상대 | 권장 변경 |
|---|---|---|
| cAdvisor (8080) | Jenkins (8080) | **8083** |
| SkyWalking UI (8080) | Jenkins (8080) | **8888** |
| Loki (3100) | Admin (3100) | **3110** (Loki를 변경, Admin 유지) |
| GitLab (80) | 호스트 80 | **8082** |

Admin과 Loki가 둘 다 3100을 쓰는 경우 **Loki를 3110으로 옮깁니다** (Admin은 사용자가 PHASE 3에서 정의한 ADMIN_PORT를 그대로 유지). devenv-observe가 이미 설치된 상태라면 PHASE 1-2의 Level 2 감지 직후 충돌 검사를 수행하고 자동 권고합니다.
