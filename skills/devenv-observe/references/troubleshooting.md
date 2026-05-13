# 트러블슈팅

설치/운영 중 자주 발생하는 오류와 해결책입니다.

> **경로**: `scripts/health-check.sh` 등은 **`devenv-core`가 생성한 `${DEVENV_HOME}`** 아래 스크립트를 가리킵니다. `devenv-observe` Git 루트에는 동일 경로가 없을 수 있습니다.

> ⚡ **실제 배포에서 검증된 비자명한 함정 14+개**는 별도 문서:
> → `references/lessons-learned.md`
>
> ### Quick Index
>
> | 증상 | 원인 영역 | 자세히 |
> |------|----------|--------|
> | systemd unit에서 docker.sock permission denied | WSL + docker group | lessons §1-1 |
> | `bash: C:/Program Files/Git/mnt/c/...: No such file` | MSYS path conv | lessons §1-2 |
> | WSL background 프로세스가 셸 종료와 함께 죽음 | systemd-run 필요 | lessons §1-3 |
> | `chmod ... config.lock failed: Operation not permitted` | NTFS 마운트 | lessons §1-4 |
> | Bastion `sed: cannot rename ... Device or resource busy` | read-only mount | lessons §2-1 |
> | Bastion fail2ban이 sshd 시작 막음 | command 체이닝 | lessons §2-2 |
> | nexus :5000/v2/ connection reset | docker-hosted 미생성 | lessons §3-1 |
> | docker login 401 Unauthorized | DockerToken realm | lessons §3-2 |
> | `lookup nexus on ...: i/o timeout` | 호스트 DNS | lessons §3-3 |
> | `Repository does not allow updating assets` | writePolicy=ALLOW_ONCE | lessons §3-4 |
> | GitLab `not allowed to force push` | main protection | lessons §4-1 |
> | Jenkins build trigger 403 | CSRF crumb session | lessons §4-2 |
> | Jenkins build `exit code 127` | gradle/npm 미설치 | lessons §5-1 |
> | `--build-arg` 공백 quoting 깨짐 | shell expansion | lessons §5-2 |
> | docker build `failed to export layer: rename ingest...` | containerd race | lessons §5-3 |
> | trigger-jobs.sh가 새 빌드를 못 찾고 즉시 FAILURE | build number 추적 | lessons §8-1 |
> | Prometheus만 backend scrape 시 406 (manual은 200) | Spring Boot 3.2 호환성 | lessons §9-4 |
> | SonarQube sonar-token 401 | placeholder credential 미갱신 | lessons §9-2 |
> | Grafana 대시보드 0개 (no data) | provisioning 미설정 | lessons §9-3 |
> | SkyWalking 서비스 보고 0개 | javaagent + agent volume 미적용 | lessons §9-1 |
> | Windows Git Bash에서 `docker: command not found` | 실행 컨텍스트 불일치 | 9장 (WSL 실행 원칙) |
> | `permission denied ... docker.sock` + sudo 비번 요구 | docker.sock 권한 | 9장 (root 진입 패턴) |
> | `awk ... unterminated string` | 교차 셸 인용/이스케이프 | 9장 (헬스체크 스크립트) |
> | 설정 파일 생성 시 `No such file or directory` | heredoc 경계 전달 실패 | 9장 (이중 heredoc) |
> | Prometheus jenkins/gitlab/nexus target down | 서비스 메트릭 비활성 기본값 | 6장 (후속 활성화) |

---

## A. 우선 해결 순서 (Observe 설치/운영)

설치 실패를 가장 크게 줄이는 우선순위입니다. 상세 원인은 각 본문 섹션을 참고하세요.

### A-1. P0 - 실행 컨텍스트 고정 (Windows -> WSL)
- Docker/Compose/스크립트 실행 위치를 WSL 내부로 고정합니다.
- Windows Git Bash에서 직접 Docker 명령을 실행하지 않습니다.
- 기준 명령:
  - `wsl.exe -d Ubuntu-22.04 -u root -- bash`

