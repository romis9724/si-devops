# Devenv Contract (4단계 공통 정책)

## 범위

이 계약은 다음 스킬이 공통으로 따라야 하는 규칙을 정의합니다.

- `devenv-core`
- `devenv-security`
- `devenv-observe`
- `devenv-app`

개별 스킬 문서와 이 계약이 충돌하면, 이 계약을 우선 적용합니다.

**절 번호**는 아래 문서 순서와 일치합니다. 상호 참조 시 `N) 제목` 형식을 사용합니다.

## 1) Preset 및 Runtime 상태

- 단일 기준 파일: `${DEVENV_HOME}/preset.json`
- `DEVENV_HOME` 미설정 시 기본 경로:
  - `~/devenv-${PROJECT_NAME}/preset.json`
- Runtime 상태는 `preset.json` 내부의 아래 키를 사용합니다.
  - `runtime.lastPhase`
  - `runtime.phaseProgress`
  - `runtime.lastError`
- PHASE 재개를 위해 별도 runtime 파일을 사용하지 않습니다.

### 민감값 (preset vs 파일)

- `preset.json`에는 **구조·식별자·포트·엔드포인트**와, 스킬이 정한 경우 **참조 키**(`*_ref`, `*_token_file`, `*_password_file` 등) 위주로 둡니다. 스킬이 **`secrets/*.env`** 등 전용 파일에만 평문 비밀을 두도록 정한 경우(예: `devenv-security`) 해당 스킬 문서를 따릅니다.
- 평문 비밀번호·PAT·API 키를 **로그·에이전트 출력·커밋**에 넣지 않습니다. `config.env` 저장 시에도 동일합니다.
- 비밀을 담는 파일은 **`chmod 600`** 등으로 제한합니다 (스킬별 경로는 각 `SKILL.md`).

## 2) 표준 헬스체크 엔드포인트

- GitLab readiness: `/users/sign_in`
- Jenkins readiness: `/login`
- Nexus readiness: `/service/rest/v1/status`
- Prometheus readiness: `/-/healthy`
- Grafana readiness: `/api/health` (DB 상태 확인 포함)
- Loki readiness: `/ready`
- SonarQube readiness: `/api/system/status` (`UP`)

macOS 호스트: SonarQube용 **`sysctl vm.max_map_count` 변경을 설치 스크립트에서 시도하지 않습니다.** JVM 완화는 스킬별 compose(예: `SONAR_SEARCH_JAVAADDITIONALOPTS=-Dnode.store.allow_mmap=false`)를 따릅니다.

주의:

- GitLab 최종 readiness 판정에 `/-/health`를 사용하지 않습니다.
- 컨테이너 실행 상태만으로 성공 판정하지 않습니다.

## 3) 포트 충돌 정책

- 우선순위:
  1. Core 고정 포트
  2. App 서비스 포트
  3. Observe/Security 보조 포트
- 알려진 충돌 처리:
  - Admin은 `3100` 유지
  - 충돌 시 Loki를 `3110`으로 이동
- 자동 변경된 포트는 반드시 `preset.json`에 저장합니다.

## 4) Retry 및 Backoff 정책

- 일시 장애의 표준 재시도 예산:
  - `maxAttempts=3`
  - `backoff=5s,10s,20s`
- 재시도 허용 범위(일시 장애):
  - network timeout
  - temporary DNS failure
  - service warm-up delay
- 파괴적 복구 동작은 사용자 확인 없이 수행하지 않습니다.

## 5) 파괴적 Docker Compose 옵션 금지 정책

재현성/안전성을 위해 아래 규칙을 전 스킬(core/security/observe/app)에 공통 적용합니다.

- 금지 기본값:
  - `docker compose up` 실행 시 `--remove-orphans`를 기본 사용하지 않습니다.
- 허용 예외:
  - 사용자 명시 승인(대화 내 확인) + 영향 범위 고지 후 1회 실행
  - 서비스별 독립 `project_name`으로 완전히 분리되어 orphan 제거 영향이 검증된 경우
- 권장 기본 패턴:
  - 설치: `docker compose ... up -d`
  - 정리: 명시적 `docker compose ... down -v` 또는 서비스 단위 teardown 스크립트
