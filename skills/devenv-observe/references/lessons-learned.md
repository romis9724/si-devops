# Lessons Learned — Real Deployment Insights

이 문서는 실제 배포 과정에서 발견된 **non-obvious 함정과 검증된 해결 패턴**을 정리한 것입니다. SKILL.md/scripts에 기본 처리되어 있어도 스킬을 적용할 때 마주칠 수 있는 실제 케이스를 미리 알아둘 가치가 있습니다.

---

## 1. WSL2 / Windows / Docker

### 1-1. systemd `--user` 단위는 docker 그룹을 상속받지 못한다

**증상**: `setup-docker-wsl.sh`로 docker 설치 후 `usermod -aG docker $USER` 했는데도, `systemd-run --user --unit=...` 로 실행한 unit 안에서 `permission denied while trying to connect to the docker API at unix:///var/run/docker.sock`.

**원인**: WSL의 systemd user manager는 사용자 로그인 시점에 시작되며, 이후 추가된 supplementary group은 user manager를 통해 시작되는 자식 프로세스에 전파되지 않습니다.

**해결**: 실행할 스크립트 첫 부분에 `sg docker` self re-exec를 넣습니다.

```bash
#!/usr/bin/env bash
if [[ -z "${IN_DOCKER_GROUP:-}" ]]; then
  export IN_DOCKER_GROUP=1
  exec sg docker -c "IN_DOCKER_GROUP=1 bash '$0' $*"
fi
set -euo pipefail
# ... 본 스크립트 ...
```

또는 systemd-run을 호출하는 외부 셸에서 `sg docker -c 'systemd-run --user ...'` 형태로 감싸는 것은 효과 없음 — 자식 unit이 그룹을 다시 잃습니다. 반드시 unit이 실행하는 스크립트 자체에서 sg를 적용하세요.

### 1-2. Git Bash (MSYS) 가 `/mnt/c` 경로를 자동 변환

**증상**: Monitor 도구 등에서 `wsl -d Ubuntu -- bash /mnt/c/...sh` 호출 시 `bash: C:/Program Files/Git/mnt/c/...: No such file or directory`.

**원인**: MSYS는 첫 인자가 `/`로 시작하면 자동으로 Windows 경로로 변환합니다.

**해결**: `MSYS_NO_PATHCONV=1` 환경변수를 prefix로 두거나, `wsl.exe`를 명시적으로 호출.

```bash
MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -- bash /mnt/c/path/to/script.sh
```

### 1-3. WSL 백그라운드 프로세스는 부모 셸 종료 시 함께 죽는다

**증상**: `wsl -d Ubuntu -- bash -lc "(... &) "` 패턴으로 백그라운드 launch한 long-running 프로세스가 wsl 명령이 종료되는 순간 함께 종료됨.

**해결**: `systemd-run --user --unit=<name>` 으로 transient unit을 띄웁니다. WSL 셸 종료에 영향받지 않고 systemd 사용자 매니저가 살아있는 한 계속 실행.

```bash
sg docker -c 'systemd-run --user --unit=devenv-install \
  --working-directory=/path/to/devenv \
  bash scripts/install-rest.sh'
# 모니터링: journalctl --user -u devenv-install -f
# 정지: systemctl --user stop devenv-install
```

### 1-4. NTFS 마운트(/mnt/c)에서 `git`이 chmod 실패

**증상**: `error: chmod on /mnt/c/.../config.lock failed: Operation not permitted` → `fatal: could not set 'core.filemode' to 'false'`.

**원인**: WSL의 `/mnt/c`는 NTFS이므로 unix 권한 변경 불가.

**해결**: git 작업 시 `core.fileMode=false` + `core.autocrlf=false`를 미리 설정하거나, **WSL 네이티브 경로(/tmp 등)에 stage**해서 작업.

```bash
WORK=$(mktemp -d -p /tmp devenv-push-XXXX)
trap "rm -rf $WORK" EXIT
GIT_OPTS="-c user.email=auto -c user.name=auto -c core.fileMode=false -c core.autocrlf=false"

cp -r /mnt/c/.../sample-apps/${repo} "$WORK/${repo}"
pushd "$WORK/${repo}" >/dev/null
rm -rf .git node_modules build dist
git ${GIT_OPTS} init -q -b main
# ... add/commit/push
```

---

## 2. Bastion Host

### 2-1. `command:` 안에서 read-only 마운트된 sshd_config을 sed로 수정 시도

**증상**: `sed: cannot rename /etc/ssh/sedXXXXXX: Device or resource busy` → 컨테이너 restart loop.

**원인**: docker-compose에서 `:ro`로 마운트한 파일은 sed의 atomic rename이 불가. 마운트된 sshd_config가 이미 올바른 설정을 갖고 있다면 sed 자체가 불필요합니다.

