# monitoring-stack.md

WSL2/Ubuntu 22.04 기반 devenv-observe 표준 레퍼런스입니다.

## 1) docker-compose 표준 (PHASE 5)

```yaml
version: "3.8"

services:
  prometheus:
    image: prom/prometheus:v2.53.0
    container_name: prometheus-${PROJECT_NAME}
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
      - --storage.tsdb.retention.time=30d
      - --storage.tsdb.retention.size=10GB
      - --web.enable-lifecycle
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    mem_limit: 2g
    networks: [devenv-monitoring, devenv-internal]

  alertmanager:
    image: prom/alertmanager:v0.27.0
    container_name: alertmanager-${PROJECT_NAME}
    command:
      - --config.file=/etc/alertmanager/alertmanager.yml
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
    mem_limit: 256m
    networks: [devenv-monitoring, devenv-internal]

  grafana:
    image: grafana/grafana:11.1.0
    container_name: grafana-${PROJECT_NAME}
    ports:
      - "3001:3000"
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD__FILE: /run/secrets/grafana_admin
      GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH: /var/lib/grafana/dashboards/devenv-overview.json
      GF_USERS_HOME_PAGE: /d/devenv-overview
    secrets:
      - grafana_admin
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - grafana-data:/var/lib/grafana
    mem_limit: 1g
    networks: [devenv-monitoring, devenv-internal]

  loki:
    image: grafana/loki:3.1.1
    container_name: loki-${PROJECT_NAME}
    ports:
      - "3100:3100"
    command: -config.file=/etc/loki/loki-config.yml
    volumes:
      - ./loki/loki-config.yml:/etc/loki/loki-config.yml:ro
      - loki-data:/loki
    mem_limit: 1g
    networks: [devenv-monitoring, devenv-internal]

  promtail:
    image: grafana/promtail:3.1.1
    container_name: promtail-${PROJECT_NAME}
    command: -config.file=/etc/promtail/promtail-config.yml
    volumes:
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./promtail/promtail-config.yml:/etc/promtail/promtail-config.yml:ro
      - promtail-positions:/tmp
    mem_limit: 256m
    networks: [devenv-monitoring, devenv-internal]

  node-exporter:
    image: prom/node-exporter:v1.8.1
    container_name: node-exporter-${PROJECT_NAME}
    pid: host
    restart: unless-stopped
    mem_limit: 128m
    networks: [devenv-monitoring, devenv-internal]

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.49.1
    container_name: cadvisor-${PROJECT_NAME}
    ports:
      - "8088:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:rw
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
    mem_limit: 512m
    networks: [devenv-monitoring, devenv-internal]

  skywalking-oap:
    image: apache/skywalking-oap-server:10.1.0
    container_name: skywalking-oap-${PROJECT_NAME}
    ports:
      - "11800:11800"
      - "12800:12800"
    environment:
      SW_STORAGE: h2
      JAVA_OPTS: "-Xms512m -Xmx1024m"
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:12800/healthcheck"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 90s
    mem_limit: 1500m
    networks: [devenv-monitoring, devenv-internal]

  skywalking-ui:
    image: apache/skywalking-ui:10.1.0
    container_name: skywalking-ui-${PROJECT_NAME}
    ports:
      - "8079:8080"
    environment:
      SW_OAP_ADDRESS: http://skywalking-oap-${PROJECT_NAME}:12800
    mem_limit: 512m
    networks: [devenv-monitoring, devenv-internal]

secrets:
  grafana_admin:
    file: ../config.env

volumes:
  prometheus-data:
  grafana-data:
  loki-data:
  promtail-positions:

networks:
  devenv-monitoring:
    name: devenv-monitoring
    driver: bridge
  devenv-internal:
    external: true
    name: devenv-internal
```

실행 시 project name은 반드시 명시합니다.

```bash
docker compose -p devenv-${PROJECT_NAME} -f docker-compose.yml up -d
```

## 2) prometheus.yml 핵심 예시

