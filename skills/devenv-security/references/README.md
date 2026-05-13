# devenv-security `references/`

`SKILL.md`는 요약·계약·strict 요약만 두고, 긴 절차와 표는 여기 둡니다.

## 핵심

| 파일 | 용도 |
|------|------|
| [`phase-playbook.md`](phase-playbook.md) | PHASE 0~8, 오류 코드, 헬스, 저장소 내 스크립트·참조 경로 표. |
| [`harness-and-orchestration.md`](harness-and-orchestration.md) | RUN_PROFILE, 템플릿 변수, LLM/에이전트 규약, `run-security.sh`, 담당 도구 표. |
| [`../secrets/security.env.example`](../secrets/security.env.example) | `${DEVENV_HOME}/secrets/security.env` 작성용 예시 (`install-security.sh` 등이 자동 `source`). |

## 운영·보안 심화

| 파일 | 용도 |
|------|------|
| [`prerequisites.md`](prerequisites.md) | 설치 전 요구사항 |
| [`troubleshooting.md`](troubleshooting.md) | 증상별 대응 |
| [`lessons-learned.md`](lessons-learned.md) | 비자명 실패 사례 |
| [`optimization-checklist.md`](optimization-checklist.md) | 게이트·비용 점검 |
| [`health-check-guide.md`](health-check-guide.md) | 헬스 점검 가이드 |
| [`security-hardening.md`](security-hardening.md) | 하드닝 |
| [`airgap.md`](airgap.md) | 에어갭 |
| [`tls-migration.md`](tls-migration.md) | TLS 전환 |
| [`upgrade-and-rollback.md`](upgrade-and-rollback.md) | 업그레이드/롤백 |
| [`compatibility-matrix.md`](compatibility-matrix.md) | 버전 매트릭스 |
| [`pr-scan-guide.md`](pr-scan-guide.md) | PR 스캔 |
| [`sec-code-mapping.md`](sec-code-mapping.md) | SEC-E 코드 매핑 |

## 템플릿·스크립트 참고

- Sonar 프로젝트 속성: `sonar-project.properties.*.template`
- Jenkins/Groovy 참고: [`jenkins-sonar-installation.groovy`](jenkins-sonar-installation.groovy)

## 확인 순서

1. [`../SKILL.md`](../SKILL.md) **빠른 탐색**
2. 진행 중인 PHASE → [`phase-playbook.md`](phase-playbook.md)에서 `PHASE n` 검색
