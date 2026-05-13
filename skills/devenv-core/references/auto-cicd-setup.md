# 자동 CI/CD 연동 (Auto CI/CD Setup) — ★ 3-repo 분리 배포

설치 완료 후 `scripts/post-install.sh`가 자동 실행하는 작업 흐름을 설명합니다.

샘플 앱은 **backend/frontend/admin 3개 독립 repo + 3개 독립 Jenkins job**으로 구성됩니다.

---

## 전체 흐름

```
[install-all.sh 종료]
        │
        ▼
[post-install.sh 자동 실행]
        │
        ├── 1. GitLab root 토큰 발급 (Rails 콘솔)
        ├── 2. GitLab 그룹 생성 ({project_name})
        ├── 3. 그룹 아래 3개 프로젝트 생성 + 각각 push:
        │       - {project_name}/backend  ← sample-apps/backend/
        │       - {project_name}/frontend ← sample-apps/frontend/
        │       - {project_name}/admin    ← sample-apps/admin/
        ├── 4. SonarQube 토큰 발급
        ├── 5. Nexus 비밀번호 자동 추출 + Docker hosted repo 생성
        ├── 6. Jenkins JCasC 동적 갱신 (token 주입) → 3개 잡 자동 등록
        ├── 7. GitLab → Jenkins Webhook 3개 등록 (repo별)
        ├── 8. 3개 첫 빌드 동시 트리거
        └── 9. 3개 빌드 결과 모니터링 + URL/상태 출력
```

---

## 1. GitLab root 토큰 발급

GitLab compose의 `GITLAB_OMNIBUS_CONFIG`에 `initial_root_password`를 주입했지만,
API 호출에는 personal access token이 필요합니다. Rails 콘솔에서 자동 발급:

```ruby
# configs/gitlab/init-token.rb
user = User.find_by(username: 'root')
token = user.personal_access_tokens.create!(
  scopes: [:api, :read_user, :read_repository, :write_repository, :sudo],
  name: 'devenv-bootstrap',
  expires_at: 1.year.from_now
)
puts "TOKEN=#{token.token}"
```

post-install.sh가 이 출력을 capture하여 환경변수로 사용.

---

## 2. GitLab root 계정 안전 생성 (이슈 6 대응)

`initial_root_password`만으로 작동하지 않는 경우(GitLab 재초기화 등)를 위한 폴백:

```ruby
# configs/gitlab/init-root.rb
# 알려진 이슈 대응:
# 1. 비밀번호에 'gitlab' 단어 포함 금지 정책
# 2. Namespace can't be blank — namespace 자동 생성 안됨
# 3. password reset이 root 미존재 상태에서 실패

require 'devise'

# root 유저 존재 확인
existing = User.find_by(username: 'root')
if existing.nil?
  user = User.new(
    username: 'root',
    name: 'Administrator',
    email: 'admin@example.com',
    password: ENV['GITLAB_ROOT_PASSWORD'],
    password_confirmation: ENV['GITLAB_ROOT_PASSWORD'],
    admin: true,
    confirmed_at: Time.now
  )
  user.skip_reconfirmation!
  user.save!(validate: false)   # namespace 검증 우회
  
  # namespace 강제 생성
  ns = Namespace.find_by(path: 'root')
  unless ns
    Namespace.create!(name: 'root', path: 'root', owner_id: user.id)
  end
  
  puts "ROOT_CREATED=true"
else
  existing.update!(password: ENV['GITLAB_ROOT_PASSWORD'])
  puts "ROOT_PASSWORD_RESET=true"
end
```

호출:
```bash
docker exec -e GITLAB_ROOT_PASSWORD="${GITLAB_ROOT_PASSWORD}" \
  -i gitlab-${PROJECT_NAME} \
  gitlab-rails runner - < configs/gitlab/init-root.rb
```

---

## 3. 그룹 + 3개 샘플 프로젝트 생성 (GitLab API)

```bash
# 그룹 생성 (1회)
curl -sS --request POST \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  --form "name=${PROJECT_NAME}" \
  --form "path=${PROJECT_NAME}" \
  --form "visibility=private" \
  "http://${GITLAB_IP}:${HOST_PORT_GITLAB}/api/v4/groups"

# 각 repo(backend/frontend/admin)별로 반복:
for repo in backend frontend admin; do
  curl -sS --request POST \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    --form "name=${repo}" \
    --form "namespace_id=${GROUP_ID}" \
    --form "visibility=private" \
    --form "initialize_with_readme=false" \
    "http://${GITLAB_IP}:${HOST_PORT_GITLAB}/api/v4/projects"
done
```

