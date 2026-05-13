# 서버 아키텍처 및 포트 매핑

## 서버 역할 및 기본 포트

| 서버 | 서비스 | 포트 | 외부 노출 |
|------|--------|------|-----------|
| Bastion | SSH | 22 (단일서버 모드는 **2222** 자동 회피) | ✅ |
| GitLab | Web | 80 (단일서버 모드는 **8082**) | 내부망 / 팀 IP |
| GitLab | SSH | 2222 | 내부망 |
| Nexus | Web/API | 8081 | 내부망 |
| Nexus | Docker Registry | 5000 | 내부망 |
| Jenkins | Web | 8080 | 내부망 / 팀 IP |
| Jenkins | Agent | 50000 | 내부망 |
| DB MySQL/MariaDB | DB | 3306 | ❌ 격리 |
| DB PostgreSQL | DB | 5432 | ❌ 격리 |
| DB MongoDB | DB | 27017 | ❌ 격리 |
| Backend | API | **APP_PORT** (기본 8080, 단일서버는 **8083** 자동 회피) | 선택적 외부 |
| Frontend | Web | **FRONTEND_PORT** (기본 3000) | 선택적 외부 |
| Admin | Web | **ADMIN_PORT** (기본 3100; Loki와 충돌 시 Loki를 3110으로) | 선택적 외부 |
| SonarQube | Web | 9000 | 내부망 |
| OWASP ZAP | API | 8090 | 내부망 |
| Prometheus | Scrape | 9090 | 내부망 |
| Grafana | Web | 3001 | 내부망 / 팀 IP |
| Loki | API | **HOST_PORT_LOKI** (기본 3100, Admin=3100과 충돌 시 **3110**) | 내부망 |
| Pinpoint Web | Web | 8079 (택1) | 내부망 |
| Pinpoint Collector | UDP/TCP | 9991-9996 | 내부망 |
| SkyWalking UI | Web | 8079 (택1) | 내부망 |
| SkyWalking OAP | gRPC | 11800 / 12800 | 내부망 |
| Elasticsearch (ELK) | API | 9200 | 내부망 |
| Logstash | Beats | 5044 / 5000 | 내부망 |
| Kibana | Web | 5601 | 내부망 |
| node-exporter | Scrape | 9100 | 내부망 |
| cAdvisor | Scrape | **8088** (lessons §7로 8080→8088 이전) | 내부망 |
| Zabbix Server | TCP | 10051 | 내부망 |
| Zabbix Web | Web | 3001 (Grafana 미사용 시) | 내부망 |

> **단일 서버 모드 포트는 자동 고정**(generate-configs.sh STEP 3):
> - `GitLab` 80 → **8082**
> - `Backend` 8080 → **8083** (Jenkins=8080과 충돌 시)
> - `Loki` 3100 → **3110** (Admin=3100과 충돌 시 + LOG_STACK=loki일 때)
> - `Bastion SSH` 22 → **2222** (호스트 sshd:22 충돌 회피)
> - `GitLab SSH` 22 → **2223** (Bastion 2222와 분리)
>
> 조정된 값은 `config.env`의 `HOST_PORT_*` 변수로 기록되며 모든 compose가 이를 참조.

---

## Nexus Docker Registry 주소 (lessons §3-3)

| 모드 | 변수 `NEXUS_REGISTRY` | 비고 |
|------|----------------------|------|
| `single` | `127.0.0.1:5000` | 호스트 daemon이 `localhost:5000`로 push/pull → tag 일치 |
| `multi`  | `${NEXUS_IP}:5000` | 다른 호스트에서 접근 |

모든 backend/frontend/admin compose 및 Jenkinsfile은 `${NEXUS_REGISTRY}`를 사용 — `${NEXUS_IP}:5000` 직접 사용 금지.

---

## Docker 네트워크 구성

| 네트워크 | 용도 | internal? |
|---------|------|-----------|
| `devenv-internal` | 모든 서비스 공통 | no |
| `devenv-db` | DB 격리 (외부 인터넷 차단) | yes |
| `devenv-monitoring` | Prometheus/Grafana/Loki 전용 | no |
| `devenv-apm` | APM 스택 전용 | no |
| `devenv-logging` | ELK 전용 | no |
| `devenv-security` | SonarQube + DB 격리 | no |

DB는 **`devenv-db` (internal)** + **`devenv-internal`** 양쪽에 연결돼 Backend는 `devenv-internal`을 통해 접근하고 외부 인터넷은 차단됩니다.

> **다중 서버 모드 주의**: 모든 네트워크가 `external: true`로 정의돼 있어 단일 호스트 docker daemon에서만 통신 가능. 다중 호스트 간 통신이 필요하면 Docker Swarm overlay 또는 Kubernetes 마이그레이션 필요 (현 스킬은 미지원).

---

## 설치 흐름

`devenv-core`는 재현성을 위해 병렬 기동보다 준비 완료 기반 순차 설치를 사용합니다.

```
preflight
  -> bootstrap
  -> bastion
  -> gitlab
  -> wait GitLab (/users/sign_in)
  -> nexus
  -> wait Nexus (/service/rest/v1/status)
  -> jenkins
  -> health-check
```

---

## 트래픽 흐름

```
[인터넷]
   │
   ▼
[Bastion Host]  ── 유일한 외부 진입점
   │ SSH ProxyJump
   ▼
[내부 네트워크]
   ├── 개발자 → Jenkins / GitLab (관리)
   ├── Jenkins → GitLab / Nexus / 보안점검 (CI 통신)
   ├── Backend → DB (격리 네트워크)
   ├── Frontend / Admin → Backend (API 호출)
   └── 모든 서버 → 모니터링/APM/로그 (메트릭/로그 push)
```
