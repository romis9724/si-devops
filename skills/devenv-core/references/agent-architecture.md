# Agent Architecture (devenv-core)

`devenv-core` 설치 시간을 줄이기 위한 에이전트 도입 아키텍처입니다.
핵심은 병렬 설치가 아니라 실패 예방/자동 복구를 통해 재설치 횟수를 줄이는 것입니다.

## 목표

- 설치 성공률 향상
- 재설치 빈도 감소
- 토큰 사용량 최소화
- 장애 시 자동 근거 수집

## 에이전트 구성

1. Preflight Agent
   - 실행: `bash scripts/agent-preflight.sh`
   - 역할: 설치 전 실패 요인 제거
2. Install Agent
   - 실행: `bash scripts/agent-install.sh`
   - 역할: 순차 설치 오케스트레이션 + 실패 로그 자동 수집
3. Verify Agent
   - 실행: `bash scripts/agent-verify.sh`
   - 역할: 헬스체크와 최종 상태 보고

## 데이터 계약 (저토큰)

모든 에이전트는 다음 JSON 1줄을 기본 출력으로 사용:

```json
{"phase":"install","status":"ok","action":"health_check","risk":"low","message":"install completed"}
```

필드:
- `phase`: preflight | install | verify
- `status`: running | ok | fail
- `action`: 다음 실행 액션
- `risk`: low | medium | high
- `message`: 1문장 요약

## 운영 가드레일

- destructive 작업(`teardown`, `down -v`)은 별도 확인 필수
- 실패 시 로그는 최근 40~50줄만 수집 (토큰 폭증 방지)
- 정상 시 상세 로그 출력 금지
- 시작 시 권한 게이트 필수:
  - `sudo -n true` 가능 여부 확인
  - 불가 시 `sudo -v` 안내 후 중단
  - root 전용 작업은 `00-root-bootstrap.sh`로 분리

## 추천 실행 순서

```bash
bash scripts/00-root-bootstrap.sh
bash scripts/agent-preflight.sh
bash scripts/agent-install.sh
bash scripts/agent-verify.sh
```

또는 오케스트레이터 단일 실행:

```bash
python3 scripts/agent-orchestrator.py
python3 scripts/agent-orchestrator.py --quiet
python3 scripts/agent-orchestrator.py --jsonl-file .agent-logs/status.jsonl
```

## CI/CD 권장

- PR 파이프라인: `bash scripts/verify-generator.sh`
- 릴리즈 전 smoke: 에이전트 3단계 실행 + JSON 결과 아카이브