각 응답에서 `id`(=PROJECT_ID)를 PROJECT_IDS 연관 배열에 저장하여
이후 webhook 등록과 빌드 트리거에 사용.

---

## 4. 샘플 앱 push (3개 동시)

```bash
for repo in backend frontend admin; do
  cd "sample-apps/${repo}"
  git init
  git config user.email "admin@${PROJECT_NAME}.local"
  git config user.name "devenv-bootstrap"

  # HTTP push (Personal Access Token 사용)
  REPO_URL="http://root:${GITLAB_TOKEN}@localhost:${HOST_PORT_GITLAB}/${PROJECT_NAME}/${repo}.git"
  git remote add origin "${REPO_URL}"
  git checkout -b main
  git add .
  git commit -m "Initial commit from devenv-dev (${repo})"
  git push -u origin main
  cd -
done
```

---

## 5. Nexus 비밀번호 자동 추출 (이슈 7 대응)

```bash
# Nexus 첫 기동 시 자동 비밀번호 생성됨
NEXUS_INIT_PW=$(docker exec nexus-${PROJECT_NAME} cat /nexus-data/admin.password 2>/dev/null)

# Script API로 admin 비밀번호를 config.env의 NEXUS_ADMIN_PASSWORD로 변경
curl -sS -u "admin:${NEXUS_INIT_PW}" \
  -X PUT "http://${NEXUS_IP}:8081/service/rest/v1/security/users/admin/change-password" \
  -H "Content-Type: text/plain" \
  -d "${NEXUS_ADMIN_PASSWORD}"

# Docker hosted repository 자동 생성
curl -sS -u "admin:${NEXUS_ADMIN_PASSWORD}" \
  -X POST "http://${NEXUS_IP}:8081/service/rest/v1/repositories/docker/hosted" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "docker-hosted",
    "online": true,
    "storage": {"blobStoreName":"default","strictContentTypeValidation":true,"writePolicy":"ALLOW"},
    "docker": {"v1Enabled":false,"forceBasicAuth":true,"httpPort":5000}
  }'
```

---

## 6. SonarQube 토큰 발급

```bash
# 첫 로그인 시 admin/admin → 새 비밀번호로 변경
curl -sS -u "admin:admin" \
  -X POST "http://${SECURITY_IP}:9000/api/users/change_password" \
  -d "login=admin&previousPassword=admin&password=${SONAR_ADMIN_PASSWORD}"

# 토큰 발급
SONAR_TOKEN=$(curl -sS -u "admin:${SONAR_ADMIN_PASSWORD}" \
  -X POST "http://${SECURITY_IP}:9000/api/user_tokens/generate" \
  -d "name=jenkins-bootstrap" | jq -r '.token')

# Webhook 등록 (Jenkins로 결과 전달)
curl -sS -u "admin:${SONAR_ADMIN_PASSWORD}" \
  -X POST "http://${SECURITY_IP}:9000/api/webhooks/create" \
  -d "name=jenkins&url=http://${JENKINS_IP}:8080/sonarqube-webhook/"
```

---

## 7. Jenkins JCasC 자동 설정

`configs/jenkins/jenkins.yaml`이 JCasC 설정. 환경변수 `${...}` 부분이 컨테이너 시작 시 자동 치환됩니다.

