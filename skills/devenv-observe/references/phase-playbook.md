# devenv-observe — PHASE 실행 피드북

PHASE 0~7, 오류 카탈로그, 헬스 기준, 참조 링크. **현재 PHASE**에 해당하는 절만 읽습니다.

## 목차 (PHASE)

| PHASE | 주제 |
|------|------|
| 0 | 프리셋 · idempotency |
| 1 | 사전 검증 |
| 2 | 설치 방식 |
| 3 | 환경 정보 |
| 4 | 구성 검토 |
| 5 | 병렬 설치 · 게이트 · 표준 |
| 6 | devenv-app 병합 |
| 7 | 완료 · preset |
| - | 오류 · 헬스 · 참조 |

## PHASE 0: 프리셋 확인

- [`../SKILL.md`](../SKILL.md) **preset.json (`observe` / `runtime`)** 절과 동일 — `${DEVENV_HOME}/preset.json`의 `observe`, `runtime`를 확인합니다.
- **재진입/Idempotency 규칙(필수)**:
  - `runtime.completedAgents`만 신뢰하지 말고 실제 Docker 상태와 교차검증합니다.
  - 모든 PHASE 시작 시 컨테이너/네트워크/볼륨/포트 존재를 검사해 SKIP/실행을 결정합니다.
  - 동일 컨테이너는 `docker compose up -d` 재실행이 idempotent여야 합니다.
  - 동일 네트워크는 기존과 `driver/subnet`이 다르면 fail-fast(`OBS-E104`) 처리합니다.
  - Grafana 대시보드 provider는 **`folder: Observability` + `folderUid: ${PROJECT_NAME}-obs`** 표준을 쓴다. 흔한 이름(`devenv` 등)만으로 미리 만든 폴더와 충돌하면 `OBS-E601`이다.

---

## PHASE 1: 사전 검증

### 1-0. 권한 계정 확인

```bash
whoami
id
sudo -n true >/dev/null 2>&1 || echo "SUDO_PASSWORD_REQUIRED"
```

### 1-0a. OS 분기 (Linux vs macOS / Darwin)

- `uname -s` 출력이 **`Darwin`** 이면 다음을 적용한다.
  - **`vm.max_map_count`**, **`timedatectl`** 검증은 **생략**한다 (macOS에서 무의미·미지원).
  - Docker Desktop **Settings → Resources** 에서 **CPU ≥ 6**, **Memory ≥ 8GB** 인지 수동 확인한다.
- **`Linux`** 이면 아래 1-1의 `sysctl`·`timedatectl` 절차를 그대로 수행한다.

### 1-1. 설치 계약(Contract) 검증 — Fail Fast

```bash
docker network ls | grep -E 'devenv-core|devenv-internal|devenv-monitoring'
docker ps >/dev/null
if [ "$(uname -s)" = "Linux" ]; then
  sysctl vm.max_map_count
  timedatectl status | grep -E 'NTP|synchronized'
  cat /etc/docker/daemon.json | jq '.["log-driver"], .["log-opts"]'
fi
```

- Docker daemon 로그 권장 설정:
```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "50m", "max-file": "5" }
}
```

- 미설정/무회전은 디스크 폭증(`OBS-E303`) 원인이 됩니다.
- **Darwin** 은 `/etc/docker/daemon.json` 검사를 생략한다. Docker Desktop 설정에서 로그 회전·디스크 상한을 확인한다.

### 1-2. devenv-core 설치 확인

```bash
docker network ls | grep devenv-core
cat ${DEVENV_HOME}/preset.json | grep '"core"'
```

### 1-3. 각 서비스 상태 확인

```bash
curl -fsS http://<MONITORING_IP>:9090/-/healthy && echo "OK" || echo "FAIL"
wget -qO- http://<MONITORING_IP>:3001/api/health >/dev/null 2>&1 && echo "OK" || echo "FAIL"
curl -fsS http://<MONITORING_IP>:3100/ready && echo "OK" || echo "FAIL"
curl -fsS http://<APM_IP>:8079 >/dev/null && echo "OK" || echo "FAIL"
```

### 1-4. Grafana 폴더 사전 확인 (OBS-E601 예방)

