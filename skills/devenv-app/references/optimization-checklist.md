# devenv-app Optimization Checklist

## 목적

`devenv-app`의 배포 재현성과 부분 실패 복구 속도를 높이기 위한 체크리스트입니다.

## 사전 점검

- core readiness 확인(GitLab/Jenkins/Nexus/Docker)
- security/observe 감지 결과와 실제 컨테이너 상태 일치 확인
- 기존 repo 이력 존재 시 비파괴 전략(백업 브랜치 + 병합) 우선

## 하네스 게이트

- `Build -> Artifact -> Deploy -> Smoke`
- 각 repo(`backend/frontend/admin`)를 독립 실패 도메인으로 처리
- 실패 repo만 재시도(`repo-only retry`)

## 비파괴 정책

- 기본 동작에서 force push 금지
- 덮어쓰기 필요 시 백업 브랜치 생성 후 일반 push 우선
- non-fast-forward 지속 시 수동 병합 가이드 후 중단

## 실패 근거 수집

- 마지막 성공 단계
- 마지막 HTTP/exit 코드
- tail logs(30~50)

## 운영 KPI

- PHASE 6 first-pass 성공률
- repo-only 재시도 비율
- 부분 실패 복구 시간(`mttr_lite`)
