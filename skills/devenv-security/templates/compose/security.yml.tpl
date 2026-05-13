# 자동 생성됨 — devenv-dev / 보안점검 서버
# pre-app/post-app 모두 동일한 보안 인프라를 사용하며,
# app 병합 여부는 compose가 아닌 상위 오케스트레이션(PHASE 7)에서 분기한다.
services:
  sonarqube:
    image: sonarqube:community
    container_name: sonarqube-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
      SONAR_SEARCH_JAVAADDITIONALOPTS: "-Dnode.store.allow_mmap=false"
      SONAR_JDBC_URL: jdbc:postgresql://sonar-db:5432/sonarqube
      SONAR_JDBC_USERNAME: sonar
      SONAR_JDBC_PASSWORD: "${SONAR_ADMIN_PASSWORD}"
    volumes:
      - sonar_data:/opt/sonarqube/data
      - sonar_logs:/opt/sonarqube/logs
      - sonar_extensions:/opt/sonarqube/extensions
      - sonar_cache:/opt/sonarqube/.sonar/cache
    ports:
      - "${SONAR_PORT:-9000}:9000"
    depends_on:
      sonar-db:
        condition: service_healthy
    networks:
      - devenv-internal
      - devenv-security
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:9000/api/system/status | grep -q UP || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 10
      start_period: 180s
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    deploy:
      resources:
        limits:
          cpus: "1.5"
          memory: 4G

  sonar-db:
    image: postgres:15-alpine
    container_name: sonar-db-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
      POSTGRES_USER: sonar
      POSTGRES_PASSWORD: "${SONAR_ADMIN_PASSWORD}"
      POSTGRES_DB: sonarqube
    volumes:
      - sonar_db:/var/lib/postgresql/data
    networks:
      - devenv-security
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U sonar -d sonarqube"]
      interval: 15s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          memory: 1G

  # OWASP ZAP은 데몬 모드 + API 노출
  # SECURITY_ZAP=n인 환경에서는 install-security.sh가 이 서비스를 stop 처리
  zap:
    # softwaresecurityproject/* publish 중단 — Docker Hub 고정 태그만 사용
    image: zaproxy/zap-stable:2.17.0
    container_name: zap-${PROJECT_NAME}
    command: zap.sh -daemon -host 0.0.0.0 -port 8090 -config api.disablekey=true -config api.addrs.addr.name=.* -config api.addrs.addr.regex=true
    ports:
      - "${ZAP_PORT:-8090}:8090"
    networks:
      - devenv-internal
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    profiles:
      - zap
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:8090/JSON/core/view/version/ || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 60s
    deploy:
      resources:
        limits:
          memory: 1G

volumes:
  sonar_data:
  sonar_logs:
  sonar_extensions:
  sonar_db:
  sonar_cache:
  # dependency-check 데이터 캐시 볼륨(기본은 Jenkins plugin 사용, 필요 시 확장 compose에서 mount)
  dep_check_data:

networks:
  devenv-internal:
    external: true
  devenv-security:
    external: true