- 프로비저닝 전에 기존 폴더·UID 충돌을 확인한다 (`devenv-app` 등이 `devenv` 등 흔한 폴더를 만들어 두면 provider 등록이 실패할 수 있음).
```bash
curl -sfS -u "admin:${GRAFANA_PASSWORD}" "http://<MONITORING_IP>:3001/api/folders?limit=5000" \
  | jq -r '.[] | "\(.uid)\t\(.title)"'
```
- 표준 provider는 **`folder: Observability`**, **`folderUid: <PROJECT>-obs`** (`dashboards.yml.tpl`). 동일 `folderUid` 또는 동일 제목으로 이미 존재하면 정리 후 재시도한다.

---

## PHASE 2: 설치 방식 선택

- 기존 빠른 시작/상세 설정 플로우를 유지합니다.

---

## PHASE 3: 환경 정보 수집

- 기존 질문 흐름을 유지하되 운영 모드에서는 서비스별 비밀번호 분리를 기본으로 안내합니다.
- `ADMIN_SHARED_PASSWORD` 단일 공유는 횡적 침투 위험이 있으므로 금지 권장.

---

## PHASE 4: 구성 검토

- Retention 정책은 시간보다 디스크 한계를 우선합니다.
- 사용자에게 디스크 가용량을 먼저 보여준 뒤 예상치를 안내합니다.
  - 예: `30d retention 시 약 X GB 예상 (워크로드 기준)`  
- 최종 기본값은 `--storage.tsdb.retention.size` 중심으로 확정하고 `time`은 보조 기준으로 설명합니다.

---

## PHASE 5: 병렬 설치

### 설치 오케스트레이션

- Gate 0(preflight) -> Gate 1(metrics/logs 병렬) -> Gate 2(APM) -> Gate 3(Verifier)
- 성공 기준은 running이 아니라 `healthcheck + 연결 검증`.

### Compose project 이름 정합성 (필수)

- 기존 devenv-core 컨테이너 recreate/merge 시 반드시 아래 형식을 사용합니다.
```bash
docker compose -p devenv-${PROJECT_NAME} -f <file> up -d
```
- `-p` 누락 시 default project로 동작하여 컨테이너 이름 충돌 + orphan volume이 발생할 수 있습니다.

### Cross-compose-project DNS/네트워크 표준

```yaml
networks:
  devenv-monitoring:
    name: devenv-monitoring
    driver: bridge
  devenv-internal:
    external: true
    name: devenv-internal
```

- 모니터링 컨테이너는 두 네트워크 모두 attach합니다.
- `preset.json`의 `ips.bastion` 등은 logical label이며 Docker network IP가 아닙니다.
- scrape target은 컨테이너명 DNS(`jenkins-${PROJECT}`, `gitlab-${PROJECT}`, `nexus-${PROJECT}`)를 사용합니다.

### 리소스 제한/예약 표준 (필수)

- 모든 서비스에 `mem_limit` 또는 `deploy.resources`를 둡니다.
- baseline:
  - prometheus `2g`
  - grafana `1g`
  - loki `1g`
  - promtail `256m`
  - skywalking-oap `1.5g`
  - node-exporter `128m`
  - cadvisor `512m`
- SkyWalking은 `JAVA_OPTS -Xmx`와 `mem_limit`을 반드시 정렬합니다.

### Secret 관리 표준

- Grafana 관리자 비밀번호 평문 환경변수 직접 주입을 피합니다.
- `env_file`/`.env` 분리 + `chmod 600`를 사용합니다.
- Compose 예시:
```yaml
environment:
  GF_SECURITY_ADMIN_PASSWORD__FILE: /run/secrets/grafana_admin
secrets:
  grafana_admin:
    file: ../config.env
```

### Alertmanager (기본 스택)

- **`templates/compose/monitoring-prometheus.yml.tpl`** 에 `alertmanager`(9093) 서비스가 포함됩니다. 설정 파일: `templates/configs/alertmanager/alertmanager.yml` (개발용 noop 수신 — 실제 알림 없음).
- **`templates/configs/prometheus.yml.tpl`** 에 `alerting.alertmanagers` → `alertmanager:9093` 이 정의되어 있습니다.
- **운영 알림**(Slack/메일 등): `references/alertmanager-config.yml` 를 참고해 `alertmanager.yml` 을 교체하거나 마운트 경로를 조정합니다.
- (선택) Prometheus 운영자 알림 규칙: `templates/configs/prometheus/alerts-operator.yml.tpl` — `prometheus.yml`의 `rule_files`와 compose 마운트를 **함께** 넣을 때만 사용. 파일만 빠지면 Prometheus가 기동하지 않는다.