### A-2. P1 - 권한/사용자 컨텍스트 선제 교정
- `/var/run/docker.sock` 권한 오류가 반복되면 일반 사용자 기반 실행을 중단합니다.
- 초기 설치/복구는 root 진입 패턴으로 통일합니다.
- 필요 시 서비스 설치 후 운영 단계에서만 일반 사용자 권한으로 전환합니다.

### A-3. P1 - 교차 셸 경계 표준화 (Git Bash ↔ WSL)
- `wsl.exe ... -- bash -c "..."` 형태의 복잡한 인라인 쿼팅을 지양합니다.
- 설정 파일 생성은 이중 heredoc 또는 Linux 측 단일 스크립트로 처리합니다.
- 원칙:
  - 외부 heredoc: WSL bash 실행 블록 전달
  - 내부 heredoc: Linux 측 파일 쓰기 담당

### A-4. P1 - Readiness 기반 설치/헬스체크 오케스트레이션
- 고정 sleep 또는 부모 PID wait 기반 폴링을 사용하지 않습니다.
- 교차 셸 경유 스크립트에서 `awk/sed` one-liner의 중첩 인용을 피합니다.
- 단일 문자 상태 변수(`O`/`W`)와 명시적 `if/else` 분기로 구현합니다.
- readiness 기준(예시):
  - Prometheus: `/-/healthy` 또는 API 응답 확인
  - Grafana: `/api/health`
  - Alertmanager: `/-/healthy`
- retry/backoff: `3회`, `5s/10s/20s`

### A-5. P2 - Prometheus 타겟 down 판정 기준 분리
- `jenkins/gitlab/nexus target down`을 즉시 설치 실패로 판정하지 않습니다.
- 먼저 각 서비스 메트릭 엔드포인트 활성화 여부를 확인합니다.
- 인프라 정상 + 메트릭 비활성 상태는 "후속 설정 필요"로 분리 기록합니다.
- 성공 기준을 "컨테이너 running"에서 "서비스 readiness + 포트 응답 + 핵심 시나리오"로 강화합니다.

### A-6. P1 - 산출물 경로 기준 통일 (DEVENV_HOME)
- 전역 계약 기준 경로:
  - `${DEVENV_HOME}` (미설정 시 `~/devenv-${PROJECT_NAME}`)
- `devenv-core`와 `devenv-observe`는 **동일한 DEVENV_HOME 루트**를 공유합니다.
- `devenv-observe`는 별도 루트(`/.../observe`)를 강제하지 않으며, 보통 아래처럼 루트 하위에 산출물을 둡니다.
  - `docker-compose/docker-compose.monitoring.yml`
  - `configs/prometheus/`, `configs/grafana/`, `configs/loki/`
  - `${DEVENV_HOME}/preset.json`의 `observe` 섹션

---

## 0. 디버깅 기본 명령

```bash
# 컨테이너 로그
docker logs <컨테이너명> --tail 100 -f

# 컨테이너 진입
docker exec -it <컨테이너명> /bin/bash

# 컨테이너 상태
docker ps -a --format 'table {{.Names}}\t{{.Status}}'

# 호스트 리소스
docker stats --no-stream
free -h && df -h

# 헬스체크 실행
bash scripts/health-check.sh
```

---

## 1. Jenkins

### "No such DSL method '﻿pipeline' found" (BOM 문자 문제)
**원인**: PowerShell의 `Out-File -Encoding utf8` 또는 `Set-Content -Encoding utf8`는 파일 앞에
UTF-8 BOM(`\xEF\xBB\xBF`, 보이지 않는 문자 `﻿`)을 삽입합니다. Jenkins 파서가 이 문자를
pipeline 키워드 앞에 붙여 인식하여 "No such DSL method '﻿pipeline'" 오류가 발생합니다.

**해결**: PowerShell에서 Jenkinsfile 작성 시 반드시 BOM 없는 UTF-8 사용:
```powershell
# 잘못된 방법 (BOM 포함)
$content | Out-File -Encoding utf8 "Jenkinsfile"
Set-Content -Encoding utf8 "Jenkinsfile" -Value $content

# 올바른 방법 (BOM 없음)
[System.IO.File]::WriteAllText(
    (Resolve-Path "Jenkinsfile").Path,
    $content,
    [System.Text.UTF8Encoding]::new($false)   # $false = no BOM
)

# 이미 BOM이 삽입된 파일 수정 (WSL에서)
sed -i '1s/^\xEF\xBB\xBF//' ~/devenv-myproject/sample-app/Jenkinsfile
```