**해결**: command에서 sed 라인을 완전히 제거. sshd_config 파일을 직접 갖춰서 마운트.

### 2-2. fail2ban이 sshd jail 로그파일을 못 찾아 종료 → sshd 시작 안 됨

**증상**:
```
fail2ban  ERROR  Failed during configuration: Have not found any log file for sshd jail
* Starting Authentication failure monitor fail2ban  ...fail!
```
이후 `&&` 체이닝으로 sshd가 시작되지 못해 컨테이너가 종료/재시작 루프.

**해결**: 개발 환경에서는 fail2ban을 제거하거나, `||` 체이닝으로 fail-safe 처리.

```yaml
command: >
  bash -c "
    apt-get update &&
    apt-get install -y --no-install-recommends openssh-server curl jq vim ca-certificates &&
    mkdir -p /var/run/sshd /var/log &&
    touch /var/log/auth.log &&
    echo 'root:${BASTION_ROOT_PASSWORD}' | chpasswd &&
    /usr/sbin/sshd -D
  "
```

운영 환경에서 fail2ban이 필요하면 미리 sshd jail 설정 (`/etc/fail2ban/jail.d/sshd.conf`)을 마운트해서 logpath 명시.

---

## 3. Nexus Docker Registry

3개의 독립적인 설정이 모두 맞아야 docker push가 동작합니다. 하나라도 빠지면 실패.

### 3-1. docker-hosted repository가 생성되어야 5000 포트가 listen

**증상**: `curl http://127.0.0.1:5000/v2/` → connection reset by peer.

**원인**: Nexus는 docker repository가 정의되어야 그 포트로 listening 시작합니다. install-nexus.sh의 초기 admin 비밀번호 변경 직후 인증 timing이 안 맞으면 repo 생성 단계가 조용히 실패할 수 있습니다.

**해결**: nexus 부팅 + 비밀번호 변경 완료 후 명시적으로 API로 repo 생성 + HTTP code 검증.

```bash
curl -fsS -u "$NEXUS_USER:$NEXUS_PWD" -H "Content-Type: application/json" \
  -X POST "${NX}/service/rest/v1/repositories/docker/hosted" \
  -d '{
    "name": "docker-hosted",
    "online": true,
    "storage": {"blobStoreName": "default", "strictContentTypeValidation": true, "writePolicy": "ALLOW"},
    "docker": {"v1Enabled": false, "forceBasicAuth": false, "httpPort": 5000}
  }'
```

⚠️ `writePolicy: "ALLOW"` (NOT `ALLOW_ONCE`) — `latest` 태그를 매번 덮어써야 하는 CI 워크플로에서 필수.

### 3-2. DockerToken realm 미활성화 → docker login 401

**증상**: `docker login 127.0.0.1:5000` → `Error response from daemon: login attempt to ... failed with status: 401 Unauthorized`.

**원인**: Nexus의 기본 active realm은 `NexusAuthenticatingRealm` (basic auth) 만 — Docker registry는 별도의 Bearer Token 인증을 사용합니다.

**해결**: `DockerToken` realm을 active로 추가.

```bash
curl -fsS -u "$NEXUS_USER:$NEXUS_PWD" -H "Content-Type: application/json" \
  -X PUT "${NX}/service/rest/v1/security/realms/active" \
  --data '["NexusAuthenticatingRealm","DockerToken"]'
```

⚠️ Nexus 3 이전 버전에서 흔히 보였던 `NexusAuthorizingRealm`은 **현재 버전(3.65)에는 없습니다.** PUT 시 unknown realm 에러로 거부됩니다. `available` 엔드포인트로 ID 먼저 확인:
```bash
curl -fsS -u "$NEXUS_USER:$NEXUS_PWD" "${NX}/service/rest/v1/security/realms/available"
```

### 3-3. 호스트 daemon이 `nexus:5000` hostname을 resolve하지 못함

**증상**: Jenkins 컨테이너 안에서 `docker push nexus:5000/...` → `lookup nexus on 10.255.255.254:53: i/o timeout`.

**원인**: Jenkins 안의 docker CLI는 호스트 docker.sock을 통해 호스트 daemon에 명령을 보내고, 호스트 daemon이 실제 push를 실행합니다. **호스트는 {project}-net 내부 hostname을 모릅니다.**

**해결**: 푸시/pull 주소를 항상 `127.0.0.1:5000`으로 hardcode (insecure-registry로 등록된 주소). 컴파일된 이미지의 tag도 동일하게.

```groovy
environment {
  NEXUS_PUSH = '127.0.0.1:5000'   // 호스트 daemon이 알 수 있는 주소
  IMAGE      = "${NEXUS_PUSH}/${PROJECT}/${APP}"
}
```

