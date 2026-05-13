# 자동 생성됨 — devenv-dev / 로그 수집 (Grafana Loki)
# Grafana는 모니터링 스택의 grafana 컨테이너를 공유합니다 (Loki 데이터소스 추가).
# 운영자: 로그 분석 1차 화면은 Grafana의 Operator Cockpit — Logs 대시보드(uid: devenv-operator-cockpit-logs)
# Promtail 라벨(project, job, owner, log_format)로 Core 장애 시간대와 LogQL 필터를 맞추기 쉽게 함
services:
  x-default-logging: &default-logging
    driver: "json-file"
    options:
      max-size: "10m"
      max-file: "3"

  loki:
    image: grafana/loki:3.2.1
    container_name: loki-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
    command: -config.file=/etc/loki/local-config.yaml
    volumes:
      - ../configs/loki/loki-config.yml:/etc/loki/local-config.yaml:ro
      - loki_data:/loki
    ports:
      - "${HOST_PORT_LOKI}:3100"
    networks:
      - devenv-monitoring
      - devenv-internal
    restart: unless-stopped
    logging: *default-logging
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3100/ready"]
      interval: 30s
      timeout: 5s
      retries: 5

  promtail:
    image: grafana/promtail:3.2.1
    container_name: promtail-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
    command: -config.file=/etc/promtail/config.yml
    volumes:
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - ../configs/promtail/promtail-config.yml:/etc/promtail/config.yml:ro
    networks:
      - devenv-monitoring
    depends_on:
      - loki
    restart: unless-stopped
    logging: *default-logging

volumes:
  loki_data:

networks:
  devenv-monitoring:
    external: true
  devenv-internal:
    external: true