**확인**: 파일 첫 3바이트가 `112 105 112` (p-i-p) 이어야 함. BOM이 있으면 `239 187 191`.
```powershell
$bytes = [System.IO.File]::ReadAllBytes('Jenkinsfile')
Write-Host "First bytes: $($bytes[0]) $($bytes[1]) $($bytes[2])"
# OK:   112 105 112  (p i p → "pipeline")
# FAIL: 239 187 191  (BOM → "﻿pipeline")
```

---

### Trivy "ignore file not found: /.trivyignore" (Docker-in-Docker 문제)
**원인**: Jenkins가 Docker 컨테이너 안에서 실행될 때(Docker-in-Docker, DinD), Jenkinsfile의
`-v ${env.WORKSPACE}/.trivyignore:/.trivyignore` 마운트가 실패합니다.

`${env.WORKSPACE}`는 Jenkins 컨테이너 내부 경로(예: `/var/jenkins_home/workspace/sample-app/`)
로 해석되지만, `docker run` 명령을 실행하는 Docker 데몬은 **호스트**에서 실행됩니다.
호스트 파일시스템에는 해당 경로가 존재하지 않으므로 Trivy가 파일을 찾지 못합니다.

**해결**: `--ignorefile` 플래그와 `-v` 마운트를 제거하고 `--ignore-unfixed`만 사용합니다.
`--ignore-unfixed`는 Maven Central에 수정 버전이 없는 CVE를 자동으로 억제합니다.

```groovy
// 잘못된 방법 (DinD 환경에서 동작 안 함)
stage('7. Image Scan (Trivy)') {
    steps {
        sh """
          docker run --rm \\
            -v /var/run/docker.sock:/var/run/docker.sock \\
            -v ${env.WORKSPACE}/.trivyignore:/.trivyignore \\
            aquasec/trivy:latest image \\
            --exit-code 1 --severity HIGH,CRITICAL \\
            --ignore-unfixed --ignorefile /.trivyignore \\
            ${NEXUS_REGISTRY}/${BACKEND_IMAGE}:${IMAGE_TAG}
        """
    }
}

// 올바른 방법
stage('7. Image Scan (Trivy)') {
    steps {
        sh """
          docker run --rm \\
            -v /var/run/docker.sock:/var/run/docker.sock \\
            aquasec/trivy:latest image \\
            --exit-code 1 --severity HIGH,CRITICAL \\
            --ignore-unfixed \\
            ${NEXUS_REGISTRY}/${BACKEND_IMAGE}:${IMAGE_TAG}
        """
    }
}
```

> **참고**: `--ignore-unfixed`와 `--ignorefile`의 차이:
> - `--ignore-unfixed`: 수정 버전이 없는 CVE를 모두 무시 (Maven Central 기준)
> - `--ignorefile .trivyignore`: 특정 CVE ID를 파일로 직접 지정하여 무시

---

### Spring Security CVE 대응 (Spring Boot 3.4.x, 2026-04 기준)
**발견된 CVE**:
| CVE | 심각도 | 컴포넌트 | 수정 버전 | 대응 방법 |
|-----|--------|---------|---------|---------|
| CVE-2025-41232 | CRITICAL | spring-security-crypto | 6.4.7 | `ext['spring-security.version'] = '6.4.7'` |
| CVE-2025-41248 | HIGH | spring-security-core | Maven Central 미출시 | `--ignore-unfixed` |
| CVE-2026-22732 | CRITICAL | spring-security-web | Maven Central 미출시 | `--ignore-unfixed` |

**build.gradle 수정**:
```groovy
ext['spring-framework.version'] = '6.2.11'
ext['spring-security.version']  = '6.4.7'   // CVE-2025-41232 수정
ext['tomcat.version']           = '10.1.54'  // Tomcat CVE 수정
```

**Trivy 스캔 명령**:
```bash
# --ignore-unfixed로 Maven Central 미출시 CVE 자동 억제
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image \
  --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed \
  localhost:5000/myproject-backend:latest
```