⚠️ JCasC의 `NEXUS_DOCKER` 환경변수를 `nexus:5000`으로 두는 건 **혼란을 부릅니다** — Jenkinsfile에서 hardcode하는 게 안전.

---

## 4. GitLab

### 4-1. main branch는 기본적으로 protected → force push 거부

**증상**: `git push -uqf origin main` → `remote rejected ... pre-receive hook declined: You are not allowed to force push code to a protected branch on this project`.

**해결**: force push 시도 대신 **clone → 변경 → 일반 push** (fast-forward) 패턴.

```bash
git clone "$REMOTE" "$STAGE"
cd "$STAGE"
# 파일 교체
cp /path/to/new/Jenkinsfile ./Jenkinsfile
git add Jenkinsfile
git commit -m "fix: ..."
git push origin main
```

또는 GitLab API로 protection을 잠시 풀고 force push 후 다시 lock하는 방법도 있지만 비용 대비 효율 낮음.

### 4-2. CSRF crumb은 cookie 세션과 묶여있다 (Jenkins API)

**증상**: build trigger curl이 HTTP 403 반환.

**원인**: Jenkins의 crumb은 발급한 세션 안에서만 유효. 별도 curl로 crumb만 받고 다른 curl로 build trigger하면 세션 불일치.

**해결**: cookie jar 공유.

```bash
JAR=$(mktemp)
CRUMB=$(curl -c "$JAR" -fsS -u "$AUTH" "${JENKINS}/crumbIssuer/api/json" | \
        jq -r '.crumbRequestField + ":" + .crumb')
curl -b "$JAR" -fsS -u "$AUTH" -H "$CRUMB" -X POST "${JENKINS}/job/${JOB}/build"
rm -f "$JAR"
```

---

## 5. Jenkins / Docker Build

### 5-1. Jenkins agent는 호스트 docker daemon만 갖고 있다

기본 JCasC + Dockerfile에 `docker-cli` + `compose-plugin`만 추가하면, Jenkins 안에는 **gradle / npm / node / mvn 어떤 빌드 도구도 없음**.

**Jenkinsfile에서 직접 `gradle bootJar` / `npm install`을 호출하면 exit code 127** (command not found).

**해결**: 모든 빌드/테스트를 **Dockerfile multi-stage**로 위임. Jenkinsfile은 `docker build`만 호출.

```dockerfile
# Stage 1: Test
FROM gradle:8.5-jdk17 AS test
WORKDIR /src
COPY . .
RUN gradle test --no-daemon

# Stage 2: Build (test stage에서 이미 검증되었으므로 -x test)
FROM gradle:8.5-jdk17 AS builder
WORKDIR /src
COPY . .
RUN gradle bootJar -x test --no-daemon

# Stage 3: Runtime
FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=builder /src/build/libs/app.jar /app/app.jar
EXPOSE 8090
ENTRYPOINT ["sh", "-c", "java ${JAVA_OPTS} -jar /app/app.jar"]
```

```groovy
stage('Unit Test')   { steps { sh "docker build --target test -t ${IMAGE}:test-${BUILD_NUMBER} ." } }
stage('Docker Build'){ steps { sh "docker build -t ${IMAGE}:${BUILD_NUMBER} -t ${IMAGE}:latest ." } }
```

### 5-2. `--build-arg` 값에 공백이 있으면 quoting이 깨진다

**증상**: `--build-arg VITE_APP_NAME="{PROJECT_NAME} Admin"`이 echo / 다른 shell expansion을 거치며 `{PROJECT_NAME}`만 전달되고 `Admin`은 다른 인자로 잘못 해석.

**해결**: 공백 포함 값은 build-arg로 넘기지 말고 **코드에 hardcode** 또는 `.env` 파일로 처리.

```jsx
// src/pages/AdminLoginPage.jsx
const APP_NAME = '{PROJECT_NAME} Admin'  // hardcode가 가장 안전
```

### 5-3. 동시 docker build 시 containerd race condition

**증상**: 여러 잡이 같은 base image (`node:20-alpine` 등) 으로 동시에 build → `failed to export layer ... rename .../ingest/.../data ... blobs/sha256/...: no such file or directory`.

**원인**: containerd의 임시 ingest 디렉토리는 단일 base image에 대해 동시 빌드를 안전하게 처리하지 못합니다.

**해결**: 빌드 트리거를 **순차(sequential)** 로 변경. 단일 호스트 / 단일 docker daemon 환경에서는 권장되는 패턴입니다.

```bash
# trigger-jobs.sh: backend → frontend → admin 순차 + 각 잡 완료 대기
for job in "${JOBS[@]}"; do
  trigger_one "$job"
  wait_for_finish "$job" || exit 1
done
```

---

## 6. 설치 자동화 / Watchdog

### 6-1. 단일 install-all.sh 대신 단계별 + watchdog 패턴

