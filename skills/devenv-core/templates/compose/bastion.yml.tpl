# 자동 생성됨 — devenv-dev / Bastion Host
# 단순 SSH 점프 호스트. 컨테이너로 운영하는 것이 아닌 호스트 OS에 직접 SSH를 운영하는 구성도 가능.
# 이 compose는 컨테이너 기반 Bastion 옵션을 제공합니다.

services:
  bastion:
    image: linuxserver/openssh-server:latest
    container_name: bastion-${PROJECT_NAME}
    hostname: bastion
    environment:
      PUID: "1000"
      PGID: "1000"
      TZ: "${TIMEZONE}"
      PASSWORD_ACCESS: "false"
      USER_NAME: devops
      PUBLIC_KEY_DIR: /config/.ssh/keys
      LOG_STDOUT: "true"
    volumes:
      - bastion_config:/config
      - ./bastion/keys:/config/.ssh/keys:ro
    ports:
      # ${HOST_PORT_BASTION_SSH}는 단일서버 모드에서 2222로 자동 조정됨 (호스트 sshd:22 충돌 회피)
      - "${HOST_PORT_BASTION_SSH}:2222"
    networks:
      - devenv-internal
    restart: unless-stopped
    mem_limit: ${BASTION_MEM_LIMIT}
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "2222"]
      interval: 30s
      timeout: 5s
      retries: 3

volumes:
  bastion_config:

networks:
  devenv-internal:
    external: true
