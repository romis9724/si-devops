# 자동 생성됨 — devenv-dev / 로그 수집 (ELK)
services:
  elasticsearch:
    image: elasticsearch:8.11.0
    container_name: es-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
      discovery.type: single-node
      xpack.security.enabled: "true"
      ELASTIC_PASSWORD: "${ELASTIC_PASSWORD}"
      ES_JAVA_OPTS: "-Xms2g -Xmx2g"
    volumes:
      - es_data:/usr/share/elasticsearch/data
    ports:
      - "9200:9200"
    networks:
      - devenv-logging
      - devenv-internal
    restart: unless-stopped
    ulimits:
      memlock:
        soft: -1
        hard: -1
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS -u elastic:${ELASTIC_PASSWORD} http://localhost:9200/_cluster/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 10
      start_period: 60s

  logstash:
    image: logstash:8.11.0
    container_name: logstash-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
      LS_JAVA_OPTS: "-Xms512m -Xmx512m"
      ELASTIC_PASSWORD: "${ELASTIC_PASSWORD}"
    volumes:
      - logstash_pipeline:/usr/share/logstash/pipeline
    ports:
      - "5044:5044"
      - "5000:5000"
    depends_on:
      elasticsearch:
        condition: service_healthy
    networks:
      - devenv-logging
      - devenv-internal
    restart: unless-stopped

  kibana:
    image: kibana:8.11.0
    container_name: kibana-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
      ELASTICSEARCH_HOSTS: http://elasticsearch:9200
      ELASTICSEARCH_USERNAME: kibana_system
      ELASTICSEARCH_PASSWORD: "${KIBANA_PASSWORD}"
    ports:
      - "5601:5601"
    depends_on:
      elasticsearch:
        condition: service_healthy
    networks:
      - devenv-logging
      - devenv-internal
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:5601/api/status || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 10
      start_period: 60s

volumes:
  es_data:
  logstash_pipeline:

networks:
  devenv-logging:
    external: true
  devenv-internal:
    external: true
