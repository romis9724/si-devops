# 설치 후 초기 설정 가이드

`install-all.sh`로 컨테이너만 기동된 상태입니다. 각 서비스의 **초기 설정**을 이 순서대로 진행하세요.

---

## 0. 비밀번호 확인

```bash
grep PASSWORD config.env
```

| 변수 | 용도 |
|------|------|
| GITLAB_ROOT_PASSWORD | GitLab root 로그인 |
| JENKINS_ADMIN_PASSWORD | Jenkins admin 로그인 |
| NEXUS_ADMIN_PASSWORD | Nexus admin 로그인 |
| SONAR_ADMIN_PASSWORD | SonarQube admin 로그인 |
| GRAFANA_PASSWORD | Grafana admin 로그인 |
| DB_PASSWORD / DB_ROOT_PASSWORD | DB 접속 |

> **주의**: Nexus 초기 비밀번호는 컨테이너 내부의 `/nexus-data/admin.password` 파일에 있습니다.
> ```bash
> docker exec nexus-<project> cat /nexus-data/admin.password
> ```
> 첫 로그인 시 변경 화면에서 `NEXUS_ADMIN_PASSWORD`로 변경하세요.

---

## 1. GitLab 초기 설정

```
URL: http://<GITLAB_IP>:<HOST_PORT_GITLAB>
계정: root / <GITLAB_ROOT_PASSWORD>
```

체크리스트:
```
□ Admin → Settings → General → Sign-up restrictions: 가입 비활성화 확인
□ 그룹 생성 (예: myproject)
□ 프로젝트 생성 (backend, frontend)
□ 사용자 추가 → 그룹에 멤버 등록
□ 프로젝트별 Branch protection 설정 (main, develop)
□ 모든 사용자 2FA 강제 (Settings → Sign-in restrictions)
□ Webhook URL 등록 (CI/CD 가이드 참고)
```

---

## 2. Nexus 초기 설정

```
URL: http://<NEXUS_IP>:8081
초기 계정: admin / <컨테이너 내부 admin.password>
```

체크리스트:
```
□ admin 비밀번호 변경 (config.env의 NEXUS_ADMIN_PASSWORD로)
□ Anonymous Access 비활성화
□ 저장소 생성:
   - maven-snapshots (Maven 스냅샷)
   - maven-releases (Maven 릴리스)
   - npm-private (npm 사설)
   - docker-hosted (port 5000) — 이미지 push용
   - docker-proxy (DockerHub 프록시)
   - docker-group (위 두 개 묶기)
□ Realm 활성화: Docker Bearer Token
□ Cleanup Policies: 30일 미사용 SNAPSHOT 자동 삭제
```

---

## 3. Jenkins 초기 설정

```
URL: http://<JENKINS_IP>:8080
계정: admin / <JENKINS_ADMIN_PASSWORD>
```

체크리스트:
```
□ Manage Plugins → Available → 필수 플러그인 설치
   (cicd-pipeline-guide.md의 플러그인 목록 참고)
□ Manage Credentials → 자격증명 등록:
   - gitlab-token (Secret text)
   - nexus-credentials (Username/Password)
   - sonarqube-token (Secret text)
   - bastion-ssh-key (SSH key)
□ Configure System → SonarQube servers 추가
□ Configure System → GitLab connections 추가
□ Configure System → Nexus 추가 (Sonatype Nexus Platform Plugin)
□ Manage Jenkins → Security → Authorization → Matrix-based security
□ 첫 Pipeline Job 생성
   - SCM: GitLab (gitlab-token 사용)
   - Build Trigger: Build when a change is pushed to GitLab
   - Pipeline: Jenkinsfile from SCM
```

Jenkinsfile 템플릿: `configs/jenkins/Jenkinsfile.template`

---

## 4. SonarQube 초기 설정

```
URL: http://<SECURITY_IP>:9000
초기 계정: admin / admin → 첫 로그인 시 변경
```