장시간 설치 (15~25분)에서 부모 셸이 종료되거나 네트워크 일시 끊김으로 install-all.sh가 죽으면 어디서 멈췄는지 모릅니다. 다음 패턴이 검증되었습니다:

1. **install을 systemd unit으로 가동** — `systemd-run --user --unit=devenv-install bash scripts/install-rest.sh`
2. **별도 watchdog 가동** — 30초 주기로 `systemctl --user is-active`, journal 활동, 컨테이너 unhealthy/restart, 잘 알려진 오류 패턴 (`connection reset`, `pull access denied`, `no space left`, `level=fatal`) 검사
3. **알려진 패턴 자동 fix** — 에이전트가 알림을 받아 즉시 진단 후 수정 → push & retrigger

`scripts/watchdog.sh` (systemd unit 모드) 와 `scripts/verify-loop.sh` (Jenkins 빌드 + 컨테이너 + HTTP 200 검증) 두 layer로 분리하면 효과적.

### 6-2. 알려진 임시 실패는 retry로 흡수

Docker Hub CDN에서 큰 이미지 (GitLab 3GB) 풀링 중 `connection reset by peer` 발생 가능. 다음 패턴:

```bash
pull_retry() {
  local img="$1"; local n=0
  until [[ $n -ge 3 ]]; do
    docker pull "$img" && return 0
    n=$((n+1))
    sleep 10
  done
  return 1
}
```

설치 마스터 스크립트가 docker compose up 호출 전에 명시적 pull + retry 단계를 갖추면 안정성이 크게 향상됩니다.

---

## 7. 포트 충돌 방지 (재확인)

다음 충돌은 자주 발생하므로 기본값을 어긋나게 잡아두세요:

| 서비스 (기본 포트) | 충돌 상대 | 권장 변경 |
|---|---|---|
| cAdvisor (8080) | Jenkins (8080) | **8083** |
| SkyWalking UI (8080) | Jenkins (8080) | **8888** |
| Loki (3100) | Admin (3100) | Loki를 **3110** |
| GitLab (80) | 호스트 80 | **8082** |

---

## 8. 빌드 순서 (기본 정책)

`backend → frontend → admin` 순차 빌드를 기본으로 합니다.

이유:
- 의존성 순서: backend가 API 계층, frontend/admin은 그것을 소비
- 동시 빌드 시 docker daemon / containerd race 회피 (5-3 참조)
- 한 잡 실패 시 후속 잡 트리거 안 함 (실패 격리)

`trigger-jobs.sh`는 sequential 모드를 기본값으로 두고, `--parallel` 옵션은 디버깅 용도로만 노출.

### 8-1. trigger-jobs.sh build number 추적 함정

sequential 모드의 `wait_for_finish`가 `prev_bn=lastBuild.number`로 기준점을 잡지만, 잡이 한 번도 안 돌았거나 `[]` 가 셸에서 escape되면 `prev_bn=0`이 되어 `target=#1`로 잘못 추적. 결과적으로 **새 빌드를 못 찾고 즉시 FAILURE로 잘못 보고** 후 후속 잡 안 트리거.

**해결**: 트리거 직후 `Location:` 헤더의 queueItem URL을 받아서 polling, 또는 webhook으로 빌드된 잡과 수동 트리거 충돌 회피 (둘 중 하나만 사용).

webhook과 수동 트리거가 동시 가능하면 build number 충돌. push-and-rebuild.sh가 push 직후 webhook으로 자동 빌드되는 잡을 또 트리거하지 않도록 정렬.

---

## 9. 관측성 도구 통합 (Prometheus / Grafana / SkyWalking / SonarQube)

**컨테이너는 띄워지지만 앱 통합은 별도 작업**. 이번 세션에서 검증된 패턴:

### 9-1. Backend deploy에 SkyWalking agent 마운트 + javaagent

Jenkinsfile deploy stage:
```groovy
docker run -d --name ${PROJECT}-${APP} \
  --hostname ${APP} --network ${PROJECT}-net --network-alias ${APP} \
  -v ${PROJECT}_skywalking_agent:/skywalking \
  -e SW_AGENT_NAME=${PROJECT}-${APP} \
  -e SW_AGENT_COLLECTOR_BACKEND_SERVICES=skywalking-oap:11800 \
  -e JAVA_OPTS='-Xms512m -Xmx1g -javaagent:/skywalking/agent/skywalking-agent.jar' \
  ${IMAGE}:latest
```

⚠️ `--hostname / --network-alias` 빠지면 Prometheus 등이 hostname으로 접근 불가 (§3-3).
⚠️ skywalking_agent volume은 `01-bootstrap.sh`에서 미리 생성, install-apm.sh의 init 컨테이너가 agent jar 복사. backend는 read-only 마운트만.