---

### Groovy GString에서 credentials 변수 이스케이프
**원인**: `sh """..."""` 블록은 Groovy GString입니다. `$VAR`는 Groovy가 먼저 해석합니다.
`withCredentials`로 주입된 `NEXUS_PASS`, `NEXUS_USER`는 Groovy 변수가 아닌 **쉘 환경변수**이므로
이스케이프 없이 쓰면 빈 문자열로 치환됩니다.

```groovy
// 잘못된 방법 (Groovy가 $NEXUS_PASS를 빈 문자열로 치환)
sh """
  echo "$NEXUS_PASS" | docker login ...
"""

// 올바른 방법 (\$ 이스케이프로 Groovy 치환 방지, 쉘이 해석)
sh """
  echo "\$NEXUS_PASS" | docker login -u "\$NEXUS_USER" --password-stdin ${NEXUS_REGISTRY}
"""
```

---

### "permission denied while trying to connect to docker daemon"
**원인**: Jenkins 컨테이너의 docker socket 접근 권한 부족.
**해결**:
```bash
# 호스트의 docker 그룹 GID 확인
getent group docker
# 예: docker:x:989

# docker-compose.jenkins.yml의 user를 "1000:<실제GID>"로 수정 후 재기동
# WSL2에서는 GID가 989 또는 998일 수 있음 (Docker Desktop: 999)
sed -i 's/user: "1000:[0-9]*/user: "1000:989/' docker-compose/docker-compose.jenkins.yml
docker compose -f docker-compose/docker-compose.jenkins.yml up -d --force-recreate
```

### "docker: command not found" (Jenkins Pipeline Stage 6~9)
**원인**: Jenkins 표준 이미지(`jenkins/jenkins:lts-jdk17`)에는 Docker CLI가 없음.
**해결**: `configs/jenkins/Dockerfile`로 커스텀 이미지를 빌드해야 함.
```bash
# jenkins.yml이 build: 섹션으로 되어있는지 확인
grep -A3 'build:' docker-compose/docker-compose.jenkins.yml

# 이미지 재빌드 (처음 한 번만 시간 소요)
docker compose -f docker-compose/docker-compose.jenkins.yml build --no-cache
docker compose -f docker-compose/docker-compose.jenkins.yml up -d --force-recreate

# 확인
docker exec jenkins-<project> docker --version
```

### Jenkins CSRF: 빌드 트리거 403 Forbidden
**원인**: Jenkins는 POST 요청에 CSRF Crumb 토큰을 요구함.
**해결**:
```bash
# Crumb 발급
CRUMB_JSON=$(curl -sS -u "admin:<PASSWORD>" "http://localhost:8080/crumbIssuer/api/json")
CRUMB_FIELD=$(echo $CRUMB_JSON | jq -r '.crumbRequestField')
CRUMB_VALUE=$(echo $CRUMB_JSON | jq -r '.crumb')

# 빌드 트리거 (Crumb 포함)
curl -sS -X POST -u "admin:<PASSWORD>" \
  -H "${CRUMB_FIELD}: ${CRUMB_VALUE}" \
  "http://localhost:8080/job/sample-app/build"
```

### JCasC ConfigurationAsCodeBootFailure
**원인A**: `jenkins.yaml`에 `remotingSecurity: enabled: true` 블록 존재.
**해결**: 해당 블록 제거 (최신 Jenkins LTS에서 지원하지 않음).

**원인B**: `jobs` 섹션의 Job DSL에 `triggers { gitlabPush {...} }` 블록 존재.
**해결**: triggers 블록 제거. GitLab Webhook은 `post-install.sh`에서 API로 직접 등록.

```bash
# 오류 확인
docker logs jenkins-<project> | grep -A5 'ConfigurationAsCode'
```

### "java.lang.OutOfMemoryError: Java heap space"
**해결**: jenkins.yml의 JAVA_OPTS에 `-Xmx2g` 추가, 호스트 RAM 확인.