### Loki 최신 스키마 표준

- `schema: v13`, `store: tsdb`, `allow_structured_metadata: true`, `ingestion_rate_mb: 16`
- `v11 + boltdb` 조합은 deprecation 경고가 발생하므로 기본값으로 사용하지 않습니다.

### Promtail positions 영속화

- `positions.filename: /tmp/positions.yaml`
- named volume(`promtail-positions`)에 매핑하여 재시작 시 전체 재수집을 방지합니다.

### Readiness gate 강화

- SkyWalking OAP는 H2 초기화로 60~90초가 필요할 수 있습니다.
- `healthcheck.start_period: 90s`, `retries: 10`을 기본으로 사용합니다.
- readiness 판정 전 최소 90초 대기 또는 `healthy` 폴링을 수행합니다.

### 5-1.1 Jenkins 메트릭 노출 표준

- `metrics_path: '/prometheus/'` (trailing slash 필수)
- `/prometheus`(slash 없음)는 302 redirect로 실패할 수 있습니다.

### 5-1.2 GitLab 메트릭 노출 표준

```ruby
gitlab_rails['monitoring_whitelist'] = ['127.0.0.0/8', '10.0.1.0/24', '172.16.0.0/12']
gitlab_exporter['enable'] = true
gitlab_exporter['listen_address'] = '0.0.0.0'
gitlab_exporter['listen_port'] = 9168
gitlab_workhorse['prometheus_listen_addr'] = '0.0.0.0:9229'
```

### 5-1.3 MySQL exporter · backend JDBC (OBS-E701)

- **MySQL 8** 기본 인증 `caching_sha2_password` + **비 SSL** JDBC 에서는 `allowPublicKeyRetrieval=true` 가 없으면 연결 실패가 난다.
- **mysqld_exporter** 는 앱 DB 사용자와 분리한 전용 계정을 쓴다. 권한 예: `PROCESS`, `REPLICATION CLIENT`, 스크랩 대상에 필요한 `SELECT` 만.
- exporter 비밀번호는 **다른 스킬의 secrets를 읽지 말고** `observe.env`(또는 observe 전용 env)에 **신규 키**로 발급한다 — deny rule·교차 스킬 참조로 막혀 실패한 사례가 있다.
- exporter DSN(Go 드라이버) 예: `exporter_user:비밀번호@tcp(mysql:3306)/?allowPublicKeyRetrieval=true` (실제 호스트·DB명에 맞게 조정).

### 5-1.4 SkyWalking Java Agent 연동 표준

- `apache/skywalking-java-agent` Docker 이미지보다 Apache archive 직접 다운로드를 기본 권장:
  - `https://archive.apache.org/dist/skywalking/java-agent/${VER}/apache-skywalking-java-agent-${VER}.tgz`

### 5-1.5 Prometheus reload 한계 (강화)

- `POST /-/reload`가 200이어도 추가된 `scrape_config`가 반영되지 않을 수 있습니다.
- 원인: 호스트/컨테이너 bind mount inode 불일치(`OBS-E402`).
- 필수 조치: `docker restart <prometheus-container>`로 inode 재바인딩.
- 검증:
```bash
docker exec <prom> grep -A 3 '<new-job-name>' /etc/prometheus/prometheus.yml
curl -s http://localhost:9090/api/v1/targets?state=active | jq '.data.activeTargets[] | .labels.job' | sort -u
```

### 5-1.6 권한 승인 패턴 (Harness)

- 세션 내에서도 action context가 바뀌면 이전 승인이 무효화될 수 있습니다.
- `AskUserQuestion`은 작업별로 분리 승인합니다.
- "A/B/C 한번에 승인" 묶음은 후속 단계에서 재거부될 가능성이 높습니다.

### 5-1.8 셸 호환성 표준 (WSL2 · macOS+zsh)