검증: SkyWalking UI(8888)에 backend가 서비스로 보고됨 — 또는 GraphQL `getAllServices`.

### 9-2. SonarQube 글로벌 토큰 → Jenkins credential 자동 등록

`sonar-token` Jenkins credential을 placeholder로 두면 빌드 시 401. 자동화:

```bash
# 1) SonarQube 토큰 발급
TOKEN=$(curl -fsS -u admin:$PWD -X POST "$SQ/api/user_tokens/generate" \
  --data-urlencode "name=jenkins-$(date +%s)" | jq -r .token)

# 2) Jenkins credential 갱신 (StringCredentialsImpl XML)
JAR=$(mktemp)
CRUMB=$(curl -c "$JAR" -fsS -u "$JAUTH" "$JENKINS/crumbIssuer/api/json" | jq -r '.crumbRequestField + ":" + .crumb')
curl -b "$JAR" -fsS -u "$JAUTH" -H "$CRUMB" -X POST \
  "$JENKINS/credentials/store/system/domain/_/credential/sonar-token/doDelete" || true
curl -b "$JAR" -fsS -u "$JAUTH" -H "$CRUMB" -H "Content-Type: application/xml" \
  --data-binary "<org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl><scope>GLOBAL</scope><id>sonar-token</id><secret>$TOKEN</secret></org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>" \
  "$JENKINS/credentials/store/system/domain/_/createCredentials"
```

`post-install.sh` 마지막 단계에 통합 권장. 발급된 토큰은 `config.env`에 보관.

Jenkinsfile의 sonar stage는 `docker run --network ${PROJECT}-net sonarsource/sonar-scanner-cli:latest -Dsonar.host.url=http://sonarqube:9000 ...` 패턴 (Jenkins agent에 sonar-scanner 설치 불필요).

### 9-3. Grafana 대시보드 자동 provisioning

datasource 자동 등록과 별개로 **대시보드도 provisioning** 가능:

```
configs/grafana/
├── provisioning/
│   ├── datasources/datasources.yml
│   └── dashboards/dashboards.yml        ★ provider 정의
└── dashboards/                          ★ 실제 대시보드
    ├── spring-boot.json   (JVM heap, HTTP 요청)
    └── node-exporter.json (호스트 + cAdvisor)
```

`provisioning/dashboards/dashboards.yml`:
```yaml
apiVersion: 1
providers:
  - name: '{project_name}-dashboards'
    folder: '{project_name}'
    type: file
    options: { path: /var/lib/grafana/dashboards }
```

monitoring compose에 `../configs/grafana/dashboards:/var/lib/grafana/dashboards:ro` 마운트 필수.

### 9-4. ⚠️ Spring Boot 3.2 + Prometheus scrape 호환성 (해결되지 않은 함정)

**같은 컨테이너 내 같은 hostname으로 다른 client만 200, Prometheus 자체로는 항상 HTTP 406**:

```
curl /actuator/prometheus              → 200 ✅
wget (Prometheus 동일 헤더) /actuator   → 200 ✅
docker exec prometheus-${PROJECT} wget ...  → 200 ✅
실제 Prometheus 자체 scrape             → 406 ❌
```

다음 시도가 모두 효과 없음:
- ❌ `WebSecurityCustomizer.ignoring().requestMatchers("/actuator/**")`
- ❌ `management.server.port: 8091` (분리 management server)
- ❌ `enable_http2: false`
- ❌ `cache.time-to-live: 0s`
- ❌ Prometheus restart / job rename trick / config reload

**권장 해결책**:
1. **SkyWalking을 Spring Boot APM의 default로** (javaagent 자동 instrumentation으로 HTTP / DB / GC / heap 모두 수집).
2. Prometheus는 self / node-exporter / cAdvisor / Jenkins로 인프라 관측 — cAdvisor가 모든 {project}-* 컨테이너 리소스를 수집하므로 backend OS-level 메트릭은 OK.
3. Spring Boot JVM 메트릭이 꼭 Prometheus로 가야 하면 `io.prometheus:simpleclient_servlet`을 직접 등록해 `/metrics` 별도 노출 (Spring Boot Actuator 우회 — content negotiation 미사용).

```gradle
implementation 'io.prometheus:simpleclient_servlet:0.16.0'
implementation 'io.prometheus:simpleclient_hotspot:0.16.0'
```

```java
@Configuration
public class PrometheusServletConfig {
  @Bean ServletRegistrationBean<MetricsServlet> promServlet() {
    DefaultExports.initialize();
    return new ServletRegistrationBean<>(new MetricsServlet(), "/metrics");
  }
}
```

prometheus.yml:
```yaml
- job_name: backend
  metrics_path: /metrics
  static_configs:
    - targets: ['backend:8090']
```

### 9-5. Prometheus 모니터링 커버리지 — 인프라 vs 앱

