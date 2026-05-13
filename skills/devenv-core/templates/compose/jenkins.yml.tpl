# Jenkins LTS + JCasC (devenv-core)
# 알려진 이슈 대응:
#  - jenkins user 1000:<docker_gid> — 01-bootstrap.sh가 호스트 GID 감지 후 자동 패치
#  - JCasC: /var/jenkins_home/casc.yaml 자동 적용
#  - 플러그인 자동 설치: jenkins-plugin-cli + plugins.txt
#  - Docker CLI + Compose Plugin: 커스텀 Dockerfile로 빌드
services:
  jenkins:
    build:
      context: ../configs/jenkins
      dockerfile: Dockerfile
    image: jenkins-${PROJECT_NAME}:local
    container_name: jenkins-${PROJECT_NAME}
    user: "1000:DOCKER_GID_PLACEHOLDER"
    environment:
      TZ: "${TIMEZONE}"
      CASC_JENKINS_CONFIG: "/var/jenkins_home/casc.yaml"
      JAVA_OPTS: >-
        -Djenkins.install.runSetupWizard=false
        -Dhudson.security.csrf.DefaultCrumbIssuer.EXCLUDE_SESSION_ID=true
      # JCasC가 참조하는 환경변수 (jenkins.yaml에서 ${...}로 사용)
      PROJECT_NAME: "${PROJECT_NAME}"
      JENKINS_ADMIN_USER: "${JENKINS_ADMIN_USER}"
      JENKINS_ADMIN_PASSWORD: "${JENKINS_ADMIN_PASSWORD}"
      JENKINS_IP: "${JENKINS_IP}"
      GITLAB_IP: "${GITLAB_IP}"
      HOST_PORT_GITLAB: "${HOST_PORT_GITLAB}"
      NEXUS_IP: "${NEXUS_IP}"
      NEXUS_REGISTRY: "${NEXUS_REGISTRY}"
      NEXUS_ADMIN_PASSWORD: "${NEXUS_ADMIN_PASSWORD}"
      BASTION_IP: "${BASTION_IP}"
      # GITLAB_TOKEN은 post-install.sh에서 동적으로 주입
      GITLAB_TOKEN: "${GITLAB_TOKEN:-}"
    volumes:
      - jenkins_home:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
      - ../configs/jenkins/jenkins.yaml:/var/jenkins_home/casc.yaml:ro
      - ../configs/jenkins/plugins.txt:/usr/share/jenkins/ref/plugins.txt:ro
      - ../configs/jenkins/10-enforce-admin-user.groovy:/var/jenkins_home/init.groovy.d/10-enforce-admin-user.groovy:ro
    ports:
      - "${HOST_PORT_JENKINS}:8080"
      - "50000:50000"
    networks:
      - devenv-internal
    restart: unless-stopped
    mem_limit: ${JENKINS_MEM_LIMIT}
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:8080/login >/dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 10
      start_period: 240s
    security_opt:
      - no-new-privileges:true

volumes:
  jenkins_home:

networks:
  devenv-internal:
    external: true
