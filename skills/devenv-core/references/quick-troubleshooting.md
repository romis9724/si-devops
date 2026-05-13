# Quick Troubleshooting (Lite)

`devenv-core` 설치/운영에서 가장 자주 발생하는 핵심 이슈만 정리한 경량 문서입니다.
상세 분석이 필요하면 `references/troubleshooting.md`를 확인하세요.

## 팀 표준값 (single 모드)

- PROJECT_NAME 예시: `myproject`
- INTERNAL_NETWORK: `10.0.1.0/24`
- Bastion/GitLab/Nexus/Jenkins IP: `10.0.1.10/11/12/13`
- 고정 포트: `2222`, `2223`, `8082`, `8080`, `8081`, `5000`

컨테이너명은 `-<project>` 접미사를 포함합니다.
예: `gitlab-myproject`, `jenkins-myproject`, `nexus-myproject`

## 환경 분기 (WSL / Docker Desktop)

- WSL Ubuntu 직접 Docker:
  - Docker daemon 설정 파일: `/etc/docker/daemon.json`
  - `sudo service docker restart` 사용
- Docker Desktop:
  - Docker Desktop > Settings > Docker Engine에서 설정
  - WSL 내부에서 daemon 재시작 대신 Desktop 재시작

## 우선 해결 순서 (Infra/DevOps/Harness)

아래 5개를 먼저 처리하면, 설치 실패 재현율이 가장 크게 줄어듭니다.

1) **P0 - 파괴적 compose 옵션 제거**
- `install-{bastion,gitlab,nexus,jenkins}.sh`에서 `--remove-orphans`를 제거합니다.
- 동일 `--project-name`을 공유하는 설치 스크립트에서 `--remove-orphans`는 선행 서비스 삭제를 유발합니다.

2) **P1 - 환경 부트스트랩 자동화**
- 설치 전에 아래를 자동 점검/보정합니다.
  - Ubuntu-22.04 설치 + OOBE 완료(일반 사용자 생성)
  - `vm.max_map_count=262144`
  - Docker `insecure-registries` (`127.0.0.1:5000`, `localhost:5000`, `10.0.1.12:5000`)

3) **P1 - WSL 호출 경계 단일화**
- `wsl.exe` 호출은 PowerShell 경로로만 실행합니다.
- 인라인 `bash -c "sed ..."`는 금지하고, `.patch.sh` 파일 실행 패턴을 사용합니다.

4) **P1 - 설치 오케스트레이션 안정화**
- 고정 sleep/PID wait 대신 readiness 기반 대기만 사용합니다.
  - 순서: `bastion -> gitlab(/users/sign_in) -> nexus(/service/rest/v1/status) -> jenkins(/login)`
  - timeout/retry: `3회`, `5s/10s/20s`

5) **P2 - 하네스 게이트 강화**
- 설치 성공 판정을 "컨테이너 기동"이 아니라 "필수 서비스 준비 완료 + 핵심 포트 응답"으로 변경합니다.
- Bastion 내부 IP 기반 WARN은 benign으로 분리하고, 호스트 경로(`127.0.0.1:2222`)를 필수 체크로 둡니다.

6) **P1 - 설치 시점 계정 강제 동기화**
- `install-all.sh`는 설치 흐름에서 `post-install.sh`를 자동 실행합니다.
- 이 단계에서 공통 관리자 비밀번호 기준으로 Nexus/Jenkins 계정을 강제 동기화합니다.
- 운영 중 주기 재설정은 수행하지 않고, 설치/재설치 시점에만 적용합니다.

## 0) 공통 점검 5개

```bash
docker ps -a --format 'table {{.Names}}\t{{.Status}}'
docker logs gitlab-myproject --tail 100
docker logs jenkins-myproject --tail 100
docker logs nexus-myproject --tail 100
bash scripts/health-check.sh
```

## 1) GitLab이 오래 걸리거나 접속 실패

- 증상: 설치가 GitLab 단계에서 오래 대기, 또는 초기 502
- 원인: 초기 마이그레이션/재설정 지연
- 조치:

```bash
docker logs -f gitlab-myproject
curl -I http://localhost:8082/users/sign_in
```

`200 OK`가 반환될 때까지 재설치하지 말고 대기합니다.

## 2) Jenkins docker.sock 권한 오류

- 증상: `permission denied while trying to connect to docker daemon`
- 조치:

```bash
getent group docker
sed -i 's/user: "1000:[0-9]*/user: "1000:989/' docker-compose/docker-compose.jenkins.yml
docker compose -f docker-compose/docker-compose.jenkins.yml up -d
```

참고:
- Docker Desktop 환경은 GID가 `999`인 경우가 많음
- 실제 값은 `getent group docker` 결과를 우선 적용

## 3) Jenkins에서 docker 명령 없음

- 증상: Pipeline에서 `docker: command not found`
- 조치:

```bash
docker compose -f docker-compose/docker-compose.jenkins.yml build --no-cache
docker compose -f docker-compose/docker-compose.jenkins.yml up -d
docker exec jenkins-myproject docker --version
```

## 4) Jenkins 빌드 트리거 403 (CSRF)

- 증상: GitLab/Webhook 또는 API 트리거가 403
- 조치:

```bash
CRUMB_JSON=$(curl -sS -u "admin:<PASSWORD>" "http://localhost:8080/crumbIssuer/api/json")
CRUMB_FIELD=$(echo "$CRUMB_JSON" | jq -r '.crumbRequestField')
CRUMB_VALUE=$(echo "$CRUMB_JSON" | jq -r '.crumb')
curl -sS -X POST -u "admin:<PASSWORD>" -H "${CRUMB_FIELD}: ${CRUMB_VALUE}" \
  "http://localhost:8080/job/<job-name>/build"
```

## 5) Nexus docker login/push 실패

- 증상: `401 Unauthorized`, `denied`, `no basic auth credentials`
- 조치 요약:
  - Nexus Realm에서 Docker Bearer Token 활성화
  - Docker daemon insecure registry에 `10.0.1.12:5000` 추가
  - `docker login 10.0.1.12:5000` 재시도

WSL Ubuntu 예시:

```bash
echo '{"insecure-registries": ["10.0.1.12:5000"]}' | sudo tee /etc/docker/daemon.json
sudo service docker restart
docker login 10.0.1.12:5000
```

## 6) 포트 충돌

- 기본 포트: `2222`, `2223`, `8082`, `8080`, `8081`, `5000`
- 점검:

```bash
ss -tln | egrep '(:2222|:2223|:8082|:8080|:8081|:5000)'
```

점유 프로세스를 정리한 뒤 `bash scripts/install-all.sh` 재실행.

## 7) 최종 복구

```bash
bash scripts/teardown.sh
bash scripts/install-all.sh
bash scripts/health-check.sh
```

주의: `teardown.sh`는 데이터 삭제를 동반할 수 있습니다.

## 운영 팁 (토큰/재설치 최소화)

- GitLab 초기 기동 지연은 재설치보다 대기가 안전합니다.
- 포트 충돌 시 포트를 바꾸지 말고 점유 프로세스를 먼저 정리합니다.
- 비밀번호/토큰은 `config.env`만 사용하고 채팅/로그에 평문 출력 금지.