기본 `prometheus.yml`이 scrape하는 것:
- prometheus self / node-exporter / cAdvisor / jenkins / backend

**미통합 (별도 exporter 필요)**:

| 서버 | 추가 방법 | 난이도 |
|------|---------|--------|
| Loki | job 추가만 (Loki 자체가 `/metrics` 노출) | ⭐ |
| MySQL | `mysqld-exporter` 컨테이너 + job | ⭐ |
| GitLab | `/-/metrics` (admin token 필요) + job | ⭐⭐ |
| SonarQube | monitoring API + token | ⭐⭐ |
| Nexus | JMX exporter sidecar | ⭐⭐⭐ |
| SkyWalking OAP | telemetry export 모드 활성화 | ⭐⭐ |

`generate-configs.sh`는 위 exporter 추가를 옵션화 권장 (`config.env`에 `PROM_EXTRA_EXPORTERS=mysql,loki,gitlab` 같이).

**중요**: cAdvisor가 모든 컨테이너 리소스를 이미 수집하므로 미통합 서비스의 OS-level 메트릭은 자동 커버. 누락되는 것은 각 서비스의 application-level 메트릭 (mysql QPS, GitLab git op rate 등).

---

## 10. layered monitor 패턴 (이번 세션 검증)

```
[install-rest.sh]      → systemd-run --user --unit=devenv-install bash scripts/install-rest.sh
[watchdog-v2.sh]       → systemd unit 상태 + 컨테이너 unhealthy/restart 감시
[verify-loop.sh]       → Jenkins 빌드 result + frontend/admin HTTP 200 polling
[verify-features.sh]   → 빌드 + 배포 + 실제 로그인/사용자 관리 API 호출 검증
[verify-prom-final.sh] → backend SUCCESS 후 Prometheus scrape health 자동 검증 + 재시도
```

**핵심 원칙**:
1. monitor stdout 한 줄 = 알림 한 개 (`grep --line-buffered`).
2. **terminal state 모두** 잡기 (success / failure / stall / dead) — 행복한 path만 잡으면 crashloop 놓침.
3. 자동 복구 시도 후 안 되면 `[FAIL]`로 명시 종료 — 사람 개입 신호.
4. 실패 알림과 함께 **마지막 콘솔 로그 tail**을 같이 발신 (`[BUILD-FAIL-TAIL] ${log:0:280}`) — 에이전트가 즉시 진단.
5. **MSYS Git Bash → WSL bash** 호출 시 `MSYS_NO_PATHCONV=1` + `wsl.exe` 명시 + 복잡한 inline shell은 **별도 .sh 파일로 분리** (quote escaping 함정 회피).

---

## 11. 모니터링 사후 검증 + Alertmanager 보강 (실환경 배포 사례)

설치 21시간 후 "변경된 스킬로 모니터링 확인" 요청 시점에서 확인된 사항들. 스킬 PHASE 7 이후 운영 단계에서 마주칠 검증 흐름과 미설치 갭, 그리고 보강 작업의 정확한 diff를 정리.

### 11-1. 헬스체크는 컨테이너 내부망에서, 포트는 "내부 포트"로

**증상**: 호스트 측 `curl http://127.0.0.1:9090/-/healthy` 가 모두 FAIL. `ss -tln`도 포트가 비어 보임.

**원인**: compose가 `ports: "9090:9090"` 처럼 published 되었어도 WSL2 환경에서는 Windows host loopback과 docker bridge 간 라우팅이 즉시 보장되지 않음. devenv-monitoring/devenv-internal 같은 내부 네트워크 안에서 컨테이너명으로 호출해야 안정적.

**해결**: 검증 컨테이너를 동일 네트워크에 띄워서 probe.

```bash
docker run --rm --network devenv-monitoring curlimages/curl:8.7.1 \
  -sS --max-time 6 -o /dev/null -w "%{http_code}" \
  http://prometheus-${PROJECT}:9090/-/healthy
```

**중요 함정**: 같은 호출에서도 cAdvisor는 **published port 8088**이 아니라 **container internal port 8080**으로 호출해야 함. SkyWalking UI도 8079 (UI), OAP는 12800 (HTTP)/11800 (gRPC)/1234 (Prometheus telemetry). 잘못된 포트로 probe 하면 `HTTP 000` (connection refused)이 떨어짐.

| 서비스 | 컨테이너 내부 포트 | host published |
|---|---|---|
| Prometheus | 9090 | 9090 |
| Grafana | 3000 | 3001 |
| Loki | 3100 | 3100 |
| Promtail | 9080 | 9080 |
| node-exporter | 9100 | 9100 |
| cAdvisor | **8080** | 8088 |
| SkyWalking UI | 8079 | 8079 |
| SkyWalking OAP | 12800 / 11800 / 1234 | 동일 |
| Alertmanager | 9093 | 9093 |

