# 자동 생성됨 — devenv-dev / APM (Elastic APM)
# 로그 스택이 ELK일 경우 동일 ES를 공유할 수도 있습니다.
# 운영자: 트레이스·서비스 UI는 Kibana의 APM 앱 — http://<KIBANA>:5601/app/apm (ELK와 함께 켠 경우)
# 수집만 이 compose일 때는 Grafana Operator Cockpit으로 인프라를 보고, APM UI는 Kibana 구성 후 사용
services:
  apm-server:
    image: docker.elastic.co/apm/apm-server:8.11.0
    container_name: apm-server-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
    command: >
      apm-server -e
        -E apm-server.host=0.0.0.0:8200
        -E output.elasticsearch.hosts=["${LOGGING_IP}:9200"]
        -E output.elasticsearch.username=elastic
        -E output.elasticsearch.password=${ELASTIC_PASSWORD}
    ports:
      - "8200:8200"
    networks:
      - devenv-apm
      - devenv-internal
    restart: unless-stopped

networks:
  devenv-apm:
    external: true
  devenv-internal:
    external: true