### Pipeline에서 GitLab webhook 트리거 안됨
- GitLab → Project → Webhooks → Test → "Push events" 결과 확인
- Jenkins job 설정의 `gitlab-plugin` URL과 secret token 일치 확인

---

## 2. GitLab

### Personal Access Token (PAT) API 호출이 401 Unauthorized 반환 (GitLab 18.x)
**원인**: GitLab 18.x 일부 버전에서 PAT 관련 feature flag들이 비활성화된 채로 배포됩니다.
`personal_access_tokens`, `api_personal_access_token_auth`, `pat_authentication` 플래그가
모두 `false`이면 PAT으로 생성한 토큰이 모든 API 요청에서 401을 반환합니다.

**진단**: GitLab Rails 콘솔에서 확인
```bash
docker exec -it gitlab-myproject gitlab-rails console
# Rails 콘솔에서:
Feature.enabled?(:personal_access_tokens)
Feature.enabled?(:api_personal_access_token_auth)
Feature.enabled?(:pat_authentication)
# => false 이면 문제
```

**해결 방법 1**: Feature flag 활성화
```ruby
# Rails 콘솔에서:
Feature.enable(:personal_access_tokens)
Feature.enable(:api_personal_access_token_auth)
Feature.enable(:pat_authentication)
```
→ 위 방법으로도 해결되지 않을 수 있음. 그럴 경우 방법 2 사용.

**해결 방법 2 (권장)**: git push 시 root 비밀번호 직접 사용
```bash
# PAT 대신 기본 인증(root 비밀번호) 사용
GITLAB_PW=$(grep GITLAB_ROOT_PASSWORD ~/devenv-<project>/config.env | cut -d'=' -f2 | tr -d '"')
git remote set-url origin "http://root:${GITLAB_PW}@localhost:<GITLAB_PORT>/<PROJECT>/sample-app.git"
git push origin main
```

**해결 방법 3**: GitLab API 호출 시 Basic Auth 사용
```bash
curl -sS -u "root:<GITLAB_PW>" \
  "http://localhost:<GITLAB_PORT>/api/v4/projects"
```

---

### install-all.sh가 "GitLab 기동 대기" 에서 무한 반복
**원인**: `/-/health` 또는 `/-/readiness` 엔드포인트는 DB 마이그레이션 중에도
        200을 반환할 수 있어 실제 기동 완료를 신뢰할 수 없음.
**해결**: `/users/sign_in` 으로 헬스체크 변경. 이 페이지가 200을 반환해야 진짜 완료.
```bash
# install-all.sh 수동 변경
sed -i 's|/-/health|/users/sign_in|g' scripts/install-all.sh
```

### "502 Bad Gateway" (기동 직후)
**원인**: 첫 부팅 시 데이터베이스 마이그레이션 진행 중. 5~10분 소요.
**해결**:
```bash
docker logs -f gitlab-<project>
# "gitlab Reconfigured!" 메시지 확인 후 다시 접속
```

### Webhook이 internal IP를 거부 ("URL is blocked")
**해결**: Admin → Settings → Network → Outbound requests → "Allow requests to the local network from web hooks" 체크.

### 메모리 부족 (`gitlab` 컨테이너 OOM)
**해결**:
```ruby
# GITLAB_OMNIBUS_CONFIG에 추가
puma['worker_processes'] = 2
sidekiq['max_concurrency'] = 10
```

---

## 3. SonarQube

### "max virtual memory areas vm.max_map_count [65530] is too low"
**해결**:
```bash
sudo sysctl -w vm.max_map_count=262144
echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf
docker restart sonarqube-<project>
```

### "ElasticSearch: bootstrap checks failed"
이전 항목과 동일.

### Quality Gate가 PENDING 상태에서 5분 타임아웃 → 빌드 ABORTED
**원인**: SonarQube Webhook URL이 `http://localhost:8080/sonarqube-webhook/` 으로 등록됨.
SonarQube 컨테이너 내부에서 `localhost`는 Jenkins가 아닌 SonarQube 자신을 가리킴.
→ Jenkins에 Quality Gate 결과가 전달되지 않아 5분 대기 후 ABORTED.