```yaml
# 핵심 부분만 발췌
jenkins:
  systemMessage: "devenv-${PROJECT_NAME} 자동 구성"
  numExecutors: 4
  securityRealm:
    local:
      allowsSignup: false
      users:
        - id: "${JENKINS_ADMIN_USER}"
          password: "${JENKINS_ADMIN_PASSWORD}"
  authorizationStrategy:
    loggedInUsersCanDoAnything:
      allowAnonymousRead: false

credentials:
  system:
    domainCredentials:
      - credentials:
          - usernamePassword:
              scope: GLOBAL
              id: "gitlab-credentials"
              username: "root"
              password: "${GITLAB_TOKEN}"
              description: "GitLab Personal Access Token"
          - usernamePassword:
              scope: GLOBAL
              id: "nexus-credentials"
              username: "admin"
              password: "${NEXUS_ADMIN_PASSWORD}"
              description: "Nexus Repository"
          - string:
              scope: GLOBAL
              id: "sonarqube-token"
              secret: "${SONAR_TOKEN}"
              description: "SonarQube Auth Token"

unclassified:
  gitLabConnectionConfig:
    connections:
      - name: "gitlab-${PROJECT_NAME}"
        url: "http://${GITLAB_IP}:${HOST_PORT_GITLAB}"
        apiTokenId: "gitlab-credentials"
        clientBuilderId: "autodetect"
  sonarGlobalConfiguration:
    installations:
      - name: "SonarQube"
        serverUrl: "http://${SECURITY_IP}:9000"
        credentialsId: "sonarqube-token"

jobs:
  # 3개 pipelineJob을 자동 등록 (각 repo별)
  - script: |
      pipelineJob('${PROJECT_NAME}-backend') {
        properties { gitLabConnectionProperty { gitLabConnection('gitlab-${PROJECT_NAME}') } }
        definition { cpsScm { scm { git {
          remote {
            url 'http://gitlab-${PROJECT_NAME}:80/${PROJECT_NAME}/backend.git'
            credentials 'gitlab-credentials'
          }
          branch '*/main'
        } } scriptPath 'Jenkinsfile' } }
      }
  - script: |
      pipelineJob('${PROJECT_NAME}-frontend') { /* frontend.git, Jenkinsfile */ }
  - script: |
      pipelineJob('${PROJECT_NAME}-admin')    { /* admin.git, Jenkinsfile */ }
```

각 잡의 SCM URL은 컨테이너명(`gitlab-${PROJECT_NAME}:80`)을 사용해야 Jenkins 컨테이너 내부에서 GitLab 접근 가능 (호스트IP 사용 시 라우팅 불가).

JCasC는 컨테이너 재시작 시 자동 적용. 환경변수가 변경되면 재시작 → 재구성.

---

## 8. GitLab Webhook 등록 (3개)

각 repo마다 해당 Jenkins 잡 URL로 webhook 등록:

```bash
for repo in backend frontend admin; do
  PID="${PROJECT_IDS[${repo}]}"
  WEBHOOK_URL="http://${JENKINS_IP}:8080/project/${PROJECT_NAME}-${repo}"

  curl -sS --request POST \
    --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    --form "url=${WEBHOOK_URL}" \
    --form "push_events=true" \
    --form "merge_requests_events=true" \
    --form "tag_push_events=true" \
    "http://${GITLAB_IP}:${HOST_PORT_GITLAB}/api/v4/projects/${PID}/hooks"
done
```

**중요**: webhook URL의 잡명은 JCasC에 등록된 잡명과 정확히 일치해야 합니다 (`${PROJECT_NAME}-${repo}`).

---

## 9. 첫 빌드 확인 (3개 잡 동시 모니터링)

각 repo의 push가 끝나면 webhook이 트리거되어 Jenkins가 3개 빌드를 동시에 시작합니다.
post-install.sh는 모든 잡을 한 루프에서 함께 모니터링하며, 끝난 잡은 결과를 고정하고 남은 잡만 계속 폴링합니다.

```bash
declare -A BUILD_RESULTS=()
for i in $(seq 1 60); do
  REMAINING=0
  for repo in backend frontend admin; do
    [[ -n "${BUILD_RESULTS[${repo}]:-}" ]] && continue   # 이미 결과 확정

    JOB="${PROJECT_NAME}-${repo}"
    INFO=$(curl -sS -u "${JENKINS_ADMIN_USER}:${JENKINS_ADMIN_PASSWORD}" \
      "http://${JENKINS_IP}:8080/job/${JOB}/lastBuild/api/json" 2>/dev/null || echo "{}")
    RESULT=$(echo "${INFO}" | jq -r '.result // "RUNNING"')
    case "${RESULT}" in
      SUCCESS)                  BUILD_RESULTS["${repo}"]="✅" ;;
      FAILURE|UNSTABLE|ABORTED) BUILD_RESULTS["${repo}"]="❌${RESULT}" ;;
      *)                        REMAINING=$((REMAINING+1)) ;;
    esac
  done
  [[ ${REMAINING} -eq 0 ]] && break
  sleep 10
done
```

타임아웃(10분) 시 미완료된 잡은 `⏱TIMEOUT`으로 표기하고 콘솔 URL을 안내합니다.

---

## 10. 결과 출력

post-install.sh 마지막에 사용자에게 안내 (3-repo 분리 형태):

