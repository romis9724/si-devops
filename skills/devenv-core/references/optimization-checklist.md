# devenv-core Optimization Checklist

## 목적

`devenv-core` 실행 품질을 인프라/DevOps/하네스 관점에서 빠르게 점검하기 위한 체크리스트입니다.

## Preflight

- 권한 컨텍스트 확인: `root` 또는 `sudo -n true` 성공
- 포트 충돌 확인: `2222`, `2223`, `8080`, `8081`, `8082`, `5000`
- 커널 파라미터 확인: `vm.max_map_count >= 262144`
- Docker/Compose 확인: `docker info`, `docker compose version`

## Install Gate

- 순서 고정: `bastion -> gitlab -> nexus -> jenkins`
- 파괴적 옵션 금지: `--remove-orphans` 기본 사용 금지
- 재시도 예산: `maxAttempts=3`, `backoff=5s/10s/20s`

## Health Gate

- GitLab: `/users/sign_in`
- Jenkins: `/login`
- Nexus: `/service/rest/v1/status`
- 실패 시 근거 3종 기록: `last step`, `last http/code`, `tail logs(30~50)`

## 운영 품질 KPI

- first-pass 성공률
- 부분 복구 평균 시간(`mttr_lite`)
- 부분 재시도 비율(`retry_efficiency`)