체크리스트:
```
□ admin 비밀번호 변경 (config.env의 SONAR_ADMIN_PASSWORD로)
□ My Account → Security → Generate Tokens → Jenkins용 토큰 발급
□ Quality Gates → "Sonar way" 정책 검토 또는 새로 정의
   (cicd-pipeline-guide.md의 Quality Gate 정책 참고)
□ Project 추가 → "Locally" → Jenkins에서 분석 실행 안내
□ Webhook 등록 (Jenkins로 결과 전달)
   Administration → Configuration → Webhooks
   URL: http://<JENKINS_IP>:8080/sonarqube-webhook/
```

---

## 5. 모니터링 (Grafana) 초기 설정

```
URL: http://<MONITORING_IP>:3001
계정: admin / <GRAFANA_PASSWORD>
```

체크리스트:
```
□ Data Sources 추가:
   - Prometheus: http://prometheus:9090
   - Loki (LOG_STACK=loki일 때): http://loki:3100
   - Elasticsearch (ELK일 때): http://<LOGGING_IP>:9200
□ 대시보드 import (모니터링 가이드의 ID 사용):
   - 1860 (Node Exporter Full)
   - 893 (Docker Monitoring)
   - 9964 (Jenkins)
   - 11955 (GitLab)
□ Alerting → Contact points → Slack/Email 연결
□ Alert rules → 권장 알람 규칙 추가
   (monitoring-stack.md의 권장 알람 참고)
```

---

## 6. 보안 점검 자동화

### Trivy (Jenkins에서 실행)
```bash
# Jenkins Pipeline Stage
sh """
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    aquasec/trivy:latest image --exit-code 1 --severity HIGH,CRITICAL \
    ${NEXUS_IP}:5000/${PROJECT_NAME}-backend:${BUILD_NUMBER}
"""
```

### OWASP ZAP DAST (배포 후)
```bash
docker exec zap-<project> zap-cli quick-scan \
  --self-contained -o '-config api.disablekey=true' \
  http://<BACKEND_IP>:<HOST_PORT_BACKEND>
```

---

## 7. APM 에이전트 주입

`monitoring-stack.md`의 Dockerfile 예시 참고. Backend의 빌드 단계에서 Agent를 이미지에 포함시키고, 실행 시 collector 주소를 `<APM_IP>`로 지정.

---

## 8. 백업 자동화 등록

```bash
# crontab -e
0 3 * * * DEVENV_HOME="${DEVENV_HOME:-$HOME/devenv-<project>}"; cd "$DEVENV_HOME" && bash scripts/backup.sh >> /var/log/devenv-backup.log 2>&1
0 4 * * 0 DEVENV_HOME="${DEVENV_HOME:-$HOME/devenv-<project>}"; cd "$DEVENV_HOME" && rsync -az backups/ backup-server:/devenv/<project>/
```

---

## 9. SSL/TLS 적용 (선택)

도메인이 있고 `SSL_TYPE=letsencrypt`인 경우, 별도 reverse proxy(Nginx + certbot 또는 Traefik)를 추가하여 HTTPS 종단처리하는 것을 권장합니다. 본 스킬은 reverse proxy를 자동 생성하지 않습니다 (운영 정책에 따라 다름).

추천 구성:
- Traefik 또는 Nginx + certbot 컨테이너 추가
- 80/443에서 HTTPS 종단
- 내부 서비스는 HTTP 그대로 유지

---

## 10. 사용자에게 공지할 정보

팀에게 공유:
```
========================================
🚀 개발 환경 준비 완료
========================================
GitLab    : http://<GITLAB_IP>:<port>
Jenkins   : http://<JENKINS_IP>:8080
Nexus     : http://<NEXUS_IP>:8081
SonarQube : http://<SECURITY_IP>:9000
Grafana   : http://<MONITORING_IP>:3001

SSH 접근  : ssh -J devops@<BASTION_IP> <user>@<server_ip>

본인 GitLab 계정 발급 받으세요. (관리자 문의)
첫 로그인 후 2FA 등록 필수.
========================================
```
