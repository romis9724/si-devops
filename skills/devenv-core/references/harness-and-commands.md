# devenv-core — 하네스 규약·PHASE 1 권한·명령 모음

SKILL.md에서 분리한 운영 참고용입니다. 전역 규약은 `../devenv-common/contracts/devenv-contract.md`를 우선합니다.

PHASE 0~11 대화형 상세가 필요하면 Cursor 에이전트는 동일 저장소의 다른 스킬과 같이 **현재 PHASE** 위주로 이 파일을 부분 로드합니다.

## 인프라/DevOps/Harness 최적화 규칙 (신규)

- 비파괴 기본값:
  - 강제 재생성/강제 삭제/강제 덮어쓰기는 기본 금지
  - 기존 정상 서비스는 `skip(existing-ok)`로 유지
- 하네스 게이트:
  - `preflight -> install -> health -> integration -> smoke`
  - 게이트 실패 시 즉시 중단하고 근거(step/code/tail) 기록
- 실행 모드:
  - 대화형: `interactive` (질문 1개씩)
  - 자동화/하네스: `non-interactive` (preset/default 우선, block 상황만 질문)
- 복구 전략:
  - 일시 장애는 3회 재시도(5s/10s/20s)
  - 재시도 실패 시 `partial` 또는 `fail`로 확정하고 다음 수동 액션 1개만 제시

### PHASE 1 선행 필수: 권한 계정 확인

PHASE 1 시작 시 아래 질문을 먼저 수행하고 응답을 기다립니다.

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

규칙:
- sudo 비밀번호 자체는 입력받아 저장하지 않습니다.
- `sudo -n true` 실패 + root 아님 → 즉시 중단 후 root/sudo 계정으로 재진입 안내.

## 빠른 시작 기본값

- OS: Ubuntu 22.04
- COMPOSE_MODE: single
- INTERNAL_NETWORK: 10.0.1.0/24
- DOMAIN: 빈 값
- SSL_TYPE: none
- SSH_VIA_BASTION: y
- IP: 10.0.1.10~13 (Bastion/GitLab/Nexus/Jenkins)

## 필수 명령

아래 `scripts/`는 **Git의 `devenv-core/scripts/`가 아니라**, `generate-configs.sh`가 채운 **`${DEVENV_HOME}/scripts/`** 를 가리킵니다.

```bash
bash scripts/generate-configs.sh
cd ~/devenv-{PROJECT_NAME}
python3 scripts/agent-orchestrator.py
python3 scripts/agent-orchestrator.py --quiet
python3 scripts/agent-orchestrator.py --jsonl-file .agent-logs/status.jsonl
```

릴리즈 전 회귀 검증:

```bash
bash scripts/verify-generator.sh
```

수동(디버깅) 모드:

```bash
bash scripts/00-root-bootstrap.sh
bash scripts/agent-preflight.sh
bash scripts/agent-install.sh
bash scripts/agent-verify.sh
```

## 출력 템플릿 (짧게 유지)

- 진행 중: `[PHASE X] 작업명 - 완료/대기`
- 오류: `원인 1줄 + 해결 1줄 + 재시도 명령 1줄`
- 완료:
  - 서비스 상태 4줄
  - 접속 URL 3줄
  - 비밀번호 위치 1줄(`config.env`)
