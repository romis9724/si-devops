# devenv-security — 오케스트레이션·계약·도구 개요

SKILL.md에서 분리한 규약입니다. 전역 규약은 `../devenv-common/contracts/devenv-contract.md`를 우선합니다.

## 실행 전제 조건

**devenv-core가 반드시 먼저 설치되어 있어야 합니다.**

devenv-security는 다음 devenv-core 서비스에 의존합니다:

| 의존 서비스 | 이유 |
|------------|------|
| Jenkins | SonarQube Quality Gate stage 자동 등록 |
| GitLab  | 샘플 앱 보안 설정 파일 push (devenv-app 병합 시) |
| Nexus   | Trivy 스캔 대상 Docker 이미지 레지스트리 |
| Docker  | SonarQube / OWASP ZAP 컨테이너 실행 |

devenv-core가 없으면 PHASE 1에서 즉시 실행을 중단하고 안내 메시지를 출력합니다.

---

## 실행 규약 (오케스트레이터 구현용)

이 문서는 설치 스크립트 자체가 아니라 **동작 규약**을 정의합니다. 실제 구현체(`bash`, `python`, `powershell`, 에이전트 워크플로우)는 아래 계약을 지켜야 합니다.

### 1) 프로필 확정 계약 (반드시 1회)

- PHASE 1에서 `RUN_PROFILE`을 반드시 1회만 확정
- 허용 값:
  - `pre-app`  : devenv-app 설치 전 (기본 점검 플로우)
  - `post-app` : devenv-app 설치 후 (기존 프로젝트 병합 가능)
- 이후 PHASE 2~8에서는 재탐지 금지, `RUN_PROFILE` 재사용

### 2) 환경변수 계약 (템플릿 렌더링 공통)

`templates/compose/security.yml.tpl` 렌더링 시 최소 아래 값을 주입:

```bash
PROJECT_NAME=<project>
TIMEZONE=<timezone>
SONAR_ADMIN_PASSWORD=<password>
SONAR_PORT=<default:9000>
ZAP_PORT=<default:8090>
```

- **비밀 출처**: `${DEVENV_HOME}/secrets/security.env`가 있으면 `install-security.sh`·`bootstrap-sonar.sh`·`jenkins-configure.sh`가 **실행 시점에 `source`** 한다. 없으면 환경변수 또는(최후) 스크립트 기본값.
- 포트는 반드시 템플릿 기본값(`9000`, `8090`)과 호환되도록 처리합니다.

### 3) 단계 분기 계약

- `RUN_PROFILE=pre-app`  : PHASE 7 자동 건너뜀
- `RUN_PROFILE=post-app` : PHASE 7 병합 여부 질의 후 진행

### 4) LLM 토큰 최적화 계약

아래 규칙을 기본값으로 사용해 불필요한 대화/출력을 줄이세요.

- **compact 출력 기본값**: `../devenv-common/contracts/devenv-contract.md` 8절을 따른다 (진행 1줄, PHASE 결과 3줄, 최종 5줄).
- **질문 최소화**: 상세 설정 모드가 아니면 추가 질문 없이 기본값 적용
- **요약 우선**: 상태판은 `정상 N / 경고 N / 장애 N` 형태를 기본으로 출력
- **변경점만 출력**: 재실행 시 이전 실행 대비 변경된 항목만 상세 표기
- **긴 예시 축약**: Jenkinsfile/Compose 예시는 전체 재출력하지 않고 삽입/수정 블록만 제시
- **오류 우선 출력**: 성공 로그는 숨기고, 실패 항목에 대해서만 원인/해결 1~3개 제시
- **종료 조건 명확화**: 사용자 입력 대기/자동 진행/종료를 항상 마지막 1줄로 명시
- **stdin 규약**: 파이프 입력이 필요한 경우 `curl ... | python3 <<EOF` 패턴을 금지하고, 변수 캡처 후 `python3 -c` 1줄 패턴을 사용

### 출력 모드 플래그

- `OUTPUT_MODE=compact|verbose` (기본: `compact`)
- `compact`에서는 아래 단일 라인 템플릿을 우선 사용
  - 진행: `[PHASE X] security | status=ok|wait|fail | next=<action>`
  - 오류: `[SEC-EXXX] <summary> | cause=<1-line> | action=<1-line> | next=retry|skip|abort`
  - 완료: `[DONE] security | sonar=ok zap=ok|skip trivy=ok depcheck=ok | next=<action>`

### 5) Agent 운용 계약 (빠른 작업용)

병렬화 가능한 작업은 에이전트를 적극 사용하되, 의존성 있는 작업은 순차 실행합니다.

- **PHASE 1 (검증)**: core 헬스체크, 보안 도구 설치 여부, app 감지 점검을 병렬 실행
- **PHASE 5 (설치)**:
  - 병렬 그룹 A: SonarQube, Trivy
  - 병렬 그룹 B: ZAP, Dependency-Check
  - 각 그룹 완료 후 헬스체크는 순차 실행
- **PHASE 6 (Jenkins 연동)**: 잡별 Jenkinsfile 패치는 병렬 가능, 전역 자격증명/토큰 생성은 순차
- **오류 처리**: 동일 원인 오류는 하나의 대표 해결안으로 묶어 재시도 루프 횟수를 줄임

Agent 출력 규칙:
- 에이전트는 **결론 + 근거 3줄 이내**로 반환
- 성공한 하위 작업의 상세 로그는 숨기고 실패 시에만 확장 출력
- 사용자 응답이 필요한 단계에서는 에이전트를 중지하고 즉시 질문으로 전환

### 6) 표준 실행 커맨드 (빠른 시작)

기본 실행은 아래 1줄을 사용하세요.

```bash
bash scripts/run-security.sh --quiet --changed-only
```

### 7) 보안/운영 최적화 규칙 (신규)

- secret hygiene:
  - 토큰/비밀번호는 로그에 평문 출력하지 않습니다.
  - `preset.json`에는 `*_ref`만 저장하고, 실값은 `${DEVENV_HOME}/secrets/security.env` (`chmod 600`)에만 저장합니다.
- quality gate 전략:
  - 초기 도입 구간은 `warn` 모드 허용, 안정화 후 `strict` 전환을 권장합니다.
  - strict 전환 시점과 예외 저장소를 명시적으로 기록합니다.
- 스캔 비용 최적화:
  - 변경 없는 리포지토리는 `changed-only` 스캔을 기본 적용합니다.
  - 중복 실패 원인은 1개 이슈로 집계해 재시도 루프를 축소합니다.
- 하네스 판정:
  - `scan -> gate -> publish` 순서를 강제하며, gate 실패 시 publish를 차단합니다.

## 담당 서비스

| 도구 | 유형 | 기본 포트 | 역할 |
|------|------|----------|------|
| **SonarQube** | SAST (정적 분석) | 9000 | 소스코드 취약점 + 코드 품질 분석 |
| **OWASP ZAP** | DAST (동적 분석) | 8090 | 실행 중인 앱 대상 웹 취약점 스캔 |
| **Trivy** | 이미지 스캔 | **`docker run aquasec/trivy`** (호스트 CLI 설치 금지) | 컨테이너 이미지 취약점 스캔 |
| **Dependency-Check** | SCA | **Jenkins 플러그인 기본** (Global Tool 이름 **`dependency-check`** 고정; 컨테이너는 명시 선택 시만) | 오픈소스 라이브러리 취약점 (CVE) |