### 11-2. 알람 룰만 있고 Alertmanager는 없음 (가장 큰 운영 갭)

**증상**: `prometheus.yml`에 `alerting.alertmanagers.static_configs.targets: []` (빈 배열), `rule_files`에는 5개 룰 정의되어 있음. 즉, **룰은 발화 가능하나 라우팅 대상이 없어 알림이 어디로도 안 감**.

**검증**:

```bash
docker run --rm --network devenv-monitoring curlimages/curl:8.7.1 -sS \
  http://prometheus-${PROJECT}:9090/api/v1/alertmanagers \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('active:', len(d['data']['activeAlertmanagers']))"
# 결과: active: 0   ← 룰이 있어도 알림을 보낼 곳이 없음
```

**해결**: Alertmanager 컨테이너 + 최소 config(null receiver) + prometheus.yml의 `targets:` 채우기 + prometheus 재기동(WSL inode caching 회피).

**Alertmanager 최소 config** — Slack/email은 사용자가 나중에 채울 수 있도록 receiver를 주석으로 보존하고 default는 `default-null`로:

```yaml
# alertmanager/alertmanager.yml
global:
  resolve_timeout: 5m
route:
  receiver: 'default-null'
  group_by: ['alertname', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    - matchers: [severity = "critical"]
      receiver: 'default-null'
      continue: true
inhibit_rules:
  - source_matchers: [severity = "critical"]
    target_matchers: [severity = "warning"]
    equal: ['alertname', 'instance', 'host']
receivers:
  # TEMPLATE: replace with actual Slack/email
  # - name: 'slack-critical'
  #   slack_configs:
  #     - api_url: '<SLACK_WEBHOOK_URL>'
  #       channel: '#alerts-critical'
  #       send_resolved: true
  - name: 'default-null'
```

**docker-compose.yml 추가**:

```yaml
alertmanager:
  image: prom/alertmanager:v0.27.0
  container_name: alertmanager-${PROJECT}
  restart: unless-stopped
  user: "0:0"
  command:
    - '--config.file=/etc/alertmanager/alertmanager.yml'
    - '--storage.path=/alertmanager'
    - '--web.listen-address=:9093'
    - '--cluster.listen-address='     # WSL에서 클러스터 disable
  volumes:
    - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
    - alertmanager-data:/alertmanager
  ports: ["9093:9093"]
  networks: [devenv-monitoring]
  healthcheck:
    test: ["CMD", "wget", "-qO-", "http://localhost:9093/-/healthy"]
    interval: 15s
    timeout: 5s
    retries: 6
    start_period: 20s
```

**prometheus.yml 보강**:

```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']
```

이후 `docker restart prometheus-${PROJECT}` (config reload만으로는 WSL bind-mount inode caching 때문에 반영 안 될 수 있음).

**검증 후 정상 응답**:
```text
active alertmanagers: 1
  - http://alertmanager:9093/api/v2/alerts
```

### 11-3. Promtail positions 파일 비영속 (컨테이너 재기동 시 로그 재수집)

**증상**: `promtail-config.yml`에 `positions.filename: /tmp/positions.yaml` — 컨테이너 내부 tmpfs 경로. 재기동마다 처음부터 다시 ingest → Loki에 중복 라인 + 디스크 압박.

**해결**: named volume 영속화.

```yaml
# promtail-config.yml
positions:
  filename: /promtail-data/positions.yaml
```

```yaml
# docker-compose.yml — volumes 블록
volumes:
  promtail-data:

# promtail 서비스 mounts에 추가
promtail:
  volumes:
    - promtail-data:/promtail-data
    # (기존) docker.sock, /var/log, /var/lib/docker/containers
```

검증:

```bash
docker exec promtail-${PROJECT} ls -la /promtail-data/
# positions.yaml 이 존재하고 내용에 file/cursor offset 들이 들어있어야 함
```

### 11-4. Grafana 비밀번호가 `config.env`에 없고 compose env에 직접 노출

**증상**: 스킬은 `ADMIN_SHARED_PASSWORD in config.env` 가정. 실제 compose에는:

```yaml
grafana:
  environment:
    GF_SECURITY_ADMIN_PASSWORD: '<your-password>'   # 평문 노출 — env_file로 분리 필요   # 평문 노출
```

**부작용**:
1. preset.json 의 `admin_password_source: "ADMIN_SHARED_PASSWORD in config.env"` 가 실제와 불일치
2. Grafana datasource health probe 자동화 시 인증 실패
3. git에 commit 되면 비밀번호 유출

**개선 패턴**:

```yaml
grafana:
  env_file:
    - ./grafana/grafana.env    # chmod 600, .gitignore
  environment:
    GF_SECURITY_ADMIN_USER: admin
    # password는 env_file에서만
```

