# 클라우드별 방화벽 / 보안 그룹 가이드

각 클라우드 제공자에서 인바운드/아웃바운드 규칙을 어떻게 설정할지 안내합니다.

---

## 공통 원칙

| 트래픽 유형 | 출발지 | 도착지 | 포트 |
|------------|-------|-------|------|
| 외부 → Bastion | 팀 IP 대역 | Bastion | 22 |
| 외부 → Frontend (도메인 사용) | 0.0.0.0/0 | Frontend | 80, 443 |
| 팀 → 관리 UI | 팀 IP 대역 | Jenkins/GitLab/Grafana 등 | 각 포트 |
| 서버 ↔ 서버 | 내부 VPC | 내부 VPC | 모든 포트 |
| DB | Backend SG | DB SG | DB 포트 |

---

## AWS Security Group 예시

### Bastion-SG
```
인바운드:
  TCP 22  ← <팀 IP 대역>

아웃바운드:
  TCP 22  → Internal-SG (VPC CIDR)
```

### Internal-SG (Jenkins/GitLab/Nexus/SonarQube/ZAP 등)
```
인바운드:
  TCP 22       ← Bastion-SG
  TCP 8080     ← <팀 IP 대역> (Jenkins UI)
  TCP 80       ← <팀 IP 대역> (GitLab UI)
  TCP 8081     ← <팀 IP 대역> (Nexus UI)
  TCP 9000     ← <팀 IP 대역> (SonarQube UI — SECURITY_SONARQUBE=y 시 필수)
  TCP 8090     ← <팀 IP 대역> (OWASP ZAP UI — SECURITY_ZAP=y 시 필수)
  TCP All      ← Internal-SG (서버간 통신)

# COMPOSE_MODE=multi (Docker Swarm) 추가 필요
  TCP 2377     ← Internal-SG (Swarm 관리 트래픽 — Manager 노드)
  TCP/UDP 7946 ← Internal-SG (노드 간 통신)
  UDP 4789     ← Internal-SG (Overlay 네트워크 VXLAN)

아웃바운드:
  All
```

### DB-SG
```
인바운드:
  TCP 3306/5432/27017  ← Backend-SG only

아웃바운드:
  All  → DB-SG (replication 등 내부만)
```

### Frontend-SG (외부 노출)
```
인바운드:
  TCP 80, 443  ← 0.0.0.0/0
  TCP 22       ← Bastion-SG

아웃바운드:
  TCP all  → Backend-SG
```

---

## GCP Firewall Rules 예시

```bash
# Bastion 외부 접근
gcloud compute firewall-rules create devenv-bastion-in \
  --direction=INGRESS \
  --source-ranges=<팀_IP_대역> \
  --action=ALLOW --rules=tcp:22 \
  --target-tags=bastion

# 관리 UI 접근 (Jenkins:8080, GitLab:80, Nexus:8081, SonarQube:9000, ZAP:8090, Grafana:3001)
gcloud compute firewall-rules create devenv-mgmt-in \
  --direction=INGRESS \
  --source-ranges=<팀_IP_대역> \
  --action=ALLOW --rules=tcp:8080,tcp:80,tcp:8081,tcp:9000,tcp:8090,tcp:3001 \
  --target-tags=devenv-mgmt

# 내부 통신
gcloud compute firewall-rules create devenv-internal \
  --direction=INGRESS \
  --source-tags=devenv \
  --action=ALLOW --rules=all \
  --target-tags=devenv

# DB는 Backend에서만
gcloud compute firewall-rules create devenv-db-in \
  --direction=INGRESS \
  --source-tags=devenv-backend \
  --action=ALLOW --rules=tcp:3306,tcp:5432,tcp:27017 \
  --target-tags=devenv-db
```

---

## Azure NSG 예시

```bash
# Resource Group / NSG 생성 후
az network nsg rule create -g <RG> --nsg-name devenv-bastion-nsg \
  --name AllowSSH --priority 100 \
  --source-address-prefixes <팀_IP_대역> \
  --destination-port-ranges 22 \
  --access Allow --protocol Tcp

az network nsg rule create -g <RG> --nsg-name devenv-internal-nsg \
  --name AllowInternal --priority 100 \
  --source-address-prefixes VirtualNetwork \
  --destination-port-ranges '*' \
  --access Allow --protocol '*'
```

---

## 온프레미스 (iptables / firewalld)

```bash
# iptables 예시
# Bastion
iptables -A INPUT -p tcp --dport 22 -s <팀_IP_대역> -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j DROP

# 관리 UI (팀 IP만) — Jenkins:8080, GitLab:80, Nexus:8081, SonarQube:9000, ZAP:8090, Grafana:3001
iptables -A INPUT -p tcp -m multiport --dports 8080,80,8081,9000,8090,3001 \
  -s <팀_IP_대역> -j ACCEPT

# 내부망 자유
iptables -A INPUT -s 10.0.1.0/24 -j ACCEPT

# 나머지 차단
iptables -A INPUT -j DROP
```

---

## 중요 체크리스트

```
□ Bastion 외에 외부에서 SSH 직접 접근 가능한 서버가 없는가?
□ DB 포트가 외부에서 닫혀 있는가?
□ Jenkins/GitLab/Nexus 등 관리 UI가 0.0.0.0/0에 열려있지 않은가?
□ Backend/Frontend는 도메인을 통해서만 노출되는가?
□ HTTPS 적용 시 80→443 강제 리다이렉트가 되는가?
□ NACL/Network Policy로 한 번 더 격리되어 있는가?
```
