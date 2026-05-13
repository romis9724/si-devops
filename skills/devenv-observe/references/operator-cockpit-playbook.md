# 운영자 콕핏 플레이북 (MSA 가시성 · 인사이트 패턴)

제니퍼소프트 글에서 강조하는 **MSA 환경에서의 가시성**과 **모니터링을 넘어 인사이트로** 가는 흐름을, `devenv-observe` 스택(Prometheus · Grafana · Loki · 선택 APM)에서 **재현 가능한 패턴**으로 정리합니다.

## 참고 문서 (요구사항 출처)

- [마이크로서비스(MSA)의 복잡한 세계와 모니터링의 필요성](https://jennifersoft.com/ko/blog/tech/2025-09-24-msa-monitoring/) — 호출 관계·병목·근본 원인(Why)까지 가야 함.
- [제니퍼 AI, 인사이트(JENNIFER AI INSIGHTS)는 무엇인가?](https://jennifersoft.com/ko/blog/tech/2026-01-26-jenniferai-aimonitoring/) — 이상 탐지, 지표 상관, 패턴·규칙·LLM 기반 해석의 **역할 분담**.

상용 제품 기능을 그대로 복제하는 문서가 **아니라**, 운영자 입장에서 **같은 질문**(어디가 아픈가, 왜 그런가, 다음에 무엇을 보나)에 답하도록 스택을 쌓는 **설계 가이드**입니다.

---

## 0. 인프라/서비스 운영자에게 먼저 (추천 방식)

**원칙**: 스크레이프·노드·컨테이너는 **항상 보이는 Core**에 두고, 로그는 **Loki가 있을 때만** 보는 **별도 보드**로 나눈다. 한 장에 전부 넣으면 Loki 미설치 환경에서 빨간 패널이 줄줄이 뜨고, 장애 시 “도구 오류인지 서비스 오류인지”를 헷갈리게 된다.

| 순서 | Grafana 대시보드 | 언제 보나 |
|------|------------------|-----------|
| 1 (필수) | **Operator Cockpit — Core** (`devenv-overview.json`, uid `devenv-overview`) | 매 순간. 타깃 DOWN, 노드 CPU·메모리, Compose 서비스 CPU 상위. |
| 2 (선택) | **Operator Cockpit — Logs & errors** (`operator-cockpit-logs.json`) | Loki(및 수집기)가 있을 때. 예외 키워드 추이·원문 샘플. |

상단 **대시보드 링크**로 Core ↔ Logs 왕복 시 **시간 범위 유지(keepTime)** 로 같은 구간을 맞춘다.

**로그인 직후 화면(3중 고정)**: `GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH` + `GF_USERS_HOME_PAGE=/d/devenv-overview` + 기동 후 `PUT /api/org/preferences`·`PUT /api/user/preferences` — 상세는 [`phase-playbook.md`](phase-playbook.md) **5-1.10**.

**Grafana가 아닌 툴**(SkyWalking·Pinpoint·Zabbix·Kibana 등)은 제품별 UI·포트·동선이 다릅니다. 통합 표는 [`multi-tool-operator-guide.md`](multi-tool-operator-guide.md) 를 본다.

### 장애 징후 후 **처음 5분** (운영자 체크리스트)

1. **Core** 연다. **DOWN 타깃** 테이블에 행이 있으면 → 해당 `job`·`instance` 네트워크·프로세스·방화벽부터 본다 (스크레이프가 끊기면 앱이 멀쩡해도 “안 보임”).
2. **노드 CPU·메모리**가 한쪽 인스턴스에만 붙는지 본다 → 쏠림이면 그 호스트 위 컨테이너/프로세스로 좁힌다.
3. **Compose 서비스 CPU 상위**에서 특정 서비스만 튀는지 본다 → MSA에서 “어느 조각이 뜨거운지” 1차 후보.
4. 사용자 체감·API 지연이면 **APM/트레이스**(선택 스택)로 같은 시간대 스팬을 연다. (Core만으로는 “왜 느린지”까지는 부족할 수 있음.)
5. Loki가 있으면 **Logs** 보드로 넘어가, Core에서 본 **시간대**에 예외 키워드·로그 샘플이 맞는지 본다.

---

## 1. MSA에서 먼저 답해야 할 질문

[`2025-09-24-msa-monitoring`](https://jennifersoft.com/ko/blog/tech/2025-09-24-msa-monitoring/) 글의 요지를 운영 KPI로 옮기면 다음과 같습니다.

| 질문 | 최소 관측 |
|------|-----------|
| 지금 시스템이 살아 있는가? | 타깃 `up`, 스크레이프 실패, 핵심 SLO |
| 어느 조각이 뜨겁거나 막혔는가? | 노드·컨테이너 CPU/메모리/스로틀, 풀 포화 |
| 한 요청이 어디서 느려졌는가? | 분산 트레이스(OTel → Tempo/Jaeger/SkyWalking 등) |
| DB·캐시·큐가 원인인가? | DB/Redis/카프카 exporter 또는 스팬의 `db.*` 시맨틱 |
| 예외·오류가 언제·얼마나 쏟아졌는가? | 로그 볼륨·레벨·패턴(Loki), 또는 메트릭 `*_total` |

**설치 시 환경을 모를 때**는 이 표를 **모듈**로 취급합니다. 예: “Kubernetes 선택 시” 노드·파드 행 추가, “Loki 선택 시” 예외 히트맵 행 활성화.

---

## 2. JENNIFER AI INSIGHTS 개념 → OSS 매핑

[`2026-01-26-jenniferai-aimonitoring`](https://jennifersoft.com/ko/blog/tech/2026-01-26-jenniferai-aimonitoring/)에 나오는 기능군을 **기술 중립**으로 옮기면 아래와 같습니다.

| 인사이트 계열 | 역할 | OSS에서의 전형적 구현 |
|---------------|------|------------------------|
| Anomaly Event | 정상 패턴 대비 이상 알림 | Grafana Alerting, Prometheus `predict_linear`/`absent`, 또는 Mimir/Grafana Cloud 이상 탐지 |
| Metrics 상관분석 | 동시에 뭐가 움직였나 | 동일 시간축에 여러 패널, 또는 상관 플러그인/노트북 |
| X-View·패턴 | 지연 분포·이상치 한눈에 | 트레이스 UI의 산점도/워터폴, 또는 히스토그램·heatmap |
| Application Insights(규칙) | 최근 구간 자동 분류·다음 행동 | 대시보드 행 + 링크드 패널, Runbook 링크, Loki 패턴 쿼리 |
| LLM·챗 | 자연어로 데이터 조회·요약 | 선택: Grafana Assistant, 사내 봇 + 쿼리 API (거버넌스 필수) |
| 스택/트랜잭션 인사이트 | 긴 스택·프로파일 압축 | Continuous profiling(Pyroscope 등), 트레이스 스팬 이벤트 |

**원칙**: 모든 문제를 LLM에 맡기지 않고, **통계·규칙·트레이스**로 80%를 처리하고 LLM은 **요약·교육·Runbook 검색**에 쓰는 구성이 운영에 안전합니다. (글에서도 기술을 문제에 맞게 고른다고 명시합니다.)

---

## 3. Grafana 대시보드 (2단 구성)

| 파일 | 역할 |
|------|------|
| [`devenv-overview.json`](../templates/configs/grafana/dashboards/devenv-overview.json) | **Core**: `up`·DOWN 상세 테이블, 노드 CPU·메모리, Compose 서비스 CPU 상위. **uid 고정: `devenv-overview`**. |
| [`operator-cockpit-logs.json`](../templates/configs/grafana/dashboards/operator-cockpit-logs.json) | **Logs**: 예외 키워드·전체 로그 볼륨 시계열, 필터된 **로그 패널**. **Loki 필요.** |

Core는 MSA 글의 전제인 **“측정·가시성”** 중 인프라·스크레이프 층을 담당한다. Logs 보드는 인사이트 글의 **예외·패턴** 층을 로그로 최소 재현한다.

**한계**: 상용 APM의 X-View·트리맵·자동 시나리오 분류와 동일 UX는 아닙니다. 트레이스·APM은 선택 스택(SkyWalking 등)과 병행하는 **하이브리드**를 권장합니다.

---

## 4. 설치 후 운영자 워크플로 (권장)

1. **Core** 대시보드를 기본 홈처럼 연다.
2. DOWN 테이블·노드/컨테이너 포화를 본다.
3. Loki 사용 시 링크로 **Logs** 보드에 들어가 같은 시간대를 본다.
4. 앱 지표(RED)·트레이스가 있다면 동일 시간대에 **스팬**을 연다 (APM/OTel).
5. DB·큐 exporter가 켜져 있으면 **Dependencies** 보드(별도 구성)로 내려간다.
6. 장애 후 복기: 가능하면 로그에 `trace_id`를 싣고 Loki·트레이스와 연결.

---

## 5. 다음 확장 (선택)

- **서비스 맵**: OTel + 백엔드 토폴로지, 또는 Grafana Service Graph.
- **예외 히트맵**: Loki에 `exception_type`, `service_name` 라벨을 싣고 Heatmap 패널로 표현.
- **이상 탐지**: SLO 버닝 레이트 알림 + Grafana/Mimir 이상 탐지 규칙.

이 문서는 [`references/README.md`](README.md) 목록에 포함되어 있습니다.
