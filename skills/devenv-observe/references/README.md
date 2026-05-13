# devenv-observe `references/`

`SKILL.md`는 PHASE 다이어그램·계약·출력 템플릿만 두고, 설치 표준·오류·헬스는 여기 둡니다.

**구현 스크립트**: 이 저장소는 **템플릿·문서·패처** 위주입니다. `devenv-core` 산출물의 `docker compose`와 동일하게 쓰려면 생성기/에이전트가 이 `templates/`를 렌더해 배포한다는 전제를 둡니다.

## 핵심

| 파일 | 용도 |
|------|------|
| [`phase-playbook.md`](phase-playbook.md) | PHASE 0~7, Compose/네트워크/리소스 표준, 오류 카탈로그, 헬스 표. |

## 스택·운영

| 파일 | 용도 |
|------|------|
| [`monitoring-stack.md`](monitoring-stack.md) | 모니터링 스택 상세 |
| [`prerequisites.md`](prerequisites.md) | 사전 요구 |
| [`health-check-guide.md`](health-check-guide.md) | 헬스 가이드 |
| [`troubleshooting.md`](troubleshooting.md) | 트러블슈팅 |
| [`lessons-learned.md`](lessons-learned.md) | 함정 사례 (실환경 배포 + 사후 검증 + Alertmanager 보강 사례 포함) |
| [`optimization-checklist.md`](optimization-checklist.md) | 점검 체크리스트 |
| [`operator-cockpit-playbook.md`](operator-cockpit-playbook.md) | MSA 가시성·인사이트 패턴, Grafana 콕핏 대시보드 연계 |
| [`multi-tool-operator-guide.md`](multi-tool-operator-guide.md) | SkyWalking·Pinpoint·Zabbix·ELK·APM 등 **Grafana 외** 툴별 운영 동선·포트 |

## 구성 파일·도구

| 파일 | 용도 |
|------|------|
| [`alertmanager-config.yml`](alertmanager-config.yml) | Alertmanager 표준(운영 알림 예시) |
| [`../templates/configs/alertmanager/alertmanager.yml`](../templates/configs/alertmanager/alertmanager.yml) | 기본 스택에 포함되는 개발용 Alertmanager 설정(noop) |
| [`skywalking-es-migration.md`](skywalking-es-migration.md) | SkyWalking ES 전환 |
| [`dashboard-patcher.py`](dashboard-patcher.py) | Community JSON 패치(datasource + templating) 후 **Grafana는 restart** |
| [`../templates/configs/grafana/dashboards/devenv-overview.json`](../templates/configs/grafana/dashboards/devenv-overview.json) | Operator Cockpit **Core** (`uid: devenv-overview`, 홈 3중 고정 대상) |
| [`../templates/configs/grafana/dashboards/operator-cockpit-logs.json`](../templates/configs/grafana/dashboards/operator-cockpit-logs.json) | Operator Cockpit **Logs** (예외·볼륨, Loki 필요) |
| [`../templates/configs/prometheus/alerts-operator.yml.tpl`](../templates/configs/prometheus/alerts-operator.yml.tpl) | Prometheus 알림 규칙 **예시**(선택, `rule_files`+마운트 동시 적용 시) |

## 확인 순서

1. [`../SKILL.md`](../SKILL.md) **빠른 탐색**
2. 현재 PHASE → [`phase-playbook.md`](phase-playbook.md) 목차 표 후 `PHASE n` 검색
