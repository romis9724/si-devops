# 헬스체크 가이드

`scripts/health-check.sh`가 자동으로 모든 서버를 점검합니다. 이 문서는 각 서버를 **수동으로** 점검할 때 어떤 엔드포인트/명령을 쓸지 알려줍니다.

---

## 자동 헬스체크

```bash
bash scripts/health-check.sh
```

출력 예시:
```
📦 [기반 인프라]
✅ Bastion SSH  → 10.0.1.10:22 열림
✅ GitLab       → HTTP 200
✅ Nexus        → HTTP 200
✅ Jenkins      → HTTP 200

🚀 [앱 서버]
✅ DB           → 10.0.1.20:3306 열림
⚠️  Backend     → HTTP 502 (예상 200)
✅ Frontend     → HTTP 200

결과: 7 정상  |  1 경고  |  0 장애
```

종료 코드: 장애 0건이면 `0`, 1건 이상이면 `1` (CI/CD에서 활용 가능).

---

## devenv-app 설치 전/후 점검 시나리오

`devenv-security`는 `devenv-app` 설치 여부에 따라 점검 범위가 달라집니다.

### A. pre-app (devenv-app 설치 전)

목표: 보안 인프라 자체가 정상인지 먼저 검증합니다.

```bash
# 1) 보안 서비스 기본 점검
curl -fsS http://<SECURITY_IP>:9000/api/system/status
curl -fsS http://<SECURITY_IP>:8090 > /dev/null
trivy --version

# 2) Jenkins 보안 연동 점검 (앱 파이프라인 병합은 제외)
curl -fsS http://<JENKINS_IP>:8080/login > /dev/null
```

판정 기준:
- SonarQube `status=UP`
- ZAP UI 응답 성공
- Trivy 버전 출력 성공
- Jenkins 접속 가능

### B. post-app (devenv-app 설치 후)

목표: 보안 인프라 + 기존 앱 병합 결과를 함께 검증합니다.

```bash
# 1) pre-app 항목 전체 재검증
bash scripts/health-check.sh

# 2) 앱 병합 파일 점검
test -f sample-apps/backend/sonar-project.properties
test -f sample-apps/frontend/sonar-project.properties

# 3) Jenkins 파이프라인 보안 스테이지 반영 여부 점검
# (Jenkinsfile에 SonarQube/Quality Gate/Trivy/Dependency-Check stage 존재 확인)
```

판정 기준:
- pre-app 기준 모두 만족
- 앱별 `sonar-project.properties` 존재
- Jenkinsfile 보안 stage 반영 확인

---

## 서버별 수동 점검

### Bastion
```bash
nc -zv <BASTION_IP> 22
ssh -i ~/.ssh/bastion_key devops@<BASTION_IP>
```

### GitLab
```bash
curl -fsS http://<GITLAB_IP>:<HOST_PORT_GITLAB>/-/health
# 응답: GitLab OK
docker exec gitlab-<project> gitlab-rake gitlab:check
```

### Nexus
```bash
curl -fsS http://<NEXUS_IP>:8081/service/rest/v1/status
# Docker registry 체크
curl -fsS http://<NEXUS_IP>:5000/v2/
```

### Jenkins
```bash
curl -fsS http://<JENKINS_IP>:8080/login
# Jenkins-CLI로 상태 확인
docker exec jenkins-<project> jenkins-cli list-jobs
```

### DB
```bash
# MySQL
docker exec db-<project> mysqladmin -uroot -p<pwd> ping
# PostgreSQL
docker exec db-<project> pg_isready -U <user>
# MongoDB
docker exec db-<project> mongosh --eval 'db.adminCommand("ping")'
```

### Backend
```bash
curl -fsS http://<BACKEND_IP>:<HOST_PORT_BACKEND>/actuator/health
# 응답 예시: {"status":"UP"}
```

### Frontend
```bash
curl -fsS http://<FRONTEND_IP>:<FRONTEND_PORT>
```

### SonarQube
```bash
curl -fsS http://<SECURITY_IP>:9000/api/system/status
# 응답: {"id":"...","version":"...","status":"UP"}
```

### Prometheus
```bash
curl -fsS http://<MONITORING_IP>:9090/-/healthy
# Target 상태 확인
curl -s http://<MONITORING_IP>:9090/api/v1/targets | jq '.data.activeTargets[].health'
```

### Grafana
```bash
curl -fsS http://<MONITORING_IP>:3001/api/health
# 응답: {"database":"ok","version":"..."}
```

### APM
```bash
# Pinpoint
curl -fsS http://<APM_IP>:8079
# SkyWalking
curl -fsS http://<APM_IP>:8079
# Elastic APM
curl -fsS http://<APM_IP>:8200
```

### 로그 스택
```bash
# ELK
curl -fsS -u elastic:<pwd> http://<LOGGING_IP>:9200/_cluster/health
curl -fsS http://<LOGGING_IP>:5601/api/status

# Loki
curl -fsS http://<LOGGING_IP>:3100/ready
curl -fsS http://<LOGGING_IP>:3100/metrics | head
```

---

## 컨테이너 헬스 상태

```bash
# 전체 컨테이너 상태
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# 특정 컨테이너 헬스
docker inspect --format '{{.State.Health.Status}}' <컨테이너명>

# 헬스체크 로그
docker inspect --format '{{json .State.Health}}' <컨테이너명> | jq
```

---

## 정기 점검 체크리스트

### 매일
```
□ scripts/health-check.sh — 전체 서비스 정상 응답
□ 디스크 사용률 < 80%
□ Docker 컨테이너 모두 running
□ 백업 스크립트 정상 실행 (cron 로그)
```

### 매주
```
□ Grafana 대시보드 — 비정상 메트릭 패턴 검토
□ Prometheus alert — 발생/해결 이력
□ SonarQube Quality Gate — 누적 부채 추세
□ Trivy — 신규 취약점
```

### 매월
```
□ 백업 복원 테스트 (별도 환경)
□ OS / Docker 보안 패치
□ Jenkins 플러그인 업데이트
□ 사용자 계정 / 권한 검토
```
