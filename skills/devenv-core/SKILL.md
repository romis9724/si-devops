---
name: devenv-core
description: >
  개발 인프라 핵심 4개 서버(Bastion, GitLab, Nexus, Jenkins) 설치 스킬.
  이 스킬은 최소 질문/최소 토큰으로 설치를 완료한다.
---

# devenv-core

## 빠른 탐색

| 찾는 내용 | 문서 |
|-----------|------|
| 하네스 게이트·PHASE 1 권한 질문·필수 bash·에이전트 명령 | [`references/harness-and-commands.md`](references/harness-and-commands.md) |
| 사전 요구·WSL | [`references/prerequisites.md`](references/prerequisites.md), [`references/wsl-setup.md`](references/wsl-setup.md) |
| 환경 변수·포트 | [`references/config-env-spec.md`](references/config-env-spec.md) |
| 장애 Lite / Full | [`references/quick-troubleshooting.md`](references/quick-troubleshooting.md), [`references/troubleshooting.md`](references/troubleshooting.md) |
| 런북·체크리스트 | [`references/runbook.md`](references/runbook.md), [`references/optimization-checklist.md`](references/optimization-checklist.md) |
| 에이전트 설계 | [`references/agent-architecture.md`](references/agent-architecture.md) |
| `config.env` / `preset.json` 예시 | [`templates/config.env.example`](templates/config.env.example), [`templates/preset.json.example`](templates/preset.json.example) |
| 통합 진단 (설치 전·후·교차) | `bash scripts/devenv-doctor.sh [auto\|preflight\|health\|smoke\|all]` |
| 자동화 (선택) | `bash scripts/ssl-init.sh` · `bash scripts/enable-cron-backup.sh` · `bash scripts/enable-wsl-autostart.sh` |

**계약**: 충돌 시 [`../devenv-common/contracts/devenv-contract.md`](../devenv-common/contracts/devenv-contract.md) 우선.

## 범위

- 포함: Bastion, GitLab, Nexus, Jenkins
- 제외: app/db(`devenv-app`), security(`devenv-security`), observe(`devenv-observe`)
- **안 맞는 경우**: K8s 우선 환경, GitLab.com SaaS 사용 환경, 24GB 미만 호스트.

## 운영 규칙 (행동·출력·재시도)

- `OUTPUT_MODE=compact` (기본). 한 번에 질문 1개. PHASE 출력 8줄 이내. 성공은 1줄 요약, 실패만 상세.
- 단일 라인 템플릿:
  - 진행: `[PHASE X] status=ok|wait|fail | next=<action>`
  - 오류: `[CORE-EXXX] <summary> | cause=<1-line> | action=<1-line> | next=retry|skip|abort`
  - 완료: `[DONE] core | bastion=ok gitlab=ok nexus=ok jenkins=ok | next=<action>`
- 비파괴 기본: 정상 서비스는 `skip(existing-ok)`. 강제 재생성/삭제/덮어쓰기 금지.
- 게이트: `preflight → install → health → integration → smoke`. 실패 시 즉시 중단 + 근거(step/code/tail) 기록.
- 재시도: 일시 장애 3회(5s/10s/20s). 실패 후 `partial`|`fail` 확정 + 다음 수동 액션 1개만.
- 모드: 대화형은 `interactive`(질문 1개씩), 자동화는 `non-interactive`(preset 우선, 차단 시만 질문).

## 필수 정책

- Windows 직접 Docker 금지, WSL2 Ubuntu만 허용
- 설치 시작 전 sudo/root 권한 컨텍스트 확정
- 비밀번호는 PHASE 5에서 공통 1회 설정 (`ADMIN_SHARED_PASSWORD`)
- single 모드 포트 고정: Bastion SSH `2222` · GitLab HTTP `8082` / SSH `2223` · Jenkins `8080` · Nexus UI/Registry `8081/5000`
- 설치 순서 고정(병렬 금지): `preflight → bootstrap → bastion → gitlab → wait(/users/sign_in) → nexus → wait(status) → jenkins → health-check`

## 동작 흐름 (PHASE 요약)

| PHASE | 내용 |
|-------|------|
| 0 | `preset.json` 재사용 여부 |
| 0.5 | Windows 호스트 검사(WSL2/Ubuntu-22.04/systemd) + 스킬 경로 폴백 미러 |
| 1 | 권한 계정 확인 + 기존 컨테이너 상태 점검 |
| 2 | 빠른 시작 / 상세 설정 선택 |
| 3 | 상세 설정 입력(선택 시) |
| 4 | preflight 항목 점검 |
| 5 | 공통 관리자 비밀번호 1회 설정 |
| 6 | 요약 확인 |
| 7 | `config.env` 작성 → `bash scripts/generate-configs.sh` |
| 8 | `bash scripts/install-all.sh` |
| 9 | `post-install.sh` 있으면 실행 |
| 10 | `bash scripts/health-check.sh` |
| 11 | 완료 요약 + `preset.json` 저장 |

PHASE 1 권한 질문·검증/운영 명령은 [`references/harness-and-commands.md`](references/harness-and-commands.md).

## preset.json (`core` 섹션)

- **역할**: devenv-core가 **최초 생성**하고 `core` 섹션(토큰·비밀·엔드포인트)을 채운다. 이후 다른 스킬이 같은 파일에 섹션을 추가.
- **위치**: `${DEVENV_HOME}/preset.json` (미설정 시 `~/devenv-${PROJECT_NAME}/preset.json`)
- **권한**: 민감 정보 포함 시 `chmod 600`
- **`config.env`**: `generate-configs.sh` 입력으로 GitLab/Jenkins/Nexus 루트 비밀이 들어간다. **커밋·로그·채팅 노출 금지**. `devenv-security`의 `secrets/security.env`와 역할 분리.

## 저장소 구성 (요약)

- **포함**: `scripts/{generate-configs,verify-generator,smoke-cross-service,agent-monitor,bootstrap-skill-mirror}.sh`, `scripts/00-windows-bootstrap.ps1`, `templates/**`, `references/**`
- **미포함**: `install-all.sh`, `health-check.sh`, `agent-orchestrator.py` 등은 `generate-configs.sh` 실행 후 `${DEVENV_HOME}`에 **생성**된다. 명령 예시는 항상 그 디렉터리를 `cd`한 뒤 실행 가정.
