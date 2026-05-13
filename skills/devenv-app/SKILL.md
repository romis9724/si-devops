---
name: devenv-app
description: >
  다음 상황에서 반드시 이 스킬을 사용하세요:
  - "앱 배포 환경 구성", "샘플 앱 생성", "백엔드/프론트 스캐폴딩" 언급 시
  - "Spring Boot 설치", "React 프로젝트 구성", "MySQL 설정" 등 앱 스택 관련 요청 시
  - "CI/CD 파이프라인 생성", "GitLab 저장소 생성", "Jenkins 잡 생성" 요청 시
  - "devenv-core 다음에 앱 환경 구성" 또는 "앱 레이어 추가" 요청 시
  - "백엔드 + 프론트 + DB 환경 한 번에 구성" 요청 시
  - devenv-core 설치 완료 후 애플리케이션 인프라를 추가하고 싶을 때
  devenv-core(GitLab, Jenkins, Nexus, Docker)가 설치된 환경 위에 앱 레이어를
  구성합니다. 백엔드·프론트엔드·DB 설치, 샘플 앱 생성, GitLab 저장소 푸시,
  Jenkins 파이프라인 연동까지 자동화합니다. devenv-security/devenv-observe
  설치 여부를 감지해 SonarQube·Trivy·Prometheus·APM 연동을 자동으로 포함합니다.
---

# devenv-app

## 빠른 탐색

| 찾는 내용 | 문서 |
|-----------|------|
| PHASE 0~7 전체 스크립트·검증·오류·함정 | [`references/phase-playbook.md`](references/phase-playbook.md) |
| 게이트·토큰·DoD·4축 프레임워크 | [`references/harness-and-token-policy.md`](references/harness-and-token-policy.md) |
| `config.env` · 포트 · single/multi | [`references/config-env-spec.md`](references/config-env-spec.md) |
| GitLab · Jenkins · Webhook · 토큰 | [`references/auto-cicd-setup.md`](references/auto-cicd-setup.md) |
| 비자명 실패 사례 | [`references/lessons-learned.md`](references/lessons-learned.md) |
| 증상별 카탈로그 | [`references/troubleshooting.md`](references/troubleshooting.md) |
| 게이트·재시도 점검 | [`references/optimization-checklist.md`](references/optimization-checklist.md) |

**계약**: 충돌 시 [`../devenv-common/contracts/devenv-contract.md`](../devenv-common/contracts/devenv-contract.md) 우선.
**안 맞는 경우**: monorepo + Bazel 빌드, Nx workspace, serverless(Lambda 등) 우선 환경.
**구현**: 이 저장소에는 **Markdown만**. 셸 설치 스크립트는 `devenv-core`가 `${DEVENV_HOME}`에 생성한 `scripts/*.sh`를 가리키거나 에이전트가 PHASE에서 직접 수행.

## 동작 방식

devenv-app은 **Level 3** 스킬 — devenv-core(Level 1)가 먼저 설치된 환경에서만 실행. devenv-security/observe(Level 2)는 자동 감지하여 샘플 앱에 Jenkinsfile·`sonar-project.properties`·`/metrics` 등을 자동 포함.

```
PHASE 0 프리셋 확인 → 1 사전 검증 → 2 설치 방식 선택 → 3 환경 정보 수집
PHASE 4 구성 검토 → 5 병렬 설치 (DB+백엔드/프론트/Admin) → 6 샘플 앱 + GitLab/Jenkins 연동 → 7 완료 요약 + 저장
```

질문 문구·검증 표·오류 대응 상세는 [`references/phase-playbook.md`](references/phase-playbook.md).

## preset.json 공유

4개 스킬은 **단일 `${DEVENV_HOME}/preset.json`을 공유**. 각자 자기 섹션(`core`, `security`, `observe`, `app`)만 갱신.

- **위치**: `DEVENV_HOME` 설정 시 그대로, 미설정 시 `~/devenv-${PROJECT_NAME}/preset.json`. 같은 디렉토리에 `config.env` 동거.
- **선행**: devenv-core가 파일을 최초 생성. devenv-app은 `core` 섹션 **읽기만**.
- **민감값**: [`../devenv-common/contracts/devenv-contract.md`](../devenv-common/contracts/devenv-contract.md) 1절 + `devenv-security`의 `secrets/` 규약 따름. `chmod 600`. PHASE 7 저장 직후 권한 확인.
- **부재 시**: PHASE 1-1에서 core 미설치 판정 → 즉시 중단.

전체 변수 명세는 [`references/config-env-spec.md`](references/config-env-spec.md).

## ⚠️ 행동 원칙

1. 한 번에 질문 1개. 응답 후에만 다음 PHASE 진행.
2. 여러 PHASE 한 번에 처리 금지.
3. 설치 시작 전 sudo/root 권한 계정 확인.

## CI/CD 생성물 (strict)

PHASE 6 생성 Jenkinsfile은 **실패를 숨기지 않음**:

- **Test**: backend `mvn ... test`, frontend/admin `npm run test` — 실패 시 즉시 중단 (`continue`, `|| true`, 임의 `--exit-code 0` 금지).
- **Sonar**: `waitForQualityGate abortPipeline: true`.
- **Trivy / Dependency-Check**: 실패 시 다음 stage 진행 금지.

전체 분기·디렉터리 트리는 [`references/phase-playbook.md`](references/phase-playbook.md) PHASE 6, [`references/auto-cicd-setup.md`](references/auto-cicd-setup.md).