```yaml
global:
  scrape_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager-${PROJECT_NAME}:9093"]

# (선택) 알림 규칙 — rule_files 지정 시 해당 파일을 반드시 마운트할 것
# rule_files:
#   - /etc/prometheus/alerts.yml

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["prometheus-${PROJECT_NAME}:9090"]

  - job_name: jenkins
    metrics_path: /prometheus/
    static_configs:
      - targets: ["jenkins-${PROJECT_NAME}:8080"]

  - job_name: gitlab
    metrics_path: /-/metrics
    static_configs:
      - targets: ["gitlab-${PROJECT_NAME}:80"]

  - job_name: nexus
    metrics_path: /service/metrics/prometheus
    basic_auth:
      username: admin
      password: "<NEXUS_ADMIN_PASSWORD>"
    static_configs:
      - targets: ["nexus-${PROJECT_NAME}:8081"]

  - job_name: cadvisor
    static_configs:
      - targets: ["cadvisor-${PROJECT_NAME}:8080"]
    metric_relabel_configs:
      - regex: "container_label_.*"
        action: labeldrop
```

주의:
- Jenkins는 `/prometheus/` trailing slash 필수 (`/prometheus`는 302 redirect로 실패 가능).
- reload 200이어도 반영되지 않으면 `docker restart <prometheus-container>` 수행.

검증:

```bash
docker exec <prom> grep -A 3 '<new-job-name>' /etc/prometheus/prometheus.yml
curl -s http://localhost:9090/api/v1/targets?state=active | jq '.data.activeTargets[] | .labels.job' | sort -u
```

## 3) loki-config.yml 표준

```yaml
auth_enabled: false

server:
  http_listen_port: 3100

limits_config:
  allow_structured_metadata: true
  ingestion_rate_mb: 16

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  filesystem:
    directory: /loki/chunks
```

## 4) promtail-config.yml 표준

```yaml
server:
  http_listen_port: 9080

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki-${PROJECT_NAME}:3100/loki/api/v1/push

scrape_configs:
  - job_name: containers
    static_configs:
      - targets: [localhost]
        labels:
          service: unknown
          project: ${PROJECT_NAME}
          env: dev
          __path__: /var/lib/docker/containers/*/*.log
```

Promtail 라벨은 `service, project, env, container_name` 중심으로 최소화합니다.

## 5) Grafana healthcheck 표준

```bash
wget -qO- http://localhost:3000/api/health >/dev/null 2>&1 || exit 1
```

`"database":"ok"` 고정 문자열 grep은 공백 포맷 차이로 오탐이 발생할 수 있습니다.

## 6) GitLab exporter 설정 예시

```ruby
gitlab_rails['monitoring_whitelist'] = ['127.0.0.0/8', '10.0.1.0/24', '172.16.0.0/12']
gitlab_exporter['enable'] = true
gitlab_exporter['listen_address'] = '0.0.0.0'
gitlab_exporter['listen_port'] = 9168
gitlab_workhorse['prometheus_listen_addr'] = '0.0.0.0:9229'
```

## 7) SkyWalking Java agent 다운로드 표준

```bash
VER=9.2.0
curl -L -o sw.tgz https://archive.apache.org/dist/skywalking/java-agent/${VER}/apache-skywalking-java-agent-${VER}.tgz
tar xf sw.tgz
```

## 8) Grafana 대시보드 JSON 패칭

- grafana.com 원본 JSON의 `${DS_PROMETHEUS}`/`${DS_LOKI}` 입력 문제를 피하기 위해 사전 패칭합니다.
- 표준 스크립트: `references/dashboard-patcher.py`

```bash
python3 references/dashboard-patcher.py raw.json patched.json
```

## 9) Alertmanager 표준

- Alertmanager 설정은 `references/alertmanager-config.yml`를 사용합니다.
- 최소 receiver 2개(slack-default, email-default), severity route, inhibit_rules를 포함합니다.
