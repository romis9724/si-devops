# 자동 생성됨 — devenv-dev / APM (SkyWalking)
services:
  skywalking-storage:
    image: elasticsearch:8.11.0
    container_name: sw-es-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
      discovery.type: single-node
      xpack.security.enabled: "false"
      ES_JAVA_OPTS: "-Xms1g -Xmx1g"
    volumes:
      - sw_es_data:/usr/share/elasticsearch/data
    networks:
      - devenv-apm
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:9200/_cluster/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 10
      start_period: 90s

  skywalking-oap:
    image: apache/skywalking-oap-server:10.1.0
    container_name: sw-oap-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
      SW_STORAGE: elasticsearch
      SW_STORAGE_ES_CLUSTER_NODES: skywalking-storage:9200
      JAVA_OPTS: "-Xms512m -Xmx1g"
    ports:
      - "11800:11800"
      - "12800:12800"
    depends_on:
      skywalking-storage:
        condition: service_healthy
    networks:
      - devenv-apm
      - devenv-internal
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:12800/healthcheck || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 10
      start_period: 60s

  skywalking-ui:
    image: apache/skywalking-ui:10.1.0
    container_name: sw-ui-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
      SW_OAP_ADDRESS: http://skywalking-oap:12800
      # 운영 기본 동선(수동): General Service → Service Topology / Trace / Log — UI는 별도 로그인 없음
      # Grafana Operator Cockpit과 병행 시: 메트릭·스크레이프는 Grafana, 트레이스·서비스맵은 여기서 확인
    ports:
      - "8079:8080"
    depends_on:
      skywalking-oap:
        condition: service_healthy
    networks:
      - devenv-apm
      - devenv-internal
    restart: unless-stopped

volumes:
  sw_es_data:

networks:
  devenv-apm:
    external: true
  devenv-internal:
    external: true