또는 docker secret:

```yaml
secrets:
  grafana_admin_password:
    file: ./grafana/admin_password.txt
services:
  grafana:
    secrets: [grafana_admin_password]
    environment:
      GF_SECURITY_ADMIN_PASSWORD__FILE: /run/secrets/grafana_admin_password
```

### 11-5. PowerShell → WSL inline bash 호출의 변수 소거 함정 (재발)

**증상**: PowerShell에서 `wsl -d Ubuntu-22.04 -u ubuntu -- bash -lc 'cat > /tmp/x.sh <<"EOF" ... $name ... EOF'` 패턴으로 heredoc 생성 시, `<<"EOF"` (literal) 인용 보호에도 불구하고 `$name`/`$1` 등이 **외부 PowerShell의 변수 확장에 의해 빈 문자열로 치환**되어 파일에 빈 값이 기록됨.

**원인**: PowerShell이 인자를 wsl.exe에 넘기는 단계에서 `$`로 시작하는 토큰을 PowerShell 변수로 해석 시도. heredoc의 quote 보호는 bash 내부에서만 유효하므로, PowerShell 단계에서 이미 소거된 텍스트가 bash에 도착함.

**해결 (검증됨)**:

```powershell
# 1) 본문을 PowerShell here-string에 보관
$bash = @'
#!/bin/bash
name="$1"
echo "Hello $name"
'@
# 2) UTF-8 (BOM 없음) + LF 로 임시 파일에 작성
$tmp = Join-Path $env:TEMP "myscript.sh"
[System.IO.File]::WriteAllText($tmp, $bash.Replace("`r`n","`n"), [System.Text.UTF8Encoding]::new($false))
# 3) WSL에서 파일을 /mnt 경유로 복사 → 실행
$wp = "/mnt/c/Users/$env:USERNAME/AppData/Local/Temp/myscript.sh"
wsl -d Ubuntu-22.04 -u ubuntu -- bash -c "cp '$wp' /tmp/myscript.sh && chmod +x /tmp/myscript.sh && /tmp/myscript.sh arg1"
```

**판별 신호**: `cat -A /tmp/myscript.sh` 첫 출력에서 `local name=$` 가 `local name=` 로 잘려 있다면 (값 없음 + 줄바꿈 `$`) 변수 소거 발생.

### 11-6. Grafana healthcheck 패턴 정정 (재확인)

`{"database":"ok","version":...}` — Grafana 11.3.x 응답은 콜론 뒤에 **공백 없음** (구버전 공백 있음). 스킬의 grep 패턴은:

```bash
grep -E '"database"[[:space:]]*:[[:space:]]*"ok"'
# 또는 더 안전하게:
... | python3 -c "import json,sys; sys.exit(0 if json.load(sys.stdin).get('database')=='ok' else 1)"
```

compose 의 healthcheck도 `>/dev/null 2>&1 || exit 1` 패턴으로 응답 형식에 의존 안 하도록:

```yaml
test: ["CMD-SHELL", "wget -qO- http://localhost:3000/api/health >/dev/null 2>&1 || exit 1"]
```

### 11-7. 검증 합격선 (post-install audit checklist)

설치 후 또는 스킬 변경 후 다음 6개가 통과하면 운영 가능 상태.

```text
1) docker ps --format "{{.Names}} {{.Status}}" | grep -E "healthy|Up" 가 9개 이상
2) docker run --rm --network <NET> curlimages/curl -sS http://<svc>:<internal_port>/health 가 8/8 HTTP 200
3) prom api/v1/targets?state=active 의 up == total (jenkins/gitlab/gitlab-exporter/gitlab-workhorse/nexus 포함)
4) prom api/v1/alertmanagers .data.activeAlertmanagers length >= 1
5) Loki api/v1/query_range with {job="docker"} for last 1h returns >= 1 stream
6) SkyWalking GraphQL getAllServices for last 24h returns >= 1 service
```

각 단계가 PHASE 7 success criterion(`metrics=ok AND logs=ok AND apm=ok AND alertmanager=ok AND (app-link=ok OR app-not-installed)`)에 매핑.

### 11-8. SkyWalking UI 빈 화면 = OAP 시작 race condition (재확인)

OAP가 완전히 readiness OK 되기 전에 UI 컨테이너가 먼저 백엔드에 연결을 시도하면, UI 로그에 `Connection refused: skywalking-oap/172.18.0.6:12800` 가 한참 남음. 이후 OAP가 healthy 되어도 UI는 재연결을 시도하므로 시간 지나면 회복. **첫 설치 직후 UI가 비어 있어도 5분 정도 후 다시 확인**할 것. 단, `depends_on: { skywalking-oap: { condition: service_healthy } }` 를 UI에 걸어두면 race가 줄어듬.
