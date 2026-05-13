# devenv-app `references/`

`SKILL.md`는 **요약·계약·strict 규약**만 두고, 실행 절차·표·함정은 이 폴더에 둡니다.

**경로 주의**: `troubleshooting.md`·`lessons-learned.md` 속 `bash scripts/...` 는 이 레포 안이 아니라, **`devenv-core` 산출물** 디렉터리 `~/devenv-${PROJECT_NAME}/`(또는 `DEVENV_HOME`) 아래 `scripts/` 를 전제로 한 경우가 많습니다.

## 파일 안내

| 파일 | 용도 |
|------|------|
| [`phase-playbook.md`](phase-playbook.md) | PHASE 0~7 질문·검증·오류·운영 함정(가장 큼). **현재 PHASE만** 읽기 권장. |
| [`harness-and-token-policy.md`](harness-and-token-policy.md) | 게이트·재시도·토큰·DoD·Infra/Dev/DevOps/Harness 4축. |
| [`config-env-spec.md`](config-env-spec.md) | `config.env` 변수·single/multi 포트 규칙. |
| [`auto-cicd-setup.md`](auto-cicd-setup.md) | GitLab/Jenkins·토큰·JCasC·Webhook·빌드 폴링. |
| [`lessons-learned.md`](lessons-learned.md) | 비자명 실패·WSL·Nexus·GitLab·Jenkins 사례. |
| [`troubleshooting.md`](troubleshooting.md) | 증상 → 원인 → 조치 카탈로그. |
| [`optimization-checklist.md`](optimization-checklist.md) | 게이트·재시도·부분 실패 점검. |

## 사람이 확인할 때

1. [`../SKILL.md`](../SKILL.md) 상단 **빠른 탐색** 표로 목적에 맞는 파일을 고릅니다.
2. PHASE별 대화 스크립트는 [`phase-playbook.md`](phase-playbook.md)의 **목차** 표를 보고 `PHASE n`으로 검색합니다.