**해결**: Webhook URL을 컨테이너명으로 재등록.
```bash
# 기존 webhook 삭제 후 재등록
WEBHOOK_KEY=$(curl -sS -u "admin:<SONAR_PW>" \
  "http://localhost:9000/api/webhooks/list" \
  | jq -r '.webhooks[0].key // empty')

[ -n "$WEBHOOK_KEY" ] && curl -sS -u "admin:<SONAR_PW>" \
  -X POST "http://localhost:9000/api/webhooks/delete" \
  -d "webhook=${WEBHOOK_KEY}"

curl -sS -u "admin:<SONAR_PW>" \
  -X POST "http://localhost:9000/api/webhooks/create" \
  -d "name=jenkins&url=http://jenkins-<PROJECT_NAME>:8080/sonarqube-webhook/"
```

### Quality Gate 실패가 빌드에 반영 안 됨
- SonarQube → Webhooks에 Jenkins 컨테이너명 URL 등록 확인 (위 참조)
- Jenkinsfile의 `waitForQualityGate abortPipeline: true` 사용 확인

---

## 4. Nexus

### admin 비밀번호 분실 / 첫 로그인
```bash
docker exec nexus-<project> cat /nexus-data/admin.password
```

### Docker push가 "denied: requested access to the resource is denied"
- Nexus → Security → Realms → "Docker Bearer Token Realm" 활성화
- 저장소 URL: `<NEXUS_IP>:5000` (Docker Hosted)
- `docker login <NEXUS_IP>:5000` 후 push

### Docker push/login이 403 Forbidden (Nexus 3.61+)
**원인**: Nexus CE(Community Edition) 3.61+ 부터 EULA 동의가 필수. 미동의 시 Docker registry 포함 모든 API가 차단됨.
**해결**:
```bash
# EULA 수락 (Python 사용)
python3 << 'EOF'
import urllib.request, json, base64
url='http://localhost:8081/service/rest/v1/system/eula'
auth=base64.b64encode(b'admin:<NEXUS_PW>').decode()
headers={'Authorization':f'Basic {auth}','Content-Type':'application/json'}
req=urllib.request.Request(url,headers=headers)
with urllib.request.urlopen(req) as r:
    eula=json.loads(r.read())
payload=json.dumps({'accepted':True,'disclaimer':eula['disclaimer']}).encode()
req=urllib.request.Request(url,data=payload,headers=headers,method='POST')
urllib.request.urlopen(req)
print("EULA accepted")
EOF
```

### "no basic auth credentials" / "http: server gave HTTP response to HTTPS client"
**원인**: Docker 데몬이 Nexus Docker 레지스트리를 insecure registry로 허용하지 않음.
**해결**:
```bash
# WSL2 Ubuntu (Docker 직접 설치 방식)
sudo bash -c 'echo "{\"insecure-registries\": [\"<NEXUS_IP>:5000\"]}" > /etc/docker/daemon.json'
sudo service docker restart
docker info | grep -A3 "Insecure"   # 10.0.1.10:5000 목록에 있어야 함

# Docker Desktop 방식: Docker Desktop → Settings → Docker Engine 에서 직접 편집
```

### Gradle wrapper 없음: "gradlew: not found" (Jenkins 빌드 실패)
**원인**: sample-app 초기 push 시 `gradlew` 파일이 없음.
**해결**: Docker로 wrapper 생성 후 push.
```bash
cd sample-app/backend
docker run --rm -v "$(pwd)":/project -w /project gradle:8.5-jdk17 gradle wrapper
git add gradlew gradlew.bat gradle/
git commit -m "chore: add gradle wrapper"
GITLAB_TOKEN=$(grep GITLAB_TOKEN ~/devenv-<project>/config.env | cut -d'"' -f2)
git remote set-url origin "http://root:${GITLAB_TOKEN}@localhost:<GITLAB_PORT>/<PROJECT>/sample-app.git"
git push origin main
```

### Spring Boot 통합 테스트에서 @Transactional 사용 시 인증 실패
**원인**: `@SpringBootTest` + `@AutoConfigureMockMvc` + `@Transactional` 조합에서
Spring Security 필터 체인이 별도 트랜잭션 컨텍스트에서 실행됩니다.
`@BeforeEach`에서 저장한 사용자가 다른 트랜잭션 컨텍스트에서 보이지 않아 로그인 테스트가 실패합니다.

