# 자동 생성됨 — devenv-dev / Nexus Repository OSS
services:
  nexus:
    image: sonatype/nexus3:${NEXUS_VERSION}
    container_name: nexus-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
      INSTALL4J_ADD_VM_PARAMS: "-Xms1g -Xmx2g -XX:MaxDirectMemorySize=2g"
    volumes:
      - nexus_data:/nexus-data
    ports:
      - "${HOST_PORT_NEXUS_UI}:8081"
      - "${HOST_PORT_NEXUS_REGISTRY}:5000"
    networks:
      - devenv-internal
    restart: unless-stopped
    mem_limit: ${NEXUS_MEM_LIMIT}
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:8081/service/rest/v1/status || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 180s
    ulimits:
      nofile:
        soft: 65536
        hard: 65536

volumes:
  nexus_data:

networks:
  devenv-internal:
    external: true