- PowerShell에서 `wsl bash -c '...'` inline 실행 시 awk의 `$7`, `$4` 참조 깨짐 및 토큰 분리 이슈가 발생할 수 있습니다.
- **macOS + zsh** 에서도 동일한 인라인·토큰 이슈가 보고되었습니다. 다단계 작업은 **항상 스크립트 파일**로 분리합니다.
- 표준 형식: `/tmp/<name>.sh` 작성 후 실행 (`wsl bash …` 또는 로컬 `bash /tmp/<name>.sh`).
- **첫 줄 직후** `PATH` 를 명시한다 (Homebrew 등):
```bash
export PATH=/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin
```
```bash
# bad
wsl bash -c 'awk "{print $7}" ...'

# good
cat >/tmp/observe-step.sh <<'EOF'
#!/usr/bin/env bash
export PATH=/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin
set -euo pipefail
...
EOF
wsl bash /tmp/observe-step.sh
```

### 5-1.9 Community 대시보드 datasource 패치 & Grafana 재기동

- `${DS_PROMETHEUS}` 등 문자열 `datasource` 치환만으로는 부족한 JSON이 있다. `references/dashboard-patcher.py` 는 재귀 치환에 더해 **`templating.list[]` 의 `type: datasource` 항목**에 대해 `current: {selected:true, text:<uid>, value:<uid>}` 를 **프로비저 uid(`prometheus` / `loki`)** 로 강제한다.
- 패치 반영 후 Grafana는 **`reload` 금지** — 바인드 마운트 inode 이슈와 동일 계열로 설정이 안 보일 수 있다. **`docker restart grafana-<project>`** 로 재기동한다 (`OBS-E402`와 동일 원칙).

### 5-1.10 Grafana 홈 대시보드 3중 고정

- `GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH` + `GF_USERS_HOME_PAGE` 만으로는 **사용자별 홈이 풀리는** 경우가 있다.
- 프로비저닝·대시보드 JSON에 **`uid: devenv-overview`** 를 부여한 뒤(파일명 `devenv-overview.json`), 기동 후 **관리자 세션**으로 API를 추가 호출한다:
```bash
# 조직 기본 홈
curl -sfS -X PUT "http://<MONITORING_IP>:3001/api/org/preferences" \
  -u "admin:${GRAFANA_PASSWORD}" -H "Content-Type: application/json" \
  -d '{"homeDashboardUID":"devenv-overview","timezone":"browser","weekStart":"browser"}'

# 관리자 사용자 홈
curl -sfS -X PUT "http://<MONITORING_IP>:3001/api/user/preferences" \
  -u "admin:${GRAFANA_PASSWORD}" -H "Content-Type: application/json" \
  -d '{"homeDashboardUID":"devenv-overview","timezone":"browser"}'
```

---

## PHASE 6: devenv-app 병합 (감지 시)

- 기존 app 컨테이너 recreate는 반드시 project명을 명시한다.
```bash
docker compose -p devenv-${PROJECT_NAME} -f <file> up -d
```

### 6-1. backend 컨테이너 표준 (관측·에이전트)

| 항목 | 표준 |
|------|------|
| Spring Actuator | `MANAGEMENT_PROMETHEUS_METRICS_EXPORT_ENABLED=true` |
| 노출 엔드포인트 | `MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE=health,info,prometheus,metrics` |
| SkyWalking Java Agent | `JAVA_TOOL_OPTIONS=-javaagent:/sw/skywalking-agent.jar` |
| 에이전트 식별 | `SW_AGENT_NAME`, `SW_AGENT_INSTANCE_NAME`(또는 이미지별 `INSTANCE_NAME`), `SW_AGENT_COLLECTOR_BACKEND_SERVICES`(예: `skywalking-oap:11800`), `SW_AGENT_NAMESPACE`(선택) |
| 볼륨 | `<monitoring>/skywalking-agent` 호스트 경로를 컨테이너 **`/sw:ro`** 로 마운트 (에이전트 JAR 위치와 일치) |

- **외부 `docker run` 으로 만들어진 동일 이름 컨테이너**가 있으면 Compose와 충돌한다 (`OBS-E702`). `docker stop` / `docker rm` 후 아래로 재생성한다.
```bash
docker compose -p devenv-${PROJECT_NAME} -f <compose.yml> up -d --force-recreate
```

