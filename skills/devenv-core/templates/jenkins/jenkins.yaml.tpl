# Jenkins Configuration as Code (JCasC) — devenv-core 범위
# 마운트: /var/jenkins_home/casc.yaml (시작 시 자동 적용)
# 환경변수 ${VAR}는 Jenkins 컨테이너 env에서 주입됨
#
# 이 파일은 devenv-core가 책임지는 "기반 설정"만 정의합니다.
#  - 사용자 계정 / 권한
#  - GitLab 연결 + 토큰
#  - Nexus 자격증명
# 앱별 잡(backend/frontend/admin) 등록은 devenv-app에서 수행합니다.
jenkins:
  systemMessage: "devenv-${PROJECT_NAME}"
  numExecutors: 4
  mode: NORMAL
  scmCheckoutRetryCount: 3

  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: "${JENKINS_ADMIN_USER}"
          password: "${JENKINS_ADMIN_PASSWORD}"

  authorizationStrategy:
    loggedInUsersCanDoAnything:
      allowAnonymousRead: false

  globalNodeProperties:
    - envVars:
        env:
          - key: "PROJECT_NAME"
            value: "${PROJECT_NAME}"
          - key: "NEXUS_REGISTRY"
            value: "${NEXUS_REGISTRY}"
          - key: "GITLAB_IP"
            value: "${GITLAB_IP}"
          - key: "GITLAB_PORT"
            value: "${HOST_PORT_GITLAB}"
          - key: "BASTION_IP"
            value: "${BASTION_IP}"

credentials:
  system:
    domainCredentials:
      - credentials:
          - usernamePassword:
              scope: GLOBAL
              id: "gitlab-credentials"
              username: "root"
              password: "${GITLAB_TOKEN}"
              description: "GitLab — Username/Password (clone/push)"
          - string:
              scope: GLOBAL
              id: "gitlab-token"
              secret: "${GITLAB_TOKEN}"
              description: "GitLab Personal Access Token (REST API)"
          - string:
              scope: GLOBAL
              id: "gitlab-api-token"
              secret: "${GITLAB_TOKEN}"
              description: "GitLab API Token — gitlab-plugin"
          - usernamePassword:
              scope: GLOBAL
              id: "nexus-credentials"
              username: "admin"
              password: "${NEXUS_ADMIN_PASSWORD}"
              description: "Nexus Repository"

unclassified:
  location:
    url: "http://${JENKINS_IP}:8080/"
    adminAddress: "admin@${PROJECT_NAME}.local"

  gitLabConnectionConfig:
    connections:
      - name: "gitlab-${PROJECT_NAME}"
        # 컨테이너 간 통신: 컨테이너명:내부포트 사용 (호스트 IP/localhost는 컨테이너 내부에서 라우팅 불가)
        url: "http://gitlab-${PROJECT_NAME}:80"
        apiTokenId: "gitlab-api-token"
        clientBuilderId: "autodetect"
        connectionTimeout: 10
        readTimeout: 10
        ignoreCertificateErrors: false

tool:
  git:
    installations:
      - name: Default
        home: "git"
