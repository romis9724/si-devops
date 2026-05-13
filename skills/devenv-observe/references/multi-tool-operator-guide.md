# 멀티 툴 운영자 가이드 (Grafana 외 스택)

`devenv-observe`는 설치 프리셋에 따라 **Grafana·Prometheus·Loki·SkyWalking·Pinpoint·Zabbix·ELK·Elastic APM** 등을 조합합니다.  
운영자 입장에서 **“어떤 툴을 언제 열고, 로그인 후 무엇을 보나”** 를 한곳에 정리합니다.  
공통 1차 화면은 **Grafana Operator Cockpit — Core** 이지만, APM·인프라 전용 UI는 각 제품을 씁니다.

---

## 1) 툴별 빠른 표

| 스택 (Compose 템플릿) | 운영자가 보는 UI | 기본 포트(예) | 로그인 후 1차 동선 |
|------------------------|------------------|----------------|----------------------|
| Prometheus + Grafana | Grafana | 3001 (템플릿 기준) | **자동**: `devenv-overview` 홈 (`GF_*` + API, phase-playbook 5-1.10) |
| Loki + Promtail | Grafana (Logs 보드) | 3100 Loki | **수동 링크**: Core 상단 → Logs 보드 |
| SkyWalking | SkyWalking UI | 8079 | **메뉴**: Service → Topology / Trace (UI 기본 인증 없음) |
| Pinpoint | Pinpoint Web | 8079 | **메뉴**: Server Map / Scatter / Inspector (이미지별 기본 계정 확인) |
| Zabbix | Zabbix Web | 8089 | **로그인** 후 Dashboards / Problems — 서버 표시명 `Zabbix-${PROJECT_NAME}` |
| ELK (Kibana) | Kibana | 5601 | **Discover**: 로그인 후 수동 또는 아래 **API로 defaultRoute** 설정(Compose에는 넣지 않음) |
| Elastic APM Server만 | Kibana APM 앱 | 8200 APM ingest | 데이터 확인은 **Kibana** `/app/apm` (ELK와 함께 구성 시) |

**주의**: SkyWalking UI와 Pinpoint Web 템플릿 모두 호스트 **8079**를 쓰도록 되어 있어, **동시에 띄우지 않는 것**이 안전합니다. 프리셋에서 하나만 선택하세요.

---

## 2) Prometheus (알림 규칙, 선택)

- 기본 compose에는 **포함하지 않음**: `rule_files`로 파일을 가리키면 해당 파일이 없을 때 Prometheus가 **기동 실패**한다.
- 예시 규칙: `templates/configs/prometheus/alerts-operator.yml.tpl` (`TargetDown`, `NodeCpuHigh`, `NodeMemoryPressure`) — `prometheus.yml`에 `rule_files` 추가 + compose에 동일 파일 마운트를 **함께** 적용할 때만 사용.
- Alertmanager가 없으면 알림은 **Prometheus UI** (`/alerts`)·`/rules` 에서만 보일 수 있습니다.

---

## 3) Loki / Promtail

- Promtail 정적 라벨: `project`, `job`, `owner=operator`, `log_format` — LogQL 예: `{owner="operator", job="containerlogs"}`
- 운영 1차: Grafana **Operator Cockpit — Logs** (`operator-cockpit-logs.json`)

---

## 4) Kibana — 기본 화면을 Discover로 두고 싶을 때

Compose에는 `SERVER_DEFAULTROUTE`를 넣지 않았다(이미지·버전별 호환 이슈 회피). 필요 시 컨테이너 기동 후 API로 설정한다 (관리자 세션 또는 적절한 인증):

```bash
curl -s -X POST "http://<KIBANA_HOST>:5601/api/kibana/settings" \
  -H "kbn-xsrf: true" -H "Content-Type: application/json" \
  -u "elastic:<ELASTIC_PASSWORD>" \
  -d '{"changes":{"defaultRoute":"/app/discover"}}'
```

버전에 따라 인증 방식이 다를 수 있어, Elastic 8 문서를 우선 확인하세요.

---

## 5) Grafana와의 역할 나누기 (추천)

| 관측 | 주 툴 |
|------|--------|
| 스크레이프·노드·컨테이너 포화 | Grafana Core + Prometheus |
| 로그 키워드·볼륨 | Grafana Logs (Loki) 또는 Kibana Discover |
| 분산 트레이스·서비스 맵 | SkyWalking / Pinpoint / Kibana APM |
| 호스트·템플릿 기반 인프라 경보 | Zabbix |

---

## 6) 관련 문서

- [`operator-cockpit-playbook.md`](operator-cockpit-playbook.md) — Core·Logs 2단, 5분 체크리스트
- [`monitoring-stack.md`](monitoring-stack.md) — Compose·Prometheus 예시
