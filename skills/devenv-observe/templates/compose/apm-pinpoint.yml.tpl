# 자동 생성됨 — devenv-dev / APM (Pinpoint)
# ⚠️ Pinpoint는 HBase + ZooKeeper가 필요한 무거운 스택.
# 단일 서버 모드에서는 SkyWalking 권장 (기본값).
#
# 알려진 이슈 대응 (실제 설치 사례 기반):
# 1. zookeeper:3.7+ 단일노드 NPE 버그 → 3.4.13 사용
# 2. ZOO_SERVERS 설정 시 clientPort 누락 → 환경변수 자체를 제거
# 3. pinpoint-hbase 이미지가 zoo1,zoo2,zoo3 3노드 쿼럼 기대 → zoo1에 alias 추가
# 4. {YOUR_RELEASE_ZOOKEEPER_ADDRESS} 플레이스홀더 → CLUSTER_ZOOKEEPER_ADDRESS 명시
# 5. 기동 순서: zoo1 (20s) → hbase (180s) → collector → web
services:
  pinpoint-zookeeper:
    image: zookeeper:3.4.13
    container_name: pinpoint-zk-${PROJECT_NAME}
    hostname: zoo1
    environment:
      TZ: "${TIMEZONE}"
      ZOO_4LW_COMMANDS_WHITELIST: "*"
      # ZOO_SERVERS 설정 금지 (3.4.13 단일노드에서 clientPort 누락 이슈)
    networks:
      devenv-apm:
        aliases:
          - zoo1
          - zoo2
          - zoo3
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "echo ruok | nc -w 2 localhost 2181 | grep -q imok"]
      interval: 15s
      timeout: 5s
      retries: 10
      start_period: 30s

  pinpoint-hbase:
    image: pinpointdocker/pinpoint-hbase:2.5.3
    container_name: pinpoint-hbase-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
      HBASE_ZOOKEEPER_QUORUM: zoo1
    volumes:
      - hbase_data:/home/pinpoint/hbase
    depends_on:
      pinpoint-zookeeper:
        condition: service_healthy
    networks:
      - devenv-apm
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "echo 'status' | hbase shell 2>&1 | grep -q 'active master' || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 12
      start_period: 180s

  pinpoint-collector:
    image: pinpointdocker/pinpoint-collector:2.5.3
    container_name: pinpoint-collector-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
      CLUSTER_ENABLE: "true"
      CLUSTER_ZOOKEEPER_ADDRESS: zoo1
      HBASE_HOST: zoo1
    ports:
      - "9991:9991"
      - "9992:9992"
      - "9993:9993/udp"
      - "9994:9994"
      - "9995:9995/udp"
      - "9996:9996/udp"
    depends_on:
      pinpoint-hbase:
        condition: service_healthy
      pinpoint-zookeeper:
        condition: service_healthy
    networks:
      - devenv-apm
      - devenv-internal
    restart: unless-stopped

  pinpoint-web:
    image: pinpointdocker/pinpoint-web:2.5.3
    container_name: pinpoint-web-${PROJECT_NAME}
    environment:
      TZ: "${TIMEZONE}"
      CLUSTER_ENABLE: "true"
      CLUSTER_ZOOKEEPER_ADDRESS: zoo1
      PINPOINT_ZOOKEEPER_ADDRESS: zoo1
      HBASE_HOST: zoo1
      # 운영 기본 동선(수동): 로그인(admin/admin 기본 등 이미지 정책 확인) → Inspector / Scatter / Server Map
      # 기본 랜딩 커스터마이즈는 이미지 설정·DB 초기화가 필요 — references/multi-tool-operator-guide.md 참고
    ports:
      - "8079:8080"
    depends_on:
      pinpoint-hbase:
        condition: service_healthy
    networks:
      - devenv-apm
      - devenv-internal
    restart: unless-stopped

volumes:
  hbase_data:

networks:
  devenv-apm:
    external: true
  devenv-internal:
    external: true
