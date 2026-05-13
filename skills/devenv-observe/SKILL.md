---
name: devenv-observe
description: >
  프로젝트 개발 인프라의 관측성(Observability) 스택을 자동으로 구성하는 스킬.
  devenv-core 설치를 전제로 Prometheus/Grafana/Loki/Promtail/SkyWalking(+선택 ELK)을 구성합니다.
---

# devenv-observe

## 빠른 탐색

| 찾는 내용 | 문서 |
|-----------|------|
| PHASE 0~7·오류 코드·헬스 | [`references/phase-playbook.md`](references/phase-playbook.md) |
| 스택 구성·아키텍처 | [`references/monitoring-stack.md`](references/monitoring-stack.md) |
| 사전 요구 | [`references/prerequisites.md`](references/prerequisites.md) |
| 함정·사례 | [`references/lessons-learned.md`](references/lessons-learned.md) |
| 증상별 조치 | [`references/troubleshooting.md`](references/troubleshooting.md) |
| 점검 체크리스트 | [`references/optimization-checklist.md`](references/optimization-checklist.md) |
| Alertmanager (개발 / 운영 참고) | [`templates/configs/alertmanager/alertmanager.yml`](templates/configs/alertmanager/alertmanager.yml) · [`references/alertmanager-config.yml`](references/alertmanager-config.yml) |
| SkyWalking → ES | [`references/skywalking-es-migration.md`](references/skywalking-es-migration.md) |
| 운영 콕핏 Core·Logs | [`references/operator-cockpit-playbook.md`](references/operator-cockpit-playbook.md) |
| 멀티 툴 운영 동선 | [`references/multi-tool-operator-guide.md`](references/multi-tool-operator-guide.md) |

**계약**: 충돌 시 [`../devenv-common/contracts/devenv-contract.md`](../devenv-common/contracts/devenv-contract.md) 우선.
**안 맞는 경우**: Datadog / New Relic 등 SaaS APM 환경, 1GB 미만 모니터링 호스트.
**산출물**: 관측 스택은 `templates/` + `references/`를 바탕으로 에이전트·생성기가 `${DEVENV_HOME}`에 compose/config를 펼친 뒤 기동. 단독 `install-all.sh`는 없음.

## 동작 방식

```
[PHASE 0] 프리셋 확인 → [1] 사전 검증 → [2] 설치 방식 선택 → [3] 환경 정보 수집
[PHASE 4] 구성 검토 → [5] 병렬 설치 → [6] devenv-app 병합 → [7] 완료 요약 + 프리셋 저장
```

게이트·Compose·네트워크·리소스 표준은 [`references/phase-playbook.md`](references/phase-playbook.md).

## preset.json (`observe` / `runtime`)

- **위치**: `${DEVENV_HOME}/preset.json` — 다른 스킬과 공유.
- **책임**: `observe` 및 필요 시 `runtime` 필드만 갱신. `core`는 읽기 위주.
- **재진입**: `runtime` 단독 신뢰 금지 — Docker 상태와 교차 검증 ([`references/phase-playbook.md`](references/phase-playbook.md) PHASE 0).

## ⚠️ 행동 원칙

1. 한 번에 질문 1개. 응답 후에만 다음 PHASE 진행.
2. 여러 PHASE 한 번에 처리 금지.
3. 기본 출력은 `compact`.
4. 설치 시작 전 sudo/root 권한 계정 확인.

## 출력 템플릿 (compact 기본, verbose는 요청 시)

- 진행: `[PHASE X] observe | status=ok|wait|fail | next=<action> | elapsed=<sec>`
- 오류: `[OBS-EXXX] <summary> | cause=<1-line> | action=<1-line> | next=retry|skip|abort`
- 완료: `[DONE] observe | metrics=ok logs=ok apm=ok app-link=ok|skip | alerting=ok|skip | failed=<n> | elapsed=<mm:ss>`
- `--telemetry-json` 시 동시 출력: `{"phase":5,"status":"ok","next":"phase6","elapsed_s":492}`
