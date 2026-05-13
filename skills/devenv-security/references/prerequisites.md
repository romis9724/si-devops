# 설치 전 사전 점검 (Prerequisites)

`scripts/00-preflight.sh`가 자동으로 점검하지만, 사람이 직접 확인하면 좋은 항목들을 정리합니다.

> ⚠️ WSL2 사용자라면 다음 두 가지를 추가로 점검하세요 (자세히 → `references/lessons-learned.md`):
> 1. **`sg docker -c 'docker info'`** 가 성공해야 함 — systemd `--user` unit에서 docker 그룹 미적용 회피용
> 2. **MSYS Git Bash로 wsl 명령 호출 시** `MSYS_NO_PATHCONV=1` prefix — `/mnt/c` 경로 변환 회피

---

## 1. 필수 도구

| 도구 | 최소 버전 | 확인 명령 |
|------|----------|----------|
| Docker | 20.10+ | `docker --version` |
| Docker Compose | v2 | `docker compose version` |
| curl | 7.x+ | `curl --version` |
| openssl | 1.1+ | `openssl version` |
| netcat (nc) | - | `nc -h 2>&1 \| head -1` |
| envsubst | - | `envsubst --version \| head -1` |

설치:
```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER && newgrp docker
sudo apt install -y gettext-base netcat-openbsd

# RHEL/CentOS
sudo dnf install -y docker docker-compose-plugin gettext nmap-ncat
sudo systemctl enable --now docker
```

---

## 2. 리소스 요구사항 (모드별)

### 단일 서버 모드 (single)
| 항목 | 최소 | 권장 |
|------|------|------|
| CPU | 8 core | 16 core |
| RAM | 24GB | 32GB |
| 디스크 | 200GB SSD | 500GB SSD |

### 다중 서버 모드 (multi) — 서버당
| 서버 | CPU | RAM | 디스크 |
|------|-----|-----|--------|
| Bastion | 1 | 1GB | 10GB |
| GitLab | 4 | 8GB | 100GB |
| Nexus | 2 | 4GB | 200GB |
| Jenkins | 2 | 4GB | 50GB |
| DB | 4 | 8GB | 100GB |
| Backend/Frontend | 2 | 4GB | 30GB |
| 보안점검 | 4 | 8GB | 50GB |
| 모니터링 | 2 | 4GB | 100GB |
| APM | 4 | 8GB | 100GB |
| 로그수집 | 4 | 8GB | 500GB |

---

## 3. 커널 파라미터

Elasticsearch / SonarQube에 필수입니다.

```bash
# 현재 값 확인
sysctl vm.max_map_count

# 임시 적용
sudo sysctl -w vm.max_map_count=262144

# 영구 적용
echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

---

## 4. 포트 점유 확인 (단일 서버 모드)

```bash
# 사용 중인 포트 확인
ss -tln

# 충돌 가능 포트 일괄 확인
for p in 22 2222 8080 50000 8082 8081 5000 8083 3000 3306 9000 9090 3001 3100 5601 9200 8079 8088; do
  if ss -tln | grep -q ":$p "; then echo "⚠️  Port $p in use"; fi
done
```

---

## 5. 클라우드 보안 그룹 / 방화벽

`references/cloud-firewall.md` 참조.

기본 원칙:
- **외부에서 직접 접근 가능: 22(Bastion), 80/443(Frontend, 도메인 사용 시)**
- **내부망(팀 IP)만: 8080(Jenkins), 80(GitLab), 8081(Nexus), 9000(SonarQube), 3001(Grafana)**
- **서버 간만: DB 포트, Prometheus, Loki, ES, APM Collector**

---

## 6. DNS / 도메인 (선택)

도메인을 사용한다면 다음 레코드를 미리 등록하세요:

```
gitlab.dev.example.com   A  10.0.1.11
nexus.dev.example.com    A  10.0.1.12
jenkins.dev.example.com  A  10.0.1.13
sonar.dev.example.com    A  10.0.1.30
grafana.dev.example.com  A  10.0.1.40
apm.dev.example.com      A  10.0.1.41
logs.dev.example.com     A  10.0.1.42
```

---

## 7. 시간 동기화 (NTP)

여러 서버 간 시간 차이는 인증서/로그 분석/메트릭 수집을 망칩니다.

```bash
# 확인
timedatectl

# Ubuntu — chrony 또는 systemd-timesyncd 사용
sudo timedatectl set-ntp true
```