- 회귀 방지:
  - 생성기/템플릿 검증 스크립트에서 `--remove-orphans` 포함 여부를 실패로 처리합니다.

## 6) 설치 성공 판정 계약 (Harness Gate)

설치 성공을 "컨테이너 실행"이 아닌 "서비스 준비 완료"로 판정합니다.

- 필수 readiness:
  - GitLab: `/users/sign_in`
  - Jenkins: `/login`
  - Nexus: `/service/rest/v1/status`
- 최소 판정 기준:
  - 필수 서비스 readiness HTTP 성공
  - 핵심 포트 응답 확인
  - 실패 시 최근 로그 30~50줄 + 마지막 실패 단계 기록
- 경고 분리:
  - 내부 네트워크 전용 probe 실패는 `WARN(benign)`으로 분리 가능
  - 단, 호스트 접근 경로 probe는 필수 성공 조건으로 유지

## 7) 오류 코드 및 출력 계약

- 오류 코드 네임스페이스:
  - `CORE-EXXX`
  - `SEC-EXXX`
  - `OBS-EXXX`
  - `APP-EXXX`
- 표준 출력 형식:

```text
[CODE] short summary
cause: one line
action: one line
next: retry | skip | abort
```

## 8) 토큰 절약 출력 모드 (기본)

- 기본 응답 스타일은 `compact`입니다.
- `compact` 출력 예산:
  - 진행 상태: 최대 1줄
  - PHASE 결과: 최대 3줄
  - 최종 결과: 최대 5줄
- 출력 항목은 아래만 포함합니다.
  - status
  - blocking reason (필요 시)
  - next action 1개
- 사용자가 상세를 요청하지 않으면 중복 표/로그를 출력하지 않습니다.
- 실패 시 로그는 마지막 30~50줄만 포함합니다(전체 로그 금지).

compact 출력 예시:

```text
[PHASE 3] done | changed=2 | next=PHASE 4 confirm
[OBS-E401] grafana unhealthy | cause=timeout | action=retry 1/3 | next=retry
[DONE] app | core=ok security=ok observe=ok app=ok | next=smoke
```

## 9) 상호작용 모드

- 모든 스킬은 아래 2개 모드를 지원해야 합니다.
  - `interactive`: 질문을 한 번에 하나씩 진행
  - `non-interactive`: preset/default 기반 자동 진행, blocking 상황만 질문
- 기본 모드:
  - 채팅 실행: `interactive`
  - harness/CI 실행: `non-interactive`

## 10) 전역 완료 기준 (Global DoD)

전체 플로우는 아래 조건이 모두 참일 때만 완료로 판정합니다.

- `core=ok`
- `security=ok|skipped`
- `observe=ok|skipped`
- `app=ok|partial-ok`
- `cross-health=ok`

## 11) Cross-Health Gate

Cross-health gate는 아래 항목을 검증합니다.

- service endpoint reachability
- pipeline trigger viability
- image artifact accessibility
- app smoke checks

cross-health 실패 시 최종 상태는 반드시 `partial`이어야 하며, blocking reason을 포함해야 합니다.

**실행 시점(기준)**: 파이프라인 트리거·이미지·앱 스모크까지 포함한 **end-to-end cross-health**는 **`devenv-app` PHASE 6~7**에서 수행하는 것을 기본으로 한다. `devenv-app` 없이 core/security/observe만 설치한 경우에는 해당 스킬의 health 게이트까지만 적용하고, 미설치 항목은 `skipped`로 표기할 수 있다.

## 12) 권한 계정 입력 계약 (sudo / root)

모든 설치 스킬(core/security/observe/app)은 설치 실행 전에 권한 컨텍스트를 먼저 확정해야 합니다.

- 필수 확인 항목(질문 1회):
  - 설치를 수행할 Linux 계정명
  - 해당 계정의 sudo 가능 여부
  - 비대화형 실행 가능 여부 (`sudo -n true` 성공 여부 또는 root 진입)
- 허용 실행 방식:
  - root 셸에서 실행
  - sudo 가능한 계정에서 실행
- 금지:
  - sudo 불가능 계정 상태로 설치 강행
  - sudo 비밀번호를 `preset.json`/`config.env`/로그에 저장