**증상**: `loginSuccess()` 테스트가 `200 OK` 대신 `401 Unauthorized` 반환.

**해결**: `@Transactional`을 테스트 클래스에서 제거하고 `@AfterEach`에서 수동으로 정리:
```java
// 잘못된 방법
@SpringBootTest
@AutoConfigureMockMvc
@Transactional  // ← 이 어노테이션 제거
class AuthControllerTest { ... }

// 올바른 방법
@SpringBootTest
@AutoConfigureMockMvc
class AuthControllerTest {
    @BeforeEach
    void setUp() {
        repo.deleteAll();
        repo.saveAndFlush(new User("testadmin", "admin@test.com",
            encoder.encode("Admin1234!"), "ADMIN"));
    }

    @AfterEach
    void tearDown() { repo.deleteAll(); }
}
```

**주의**: 여러 테스트 클래스가 H2 메모리 DB를 공유하면 데이터 충돌이 발생합니다.
각 테스트 클래스마다 별도의 DB 이름 사용:
```java
// AuthControllerTest
@TestPropertySource(properties = {
    "spring.datasource.url=jdbc:h2:mem:authtest;MODE=MySQL;DB_CLOSE_DELAY=-1", ...
})

// UserControllerTest
@TestPropertySource(properties = {
    "spring.datasource.url=jdbc:h2:mem:usertest;MODE=MySQL;DB_CLOSE_DELAY=-1", ...
})
```

---

## 5. DB

### Backend 컨테이너에서 DB 연결 안 됨
**원인**: `devenv-db` 네트워크에 Backend가 연결 안 됨.
**해결**: backend.yml에 `devenv-db` 네트워크 포함 확인.

### MySQL "Access denied for user"
```bash
docker exec -it db-<project> mysql -uroot -p<DB_ROOT_PASSWORD>
mysql> SHOW GRANTS FOR '<DB_USER>'@'%';
mysql> GRANT ALL ON <DB_NAME>.* TO '<DB_USER>'@'%';
mysql> FLUSH PRIVILEGES;
```

---

## 6. Prometheus / Grafana

### Target down (UP 0)
```bash
# 1. node-exporter가 떠있는지
docker ps | grep node-exporter

# 2. 방화벽이 9100을 막고 있지 않은지
nc -zv <서버IP> 9100

# 3. Prometheus → Status → Targets 에서 에러 메시지 확인
curl http://<MONITORING_IP>:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health=="down")'
```

### Jenkins/GitLab/Nexus target이 down으로 남음 (설치 정상, 후속 설정 필요)
**증상**: Prometheus Targets에서 `jenkins`, `gitlab`, `nexus`가 `down` 상태.

**원인**: 인프라 설치 문제라기보다, 각 서비스에서 메트릭 엔드포인트/플러그인이 기본 비활성.

**해결**:
- Jenkins: Prometheus metrics 관련 플러그인/엔드포인트 활성화 후 재확인
- GitLab: exporter/metrics endpoint 노출 설정 확인
- Nexus: metrics endpoint 또는 exporter 구성 확인

**확인**: 각 서비스 메트릭 URL이 200 응답을 반환하면 Prometheus target은 자동 복구됩니다.

### Grafana 로그인 실패
```bash
docker exec grafana-<project> grafana-cli admin reset-admin-password <new_password>
```

---

## 7. ELK / Loki

### Elasticsearch가 기동 직후 종료
```bash
docker logs es-<project>
# "max virtual memory areas vm.max_map_count [65530] is too low"
sudo sysctl -w vm.max_map_count=262144
```

### Kibana "Kibana server is not ready yet"
- ES가 yellow/green 상태인지 확인
```bash
curl -u elastic:<pwd> http://<LOGGING_IP>:9200/_cluster/health?pretty
```

### Loki가 로그를 안 받음
```bash
# Promtail 로그 확인
docker logs promtail-<project>
# "context deadline exceeded" → Loki URL 도달 가능 여부 확인
```

---

## 8. APM