---

## PHASE 7: 완료 요약 + 프리셋 저장

- 완료 요약에 Alertmanager URL을 포함합니다.
  - `http://<MONITORING_IP>:9093`
- 운영 사용 전 SkyWalking은 H2를 계속 사용하지 않습니다.
  - H2는 PoC 전용, 운영 전 Elasticsearch backend로 전환합니다.
  - 가이드: `references/skywalking-es-migration.md`

### 다음 단계 (Uninstall 포함)

```bash
cd ${DEVENV_HOME}/monitoring
docker compose -p devenv-monitoring down -v
# -v 없이 실행하면 볼륨(데이터) 보존
```

---

## 오류 처리

### 오류 코드 카탈로그 (확장)

| 코드 | 분류 | 대표 증상 | 기본 조치 |
|------|------|-----------|-----------|
| OBS-E101 | PortConflict | address already in use | 대체 포트 제안 |
| OBS-E102 | DockerAccessDenied | docker.sock permission denied | 권한/그룹 확인 |
| OBS-E103 | PortDriftConflict | 타 compose project 포트 점유 | project명/포트 소유 확인 |
| OBS-E104 | NetworkDriverMismatch | 기존 네트워크 driver/subnet 불일치 | fail-fast 후 수동 정합 |
| OBS-E201 | NetworkMissing | 서비스 간 DNS 연결 실패 | 네트워크 재연결 |
| OBS-E301 | VmMaxMapTooLow | ES 시작 실패 | vm.max_map_count 상향 |
| OBS-E302 | ResourceInsufficient | OOM/재시작 반복 | 리소스 상향 |
| OBS-E303 | LogDriverDiskFull | json-file 미회전으로 디스크 가득 참 | daemon log-opts 적용 |
| OBS-E401 | HealthcheckFailed | running but unhealthy | endpoint 재검증 |
| OBS-E402 | BindMountInodeStale | reload 200이나 설정 미반영 | prometheus / grafana **restart** (inode 재바인딩) |
| OBS-E403 | GrafanaHealthcheckPatternMismatch | Grafana health JSON 패턴 고정 grep 오탐 | wget/공백 허용 regex 사용 |
| OBS-E601 | GrafanaFolderProvisionConflict | `devenv` 등 기존 폴더·UID와 provider 충돌 | `GET /api/folders` 확인 후 충돌 폴더 정리·`folderUid` 표준 준수 |
| OBS-E701 | MySQLAuthExporterMismatch | exporter/JDBC `caching_sha2`·키 읽기 실패 | `allowPublicKeyRetrieval`, 전용 exporter 유저, `observe.env` 전용 비밀 |
| OBS-E702 | ExternalContainerNameCollision | 외부 `docker run` 과 compose 이름·포트 충돌 | `docker stop`/`rm` 후 `compose -p … up -d --force-recreate` |
| OBS-E501 | AlertmanagerNotConfigured | alerting block/receiver 누락 | alertmanager 추가 |
| OBS-E502 | SecretInPlainEnv | 평문 비밀번호 환경변수 노출 | secret file 분리 |
| OBS-E901 | Unknown | 원인 미확정 | 로그 수집 후 재시도 |

---

## 헬스체크 기준 (수정)

| 서비스 | 명령 | 정상 기준 |
|--------|------|-----------|
| Prometheus | `curl -fsS http://<IP>:9090/-/healthy` | HTTP 200 |
| Grafana | `wget -qO- http://<IP>:3001/api/health >/dev/null 2>&1` | 종료코드 0 |
| Loki | `curl -fsS http://<IP>:3100/ready` | `ready` |
| Alertmanager | `curl -fsS http://<IP>:9093/-/healthy` | HTTP 200 |
| SkyWalking OAP (10.1+) | `curl -fsS http://<IP>:12800/healthcheck` | HTTP 200 (`/internal/l7check` 제거됨) |

---

## 참조 정보

- 모니터링 상세: `references/monitoring-stack.md`
- Grafana 대시보드 패처: `references/dashboard-patcher.py`
- Alertmanager 표준: `references/alertmanager-config.yml`
- SkyWalking ES 전환: `references/skywalking-es-migration.md`
