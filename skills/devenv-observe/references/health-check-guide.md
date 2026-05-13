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

## devenv-app 연동 전/후 검증 (실전 체크리스트)

아래 순서로 점검하면 "설치는 됐는데 서버 간 연결이 안됨" 문제를 가장 빨리 찾을 수 있습니다.

### 1) 네트워크 조인 확인 (가장 중요)

```bash
# 앱 컨테이너가 devenv-internal 네트워크에 붙어있는지 확인
docker inspect backend-<project> --format '{{json .NetworkSettings.Networks}}' | jq
docker inspect frontend-<project> --format '{{json .NetworkSettings.Networks}}' | jq

# 미연결이면 연결
docker network connect devenv-internal backend-<project> || true
docker network connect devenv-internal frontend-<project> || true
```

### 2) DNS 기반 통신 확인 (컨테이너명 해석)

```bash
# Prometheus 컨테이너에서 backend DNS 확인
docker exec prometheus-<project> getent hosts backend-<project>

# Grafana 컨테이너에서 prometheus/loki DNS 확인
docker exec grafana-<project> getent hosts prometheus-<project>
docker exec grafana-<project> getent hosts loki-<project>
```

### 3) 프로토콜/포트 확인 (서비스별)

```bash
# Prometheus
curl -fsS http://<MONITORING_IP>:9090/-/healthy

# Loki
curl -fsS http://<LOGGING_IP>:3100/ready

# SkyWalking OAP
curl -fsS http://<APM_IP>:12800/healthcheck

# Grafana datasource 연결 상태(HTTP 200/401이면 엔드포인트 생존)
curl -I http://<MONITORING_IP>:3001/api/health
```

### 4) 앱 연동 확인 (devenv-app 설치 후)

```bash
# Backend metrics 노출 확인
curl -fsS http://<BACKEND_IP>:<HOST_PORT_BACKEND>/metrics | head
# Spring Boot인 경우
curl -fsS http://<BACKEND_IP>:<HOST_PORT_BACKEND>/actuator/prometheus | head

# Prometheus 타겟에 backend가 올라왔는지 확인
curl -s http://<MONITORING_IP>:9090/api/v1/targets \
  | jq '.data.activeTargets[] | {job: .labels.job, health: .health, scrapeUrl: .scrapeUrl}'
```

### 5) 실패 시 즉시 확인할 로그

```bash
docker logs prometheus-<project> --tail 200
docker logs grafana-<project> --tail 200
docker logs loki-<project> --tail 200
docker logs promtail-<project> --tail 200
docker logs sw-oap-<project> --tail 200
```

---

## 의존성 문제 대응 가이드 (선택 설치 시)

### 공통 원칙

- 관측성 스택 설치 전 `devenv-core`의 네트워크/기본 서비스가 정상인지 먼저 확인
- `depends_on`은 시작 순서만 보장하고 "정상 동작"은 보장하지 않으므로 healthcheck를 반드시 함께 사용
- 앱 연동은 IP 고정보다 Docker DNS(`service-<project>`)를 우선 사용

### 자주 발생하는 의존성 충돌

- `Prometheus ↔ Backend`
  - 증상: target `DOWN`
  - 조치: backend metrics endpoint 노출 여부, prometheus scrape target 주소 확인
- `Grafana ↔ Prometheus/Loki`
  - 증상: 대시보드 `No data`
  - 조치: datasource URL이 컨테이너 DNS 기준인지 확인 (`prometheus-<project>`, `loki-<project>`)
- `Promtail ↔ Docker 로그`
  - 증상: 로그 미수집
  - 조치: `/var/lib/docker/containers` 마운트 + docker_sd_configs 사용 여부 점검
- `SkyWalking Agent ↔ OAP`
  - 증상: 서비스 맵 비어있음
  - 조치: 앱 컨테이너와 OAP 네트워크 동일 여부, agent backend 주소 확인

### 설치 순서 권장

```text
1) Prometheus + Grafana
2) Loki + Promtail (또는 ELK)
3) APM (SkyWalking/Pinpoint/Elastic APM)
4) devenv-app 연동(/metrics, 로그 라벨, APM agent)
5) Prometheus targets / Grafana datasource / APM UI 최종 검증
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