### Pinpoint Web에 트레이스가 안 보임
- 앱이 Pinpoint Agent와 함께 기동되었는지: `ps -ef | grep pinpoint`
- Collector로 UDP 9995/9996 도달 가능한지: `nc -zuv <APM_IP> 9995`
- `pinpoint.applicationName`이 일치하는지

### SkyWalking에 데이터 없음
- OAP collector(11800) gRPC 도달 확인
- `-Dskywalking.collector.backend_service` 값 확인

---

## 9. 네트워크 / Docker

### Windows Git Bash에서 "docker: command not found"
**원인**: Docker가 Windows 호스트가 아니라 WSL 내부에 설치되어 있는데, Windows 셸에서 실행.

**해결**: Docker 관련 명령은 모두 WSL 내부에서만 실행합니다.
```bash
# 권장: WSL bash 진입 후 실행
wsl.exe -d Ubuntu-22.04 -- bash -lc 'docker version'
```

### "permission denied while trying to connect to docker daemon" + "sudo: a password is required"
**원인**: 일반 사용자로 WSL 진입 시 `/var/run/docker.sock` 접근 권한이 없고, sudo 비밀번호도 미설정.

**해결**: 초기 설치/복구 작업은 root 사용자로 진입해 실행합니다.
```bash
wsl.exe -d Ubuntu-22.04 -u root -- bash
```

### 설정 파일 작성 시 "No such file or directory" (Git Bash -> WSL heredoc 경계)
**원인**: Git Bash에서 `wsl.exe`를 경유할 때 단일 heredoc stdin이 WSL bash로 안정적으로 전달되지 않는 경우가 있음.

**해결**: 외부 heredoc은 WSL bash 실행 블록으로 보내고, 내부 heredoc은 Linux 측에서 처리하는 이중 heredoc 사용.
```bash
wsl.exe -d Ubuntu-22.04 -u root -- bash << 'OUTER'
DEVENV_HOME="${DEVENV_HOME:-$HOME/devenv-<project>}"
cat > "${DEVENV_HOME}/sample.conf" << 'INNER'
KEY=value
INNER
OUTER
```

### 헬스체크 폴링에서 "awk: ... unterminated string"
**원인**: Git Bash가 중첩 인용/이스케이프를 `awk`에 전달하기 전에 오해석.

**해결**: 교차 셸 실행 스크립트에서는 복잡한 `awk` one-liner를 피하고, 단순 변수 + `if/else`로 분기.

### "network devenv-internal not found"
```bash
bash scripts/01-bootstrap.sh
```

### 컨테이너 재기동마다 IP가 바뀜
정상 동작입니다. 컨테이너 간에는 컨테이너명을 사용하세요 (Docker DNS).

### 디스크 가득 참
```bash
# 사용량 분석
docker system df

# 정리
docker system prune -a --volumes  # 위험: 사용 중인 volume 외 모두 삭제
docker image prune -a             # 안전: 미사용 이미지만
docker builder prune              # 빌드 캐시
```

---

## 10. 일반 복구 절차

### 특정 서비스만 재기동
```bash
bash scripts/install-<service>.sh
```

### 전체 재기동 (데이터 유지)
```bash
DEVENV_HOME="${DEVENV_HOME:-$HOME/devenv-<project>}"
cd "$DEVENV_HOME"
for f in docker-compose/docker-compose.*.yml; do
  docker compose --env-file config.env -f "$f" restart
done
```

### 전체 정리 후 재설치 (데이터 손실 주의)
```bash
bash scripts/backup.sh           # 먼저 백업!
bash scripts/teardown.sh         # 'DELETE' 입력
bash scripts/01-bootstrap.sh
bash scripts/install-all.sh
bash scripts/restore.sh backups/<timestamp>  # 복원
```

---

## 도움이 더 필요할 때

오류 메시지 전체와 함께 다음 정보를 정리하면 빠른 진단이 가능합니다:
```
□ 어느 단계에서 발생했나? (preflight / bootstrap / install / runtime)
□ docker ps 출력
□ docker logs <문제 컨테이너> 마지막 50줄
□ scripts/health-check.sh 결과
□ free -h && df -h
□ config.env의 COMPOSE_MODE
```
