# devenv-observe Optimization Checklist

## 목적

`devenv-observe` 설치를 가볍고 안정적으로 유지하기 위한 운영 기준입니다.

## 아키텍처 선택

- 기본 로그 스택: Loki 우선
- ELK는 명시 요청 시만 활성화
- APM은 1개만 기본 활성화(다중 APM 기본 금지)

## 실행 게이트

- `preflight -> deploy -> readiness -> datasource-link -> smoke`
- readiness 실패 시 후속 게이트 중단
- 재시도 예산: `3회`, `5s/10s/20s`

## 충돌 회피

- 포트 우선순위: Core > App > Observe/Security
- Admin `3100` 유지, 충돌 시 Loki `3110` 이동

## 최소 성공 기준

- Prometheus `/ -/healthy` 성공
- Grafana `/api/health` 성공
- 선택된 로그/APM endpoint 성공
- 앱 메트릭 스모크 1개 이상 성공
