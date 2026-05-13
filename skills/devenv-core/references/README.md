# devenv-core `references/`

`SKILL.md`는 계약·포트·PHASE 번호 요약만 두고, 긴 규약·명령 블록은 여기 둡니다.

## 스크립트 위치 (혼동 방지)

| 위치 | 내용 |
|------|------|
| **이 저장소** `devenv-core/scripts/` | `generate-configs.sh`, `verify-generator.sh` 만 존재 |
| **`${DEVENV_HOME}/scripts/`** | `install-*.sh`, `health-check.sh`, `agent-orchestrator.py` 등 — 생성기 산출물 |

## 바로 쓰는 파일

| 파일 | 용도 |
|------|------|
| [`harness-and-commands.md`](harness-and-commands.md) | 하네스 게이트, PHASE 1 권한 확인, 빠른 시작 기본값, `generate-configs` / `agent-orchestrator` / 수동 설치 명령, 출력 템플릿. |

## 설치·운영

| 파일 | 용도 |
|------|------|
| [`prerequisites.md`](prerequisites.md) | 사전 요구 |
| [`wsl-setup.md`](wsl-setup.md) | WSL |
| [`config-env-spec.md`](config-env-spec.md) | 변수·포트 |
| [`health-check-guide.md`](health-check-guide.md) | 헬스 |
| [`post-install-guide.md`](post-install-guide.md) | 설치 후 |
| [`runbook.md`](runbook.md) | 런북 |
| [`backup-restore.md`](backup-restore.md) | 백업 |
| [`cloud-firewall.md`](cloud-firewall.md) | 방화벽 |

## 장애·최적화

| 파일 | 용도 |
|------|------|
| [`quick-troubleshooting.md`](quick-troubleshooting.md) | 빠른 대응 |
| [`troubleshooting.md`](troubleshooting.md) | 전체 |
| [`lessons-learned.md`](lessons-learned.md) | 사례 |
| [`optimization-checklist.md`](optimization-checklist.md) | 점검 |

## 아키텍처·CI/CD 참고

| 파일 | 용도 |
|------|------|
| [`agent-architecture.md`](agent-architecture.md) | 에이전트 |
| [`server-architecture.md`](server-architecture.md) | 서버 구조 |
| [`auto-cicd-setup.md`](auto-cicd-setup.md) | CI/CD |
| [`cicd-pipeline-guide.md`](cicd-pipeline-guide.md) | 파이프라인 |

## 확인 순서

1. [`../SKILL.md`](../SKILL.md) **빠른 탐색**
2. 운영 명령이 필요하면 [`harness-and-commands.md`](harness-and-commands.md)
