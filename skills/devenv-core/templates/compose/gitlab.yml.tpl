# GitLab CE (devenv-core)
# 포트 정책:
#   HTTP: HOST_PORT_GITLAB → 80      (단일 서버: 8082, 다중: 80)
#   SSH : HOST_PORT_GITLAB_SSH → 22  (Bastion이 2222를 점유하므로 GitLab은 2223)
# external_url과 nginx['listen_port']는 모두 80 — 컨테이너 내부 기준으로만 통일.
services:
  gitlab:
    image: gitlab/gitlab-ce:${GITLAB_VERSION}
    container_name: gitlab-${PROJECT_NAME}
    hostname: gitlab
    environment:
      TZ: "${TIMEZONE}"
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'http://${GITLAB_IP}:${HOST_PORT_GITLAB}'
        gitlab_rails['gitlab_signup_enabled'] = false
        gitlab_rails['time_zone'] = '${TIMEZONE}'
        gitlab_rails['gitlab_shell_ssh_port'] = ${HOST_PORT_GITLAB_SSH}
        gitlab_rails['initial_root_password'] = '${GITLAB_ROOT_PASSWORD}'
        gitlab_rails['initial_root_email'] = '${GITLAB_ROOT_EMAIL}'
        nginx['listen_port'] = 80
        nginx['listen_https'] = false
        prometheus_monitoring['enable'] = false
    volumes:
      - gitlab_config:/etc/gitlab
      - gitlab_logs:/var/log/gitlab
      - gitlab_data:/var/opt/gitlab
    ports:
      - "${HOST_PORT_GITLAB}:80"
      - "${HOST_PORT_GITLAB_SSH}:22"
    networks:
      - devenv-internal
    restart: unless-stopped
    mem_limit: ${GITLAB_MEM_LIMIT}
    shm_size: '256m'
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost/-/health"]
      interval: 60s
      timeout: 30s
      retries: 5
      start_period: 600s

volumes:
  gitlab_config:
  gitlab_logs:
  gitlab_data:

networks:
  devenv-internal:
    external: true
