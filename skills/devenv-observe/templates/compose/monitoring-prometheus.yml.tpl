# 자동 생성됨 — devenv-dev / 모니터링 (Prometheus + Grafana)
services:
  x-default-logging: &default-logging
    driver: "json-file"
    options:
      max-size: "10m"
      max-file: "3"

  prometheus:
    image: prom/prometheus:v2.53.3
    container_name: prometheus-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
    volumes:
      - ../configs/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.retention.time=30d'
      - '--web.enable-lifecycle'
    ports:
      - "9090:9090"
    networks:
      - devenv-monitoring
      - devenv-internal
    restart: unless-stopped
    logging: *default-logging
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 5s
      retries: 5
    depends_on:
      - alertmanager

  alertmanager:
    image: prom/alertmanager:v0.27.0
    container_name: alertmanager-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
    volumes:
      - ../configs/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
    ports:
      - "9093:9093"
    networks:
      - devenv-monitoring
      - devenv-internal
    restart: unless-stopped
    logging: *default-logging
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:9093/-/healthy"]
      interval: 30s
      timeout: 5s
      retries: 5

  grafana:
    image: grafana/grafana:11.2.0
    container_name: grafana-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: "${GRAFANA_PASSWORD}"
      GF_USERS_ALLOW_SIGN_UP: "false"
      GF_AUTH_ANONYMOUS_ENABLED: "false"
      # 홈 대시보드 3중 고정: 파일 경로 + 라우트 + API(org/user) — phase-playbook Grafana 절 참고
      GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH: /var/lib/grafana/dashboards/devenv-overview.json
      GF_USERS_HOME_PAGE: /d/devenv-overview
    volumes:
      - grafana_data:/var/lib/grafana
      - ../configs/grafana/provisioning:/etc/grafana/provisioning:ro
      - ../configs/grafana/dashboards:/var/lib/grafana/dashboards:ro
    ports:
      - "3001:3000"
    networks:
      - devenv-monitoring
      - devenv-internal
    depends_on:
      - prometheus
    restart: unless-stopped
    logging: *default-logging
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:3000/api/health | grep -q ok || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 5

  node-exporter:
    image: prom/node-exporter:v1.8.2
    container_name: node-exporter-${PROJECT_NAME}
    pid: host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    ports:
      - "9100:9100"
    networks:
      - devenv-monitoring
    restart: unless-stopped
    logging: *default-logging

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.49.1
    container_name: cadvisor-${PROJECT_NAME}
    privileged: true
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    ports:
      - "8088:8080"
    networks:
      - devenv-monitoring
    restart: unless-stopped
    logging: *default-logging

volumes:
  prometheus_data:
  grafana_data:

networks:
  devenv-monitoring:
    external: true
  devenv-internal:
    external: true
