# devenv-core Runbook

운영/장애 대응 시 가장 먼저 확인할 명령과 절차를 1페이지로 정리한 문서입니다.

## 1. 설치 직후 확인

```bash
cd ~/devenv-<project>
python3 scripts/agent-orchestrator.py
```

확인 기준:
- GitLab: `http://localhost:8082/users/sign_in`
- Nexus: `http://localhost:8081/service/rest/v1/status`
- Jenkins: `http://localhost:8080/login`
- Bastion: `ssh -p 2222 devops@<BASTION_IP>`

## 2. 일일 운영 점검

```bash
docker ps -a --format 'table {{.Names}}\t{{.Status}}'
docker stats --no-stream
free -h && df -h
```

## 3. 서비스 단건 재기동

```bash
cd ~/devenv-<project>
bash scripts/install-bastion.sh
bash scripts/install-gitlab.sh
bash scripts/install-nexus.sh
bash scripts/install-jenkins.sh
```

주의: 설치 순서 의존성이 있으면 `install-all.sh`를 사용합니다.

## 4. 전체 재적용 (권장 순서)

```bash
cd ~/devenv-<project>
bash scripts/install-all.sh
bash scripts/health-check.sh
```

설치 시 계정 동기화 정책:
- `install-all.sh`는 설치 흐름 안에서 `post-install.sh`를 자동 실행합니다.
- 이 단계에서 공통 관리자 비밀번호를 기준으로 Nexus/Jenkins 계정을 강제 동기화합니다.
- 운영 중 주기 재설정은 수행하지 않으며, 설치/재설치 시점에만 적용합니다.

## 4-1. 정기 백업 (권장)

```bash
cd ~/devenv-<project>
bash scripts/backup.sh                        # 즉시 1회 백업
bash scripts/enable-cron-backup.sh            # 매일 03:00 자동 백업 등록
                                              # (systemd --user timer 우선, crontab fallback)
```

백업 결과는 `backups/<timestamp>`에 저장됩니다. WSL2에서 호스트 Windows가 idle로 distro를 종료하면 cron/timer도 멈춥니다. 진정한 24/7 백업은 호스트 Windows의 Scheduled Task로 별도 등록:

```powershell
# 관리자 PowerShell
cd ~\devenv-<project>
.\scripts\install-windows-task.ps1 -Project <project>
```

## 4-2. TLS 인증서 (선택)

`install-all.sh`가 `SSL_TYPE != none`일 때 `ssl-init.sh`를 자동 호출하여 인증서를 준비합니다.

수동 재발급:

```bash
bash scripts/ssl-init.sh              # SSL_TYPE에 따라 분기
bash scripts/ssl-init.sh --force      # self-signed 강제 재생성 (만료 임박)
```

> **letsencrypt 발급 시**: standalone 모드는 80 포트가 필요하므로 GitLab을 잠시 정지 후 실행:
> ```bash
> docker compose -f docker-compose/docker-compose.gitlab.yml stop
> bash scripts/ssl-init.sh
> docker compose -f docker-compose/docker-compose.gitlab.yml start
> ```
> WSL2 환경에서는 Windows Defender Firewall이 80 포트를 차단할 수 있어 DNS-01 challenge 또는 외부 reverse proxy 사용을 권장합니다.

## 4-3. 통합 진단

```bash
bash scripts/devenv-doctor.sh         # auto 분기 (컨테이너 상태 감지)
bash scripts/devenv-doctor.sh all     # preflight + health + smoke 전체
```

## 5. 장애 1차 대응

```bash
docker logs gitlab-<project> --tail 100
docker logs nexus-<project> --tail 100
docker logs jenkins-<project> --tail 100
```

판단:
- 빠른 복구 가능: 단건 재기동
- 원인 불명/반복 장애: `references/quick-troubleshooting.md` 확인
- 심층 분석 필요: `references/troubleshooting.md` 확인

## 6. teardown / 재구축 (3단계 안전 절차)

`teardown.sh`는 컨테이너·볼륨·네트워크를 제거하므로 **반드시 단계적으로** 실행합니다.

### 6-1. 사전 점검 (안전, 변경 없음)

```bash
cd ~/devenv-<project>
bash scripts/teardown.sh --dry-run     # 어떤 명령이 실행될지만 출력
```

### 6-2. 컨테이너만 내리기 (데이터 유지)

```bash
bash scripts/teardown.sh --keep-volumes   # 볼륨 보존, 컨테이너만 down
bash scripts/install-all.sh                # 재기동 시 데이터 유지
```

### 6-3. 전체 제거 (데이터 손실)

백업이 있는지 먼저 확인:

```bash
ls backups/                                 # 최근 백업 시점 확인
bash scripts/backup.sh                      # 백업이 없으면 먼저 실행
```

전체 teardown + 재설치:

```bash
bash scripts/teardown.sh                    # 5초 대기 + yes 확인 후 진행
bash scripts/install-all.sh
bash scripts/health-check.sh
```

비밀 파일까지 완전 삭제 (재배포 시):

```bash
bash scripts/teardown.sh --purge-secrets    # secrets/*.env shred 포함
```

### 데이터 복구

```bash
bash scripts/restore.sh backups/<timestamp>
bash scripts/install-all.sh
bash scripts/health-check.sh
```

> teardown.sh는 core 외에 security(SonarQube/ZAP), observe(Prometheus/Grafana/Loki), app(backend/frontend/mysql) 컨테이너까지 일괄 정리합니다. 보안/관측 단독 정리는 향후 `--scope=security` 등 옵션 예정.

## 7. 보안 운영 원칙

- 비밀번호는 `config.env`만 사용, Git 저장소 커밋 금지
- 공통 관리자 비밀번호 변경 시 `config.env` 반영 후 서비스 재적용
- 토큰/비밀값은 채팅/로그에 그대로 출력하지 않기

## 8. 변경 회귀 검증 (릴리즈 전)

```bash
bash scripts/verify-generator.sh
```

`[OK] verify-generator passed`가 출력되면 생성기 핵심 정책 회귀가 없음을 의미합니다.

## 9. 에이전트 실행 (저토큰 모드, 기본)

```bash
cd ~/devenv-<project>
python3 scripts/agent-orchestrator.py
python3 scripts/agent-orchestrator.py --quiet
python3 scripts/agent-orchestrator.py --jsonl-file .agent-logs/status.jsonl
```

정상 출력은 JSON 1줄 위주로 유지되며, 실패 시에만 최소 로그를 추가로 출력합니다.

`sudo -v`가 필요한 환경이면 먼저 1회 실행하세요.

```bash
sudo -v
```
