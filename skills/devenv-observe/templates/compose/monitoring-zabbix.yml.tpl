# 자동 생성됨 — devenv-dev / 모니터링 (Zabbix)
services:
  x-default-logging: &default-logging
    driver: "json-file"
    options:
      max-size: "10m"
      max-file: "3"

  zabbix-db:
    image: postgres:16-alpine
    container_name: zabbix-db-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
      POSTGRES_DB: zabbix
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: "${ZABBIX_DB_PASSWORD}"
    volumes:
      - zabbix_db_data:/var/lib/postgresql/data
    networks:
      - devenv-monitoring
    restart: unless-stopped
    logging: *default-logging
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U zabbix -d zabbix"]
      interval: 30s
      timeout: 5s
      retries: 5

  zabbix-server:
    image: zabbix/zabbix-server-pgsql:alpine-7.0.13
    container_name: zabbix-server-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
      DB_SERVER_HOST: zabbix-db
      POSTGRES_DB: zabbix
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: "${ZABBIX_DB_PASSWORD}"
    ports:
      - "10051:10051"
    depends_on:
      zabbix-db:
        condition: service_healthy
    networks:
      - devenv-monitoring
      - devenv-internal
    restart: unless-stopped
    logging: *default-logging
    healthcheck:
      test: ["CMD-SHELL", "nc -z localhost 10051 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 10

  zabbix-web:
    image: zabbix/zabbix-web-nginx-pgsql:alpine-7.0.13
    container_name: zabbix-web-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
      DB_SERVER_HOST: zabbix-db
      POSTGRES_DB: zabbix
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: "${ZABBIX_DB_PASSWORD}"
      ZBX_SERVER_HOST: zabbix-server
      # UI에 표시되는 서버 이름(가독성) — 기본 대시보드는 웹에서 사용자/역할별로 지정
      ZBX_SERVER_NAME: "Zabbix-${PROJECT_NAME}"
      PHP_TZ: "${TIMEZONE}"
    ports:
      - "8089:8080"
    depends_on:
      zabbix-server:
        condition: service_healthy
    networks:
      - devenv-monitoring
      - devenv-internal
    restart: unless-stopped
    logging: *default-logging
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:8080/ | grep -qi zabbix || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 10

volumes:
  zabbix_db_data:

networks:
  devenv-monitoring:
    external: true
  devenv-internal:
    external: true
