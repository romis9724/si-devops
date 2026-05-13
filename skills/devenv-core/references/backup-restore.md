# 백업 / 복원 가이드

## 무엇을 백업하는가?

| 대상 | 위치 | 방법 |
|------|------|------|
| GitLab 데이터 | volume `gitlab_data`, `gitlab_config` | tar 압축 |
| Jenkins 설정/잡 | volume `jenkins_home` | tar 압축 |
| Nexus artifact | volume `nexus_data` | tar 압축 |
| DB 데이터 | volume `mysql_data` 등 + SQL 덤프 | mysqldump/pg_dump |
| SonarQube | volume `sonar_data`, `sonar_db` | tar 압축 |
| Grafana 대시보드 | volume `grafana_data` | tar 압축 |
| Prometheus 메트릭 | volume `prometheus_data` | tar 압축 |
| config.env (비밀번호) | 파일 | 사본 |

## 사용법

### 백업
```bash
bash scripts/backup.sh
# → backups/<timestamp>/ 디렉토리에 저장
```

`backup.sh`는 30일 이상 된 백업을 자동 정리합니다.

### 복원 (위험! 기존 데이터 덮어쓰기)
```bash
bash scripts/restore.sh backups/20240115_103000
```

복원은 다음 순서로 진행됩니다:
1. 'yes' 확인 입력
2. 모든 컨테이너 중지
3. 볼륨 데이터 덮어쓰기
4. DB 컨테이너 기동 → SQL 덤프 import
5. 사용자가 `install-all.sh`로 전체 재기동

---

## 운영 권장사항

### 1. 정기 백업 자동화 (cron)

```bash
# crontab -e
0 3 * * * cd /opt/devenv-{project} && bash scripts/backup.sh >> /var/log/devenv-backup.log 2>&1
```

매일 새벽 3시 자동 백업.

### 2. 외부 저장소로 오프사이트 백업

로컬 디스크 손상에 대비하여 백업본을 외부로도 보내야 합니다.

```bash
# AWS S3
aws s3 sync backups/ s3://my-devenv-backups/ --delete --exclude "*" --include "*.tar.gz" --include "*.sql"

# rsync
rsync -avz --delete backups/ backup-server:/backups/devenv-{project}/
```

### 3. 백업 복구 테스트 (월 1회)

백업이 실제로 복구 가능한지 정기 테스트가 필수입니다.

```bash
# 별도 테스트 환경에서
bash scripts/restore.sh /path/to/backup
bash scripts/health-check.sh
```

### 4. GitLab 자체 백업 사용 (권장)

GitLab은 자체 백업 명령을 제공합니다. 더 일관성 있고 빠릅니다.

```bash
docker exec gitlab-{project} gitlab-backup create
# /var/opt/gitlab/backups/ 에 .tar 파일 생성
docker cp gitlab-{project}:/var/opt/gitlab/backups/ ./backups/gitlab/
```

---

## 디스크 사용량 모니터링

백업이 누적되어 디스크가 가득 차는 것을 막기 위해:

```bash
# 백업 디렉토리 크기 확인
du -sh backups/

# 30일 초과 자동 삭제 (backup.sh에 포함)
find backups -maxdepth 1 -type d -mtime +30 -exec rm -rf {} +
```

Grafana 대시보드에 디스크 사용률 알람 설정 권장.

---

## 재해 복구 시나리오

### Case 1: 단일 서비스 데이터 손상
```bash
docker compose -f docker-compose/docker-compose.<service>.yml down -v
# restore.sh로 해당 볼륨만 복구
```

### Case 2: 호스트 전체 손실
```bash
# 1. 새 호스트에 Docker 설치
# 2. 백업 디렉토리 복사
# 3. config.env 복사
bash scripts/01-bootstrap.sh
bash scripts/restore.sh backups/<timestamp>
bash scripts/install-all.sh
```

### Case 3: 부분 손실 (예: DB만)
```bash
docker compose -f docker-compose/docker-compose.db.yml down -v
docker volume rm devenv-{project}_mysql_data
bash scripts/install-db.sh
# DB 컨테이너 기동 후 SQL 덤프만 import
docker exec -i db-{project} mysql -uroot -p<pwd> < backups/<timestamp>/db.sql
```