- 실패 처리:
  - 권한 검증 실패 시 즉시 중단(fail fast)
  - 계정 전환 또는 root 재진입 안내 후 재시도

## 13) 인프라/DevOps/Harness 최적화 계약

모든 스킬은 아래 최적화 규칙을 공통 적용합니다.

- idempotency-first:
  - 동일 입력으로 재실행 시 동일 결과를 보장합니다.
  - 이미 정상 상태인 리소스는 재생성하지 않고 `skip(existing-ok)`로 처리합니다.
- non-destructive-first:
  - 데이터/이력 손실 가능 동작(강제 push, 볼륨 삭제, 강제 재생성)은 기본 금지입니다.
  - 사용자 명시 승인 시에만 1회 수행하고 영향 범위를 먼저 고지합니다.
- gate-based execution:
  - 기본 게이트 순서: `preflight -> install -> health -> integration -> smoke`
  - 어느 한 게이트라도 실패하면 다음 게이트로 진행하지 않습니다.
- bounded retries:
  - 재시도는 계약 4절(`3회`, `5s/10s/20s`)을 기본으로 하며 무한 루프를 금지합니다.
  - 재시도 실패 시 즉시 `partial` 또는 `fail`로 승격하고 근거를 남깁니다.
- evidence-first failure report:
  - 실패 출력에는 최소 3개를 포함합니다: `last step`, `last http/code`, `tail logs(30~50)`.
  - 원인 미확정 시 추정으로 단정하지 않고 `unknown-yet` 상태를 명시합니다.
- cross-skill consistency:
  - core/security/observe/app 간 포트, endpoint, preset 키 이름이 충돌하면 본 계약을 단일 기준으로 재정렬합니다.

## 14) 운영 KPI 및 SLO-lite

지속 개선을 위해 스킬 실행 결과를 아래 KPI로 측정합니다.

- install_success_rate: 단일 실행에서 `ok` 또는 `partial-ok`로 끝난 비율
- first_pass_rate: 재시도 없이 최초 시도에서 게이트를 통과한 비율
- mttr_lite: 실패 감지부터 복구(또는 partial 확정)까지 소요 시간
- retry_efficiency: 전체 재실행 대비 부분 재시도 비율
- evidence_completeness: 실패 케이스 중 근거 3종(`step/code/tail`)이 채워진 비율

권장 SLO-lite:

- core/security/observe/app 각 스킬의 `first_pass_rate >= 80%`
- 치명 실패의 `mttr_lite <= 15분` (개발 환경 기준)

## 15) 호스트·OS·셸 (요약)

| 스킬 | 실행 호스트 (문서 기준) |
|------|-------------------------|
| `devenv-core` | **Windows는 WSL2 Ubuntu만**(네이티브 Windows Docker 금지). 네이티브 Linux 지원. |
| `devenv-security` | Linux 권장. macOS 분기는 해당 `SKILL.md`·`references` (예: Sonar mmap). |
| `devenv-observe` | Linux / WSL2 / macOS(Docker Desktop). Promtail·경로 차이는 `references` 따름. |
| `devenv-app` | core 선행 전제와 동일 호스트 정책. |

### 경로·셸 (WSL path mangling 방지)

| 호스트 | 권장 명령 |
|--------|-----------|
| Windows + WSL | `MSYS_NO_PATHCONV=1 wsl.exe -d <distro> -u <user> -- bash -lc '...'` 또는 PowerShell의 `wsl.exe ...` |
| 네이티브 Linux | `bash -lc '...'` |
| macOS | 터미널에서 직접 `bash`/`zsh` + Docker Desktop — MSYS 경로 변환 이슈 없음 |

Git Bash(MSYS) 경유 시 Linux 경로가 Windows 경로로 변환될 수 있으므로, WSL 실행은 위 패턴을 기본으로 합니다.

## 16) 설치 동시성 락 규약

- 설치 시작 시 `${install_dir}/.devenv.lock` 생성
- 락 파일이 있으면 신규 실행은 즉시 중단하고 `abort` 반환
- 정상 종료/에러 종료 모두에서 락 파일 제거를 보장 (`trap`)
- stale lock 강제 제거는 사용자 확인 후 1회만 허용