```
==========================================
✅ CI/CD 자동 연동 완료
==========================================
🚀 샘플 앱 (3-repo 분리 배포):
  ┌─ Backend
  │   GitLab repo: http://10.0.1.10:8082/myproject/backend
  │   Jenkins job: http://10.0.1.10:8080/job/myproject-backend/
  │   배포: http://10.0.1.21:8083/health
  ├─ Frontend
  │   GitLab repo: http://10.0.1.10:8082/myproject/frontend
  │   Jenkins job: http://10.0.1.10:8080/job/myproject-frontend/
  │   배포: http://10.0.1.22:3000
  └─ Admin
      GitLab repo: http://10.0.1.10:8082/myproject/admin
      Jenkins job: http://10.0.1.10:8080/job/myproject-admin/
      배포: http://10.0.1.23:3100

다음 명령으로 개별 잡을 수동 트리거할 수 있습니다:
  curl -X POST http://10.0.1.10:8080/job/myproject-backend/build  -u admin:<PW>
  curl -X POST http://10.0.1.10:8080/job/myproject-frontend/build -u admin:<PW>
  curl -X POST http://10.0.1.10:8080/job/myproject-admin/build    -u admin:<PW>

GitLab 코드 클론 (3개 repo):
  git clone http://root:<TOKEN>@10.0.1.10:8082/myproject/backend.git
  git clone http://root:<TOKEN>@10.0.1.10:8082/myproject/frontend.git
  git clone http://root:<TOKEN>@10.0.1.10:8082/myproject/admin.git
==========================================
```

---

## 트러블슈팅

### post-install.sh가 GitLab API 호출 실패
- GitLab이 완전히 기동했는지 확인 (5~10분 소요)
- `docker logs gitlab-${PROJECT_NAME} | grep -i ready`
- `/-/health`는 마이그레이션 중에도 200을 반환하므로 신뢰 불가 → `/users/sign_in`으로 확인

### 일부 repo만 push 실패
- 3개 repo 중 1~2개만 실패하는 경우, post-install.sh는 나머지 진행을 계속합니다
- 실패한 repo만 수동 push:
  ```bash
  cd sample-apps/<repo>     # backend / frontend / admin
  git remote -v             # origin 확인
  git push -u origin main
  ```

### Jenkins 잡이 3개 모두 등록되지 않음
- `docker exec jenkins-${PROJECT_NAME} ls /var/jenkins_home/casc.yaml` 확인
- Jenkins 로그: `docker logs jenkins-${PROJECT_NAME} | grep -i casc`
- JCasC 부팅 실패 시 잡이 1개도 등록 안 됨 → jenkins.yaml의 들여쓰기/문법 점검
- Jenkins UI → Manage Jenkins → Configuration as Code → Reload existing configuration

### Webhook이 일부 잡만 트리거함
- 각 repo의 webhook URL이 `…/project/${PROJECT_NAME}-${repo}` 형태인지 확인
- GitLab → Project → Settings → Webhooks → 우측 "Test" 버튼으로 수동 테스트
- "URL is blocked" 오류 시: GitLab admin → Settings → Network → "Allow requests to the local network from web hooks" 활성화 (post-install.sh가 자동 처리)

### Frontend / Admin 빌드는 성공했는데 컨테이너가 뜨지 않음
- 사전 기동된 placeholder 컨테이너(`frontend-${PROJECT_NAME}`, `admin-${PROJECT_NAME}`)와 충돌 가능
- Jenkinsfile의 Deploy Dev 단계가 기존 컨테이너를 stop/rm 후 새로 run하므로 보통 자동 해결됨
- 그래도 안 되면: `docker ps -a | grep ${PROJECT_NAME}` → 수동 정리 후 잡 재실행

### 첫 빌드가 SonarQube 단계에서 멈춤
- SonarQube webhook이 등록되었는지 확인 (`/api/webhooks/list`)
- 5분 timeout 안에 응답이 없으면 abortPipeline 발동

### Frontend와 Admin 이미지가 같은 결과를 만드는 것 같음
- 정상입니다. 두 repo는 같은 Frontend 템플릿에서 출발하지만, **Git/Jenkins/이미지/컨테이너가 분리**되어 있어 이후 독립적으로 발전합니다
- Admin의 코드를 수정해서 push하면 admin Jenkins job만 동작하고 admin 컨테이너만 교체됩니다
