# 보안 강화 가이드 (Security Hardening)

본 스킬은 **개발 환경**용입니다. 운영 환경 수준의 보안이 필요하면 추가 강화가 필요합니다.

---

## 공통 원칙

1. **최소 권한** — 모든 서비스는 root가 아닌 전용 사용자로 실행 (Jenkins는 docker socket 접근을 위해 docker 그룹만)
2. **격리** — DB는 `devenv-db` (internal) 네트워크로 외부 인터넷 차단
3. **노출 최소화** — 외부 직접 노출은 Bastion(SSH)만, 나머지는 Bastion 경유 SSH 터널 또는 VPN
4. **자동 비밀번호 생성** — `generate-configs.sh`가 강력한 랜덤 비밀번호를 자동 생성
5. **권한 분리** — config.env는 `chmod 600`, Git 커밋 금지

---

## OS 기본 보안 (Bastion / 모든 서버)

### SSH 강화 (`/etc/ssh/sshd_config`)
```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers devops
Protocol 2
```

### fail2ban
```bash
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban
```

### 자동 보안 패치
```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

---

## Bastion Host 추가 설정

### 화이트리스트 IP만 SSH 허용 (예: 팀 IP 대역)
```bash
# UFW 사용
sudo ufw allow from <팀_IP_대역> to any port 22 proto tcp
sudo ufw deny 22/tcp
sudo ufw enable

# iptables 직접
iptables -A INPUT -p tcp --dport 22 -s <팀_IP_대역> -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j DROP
```

### 세션 타임아웃
```bash
echo "TMOUT=600" | sudo tee -a /etc/profile
```

---

## Jenkins 보안

### docker socket 접근의 위험성
Jenkins compose는 `/var/run/docker.sock`을 마운트합니다. 이는 **Jenkins가 호스트의 모든 컨테이너를 제어할 수 있음**을 의미합니다. 실무에서는 다음 중 하나로 위험을 줄입니다:

1. **DinD(Docker-in-Docker) 사용** — 별도 Docker 데몬을 컨테이너 내부에서 운영 (성능/디스크 트레이드오프)
2. **빌드 전용 Agent 분리** — Jenkins controller에서 docker.sock을 빼고, 별도 Agent VM이 빌드 수행
3. **Sysbox/Kata** — 격리된 컨테이너 런타임 사용

본 스킬은 단순화를 위해 socket 마운트 방식을 사용합니다. 운영 환경에서는 위 옵션 검토 권장.

### Jenkins 매트릭스 권한 (초기 설정 후)
```groovy
// Manage Jenkins → Security → Authorization → Matrix-based security
// admin: Overall/Administer
// developer: Overall/Read, Job/Build, Job/Read
// guest: Overall/Read만
```

---

## GitLab 보안 (`gitlab.rb`)

```ruby
# /etc/gitlab/gitlab.rb (compose 환경에서는 GITLAB_OMNIBUS_CONFIG로 주입)
gitlab_rails['gitlab_signup_enabled'] = false
gitlab_rails['minimum_password_length'] = 12
gitlab_rails['password_lowercase_required'] = true
gitlab_rails['password_uppercase_required'] = true
gitlab_rails['password_number_required'] = true
gitlab_rails['password_symbol_required'] = true
```

설치 후 UI에서:
- 모든 사용자 2FA 강제
- 브랜치 보호 규칙 (main, develop)
- Push rules (커밋 메시지/시그니처 검증)

---

## Nexus 보안

설치 후 UI에서:
1. 익명 접근 비활성화 (Security → Anonymous Access → OFF)
2. 저장소별 권한 분리 (releases: 배포 권한 제한, snapshots: 자유)
3. 정기 정리 정책 (Tasks → Cleanup) — 90일 미사용 artifact 삭제

---

## DB 보안

`generate-configs.sh`가 자동 처리:
- root 비밀번호 자동 생성
- 앱 전용 계정 생성 (최소 권한 — 해당 DB만)
- `devenv-db` internal 네트워크로 외부 인터넷 차단

수동 추가 권장:
```sql
-- MySQL 예시
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
```

---

## SonarQube Quality Gate

기본 통과 기준 (Jenkins가 이 결과를 받아 빌드 실패 처리):
- Coverage on New Code ≥ 80%
- Duplicated Lines ≤ 3%
- Maintainability/Reliability/Security Rating = A
- Security Hotspots Reviewed = 100%

---

## Docker 런타임 보안

본 스킬의 모든 compose 템플릿에 적용된 항목:
```yaml
security_opt:
  - no-new-privileges:true
restart: unless-stopped
healthcheck: { ... }
```

추가 권장 (각 서비스별 트레이드오프 검토 필요):
```yaml
read_only: true
tmpfs: [/tmp]
cap_drop: [ALL]
deploy:
  resources:
    limits: { cpus: '2.0', memory: 4G }
```

---

## 정기 보안 점검 주기

| 항목 | 주기 | 자동화 |
|------|------|-------|
| OS 보안 패치 | 매주 | unattended-upgrades |
| Docker 이미지 취약점 (Trivy) | 빌드마다 | Jenkins |
| OWASP ZAP DAST | 주 1회 | Jenkins (cron) |
| SonarQube SAST | PR마다 | Jenkins |
| 의존성 취약점 | 빌드마다 | Jenkins (Dependency-Check) |
| 침투 테스트 | 분기 1회 | 보안팀 (수동) |
| 접근 로그 감사 | 월 1회 | 인프라 (수동) |
| 계정/권한 검토 | 분기 1회 | 팀 리드 |
| 백업 복구 테스트 | 월 1회 | 인프라 |
