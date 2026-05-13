# CI/CD 파이프라인 가이드

## 전체 흐름

```
개발자 Push
    │
    ▼
GitLab (Webhook)
    │
    ▼
Jenkins Pipeline
    ├── Stage 1: Checkout
    ├── Stage 2: Build
    ├── Stage 3: Unit Test
    ├── Stage 4: SAST (SonarQube)
    ├── Stage 5: Quality Gate
    ├── Stage 6: Dependency Scan
    ├── Stage 7: Docker Build
    ├── Stage 8: Image Scan (Trivy)
    ├── Stage 9: Push to Nexus
    ├── Stage 10: Deploy Dev
    ├── Stage 11: DAST (OWASP ZAP, Dev 대상)
    └── Stage 12: Deploy Staging (수동 승인)
```

---

## Jenkinsfile 위치

생성된 환경의 `configs/jenkins/Jenkinsfile.template`에 언어별 템플릿이 있습니다.
앱 저장소 루트에 `Jenkinsfile`로 복사 후 사용하세요.

---

## 브랜치 전략별 트리거

### GitFlow
| 브랜치 | 동작 |
|--------|------|
| `feature/*` | Build + Test + SAST |
| `develop` | + Dep-Scan + 이미지 Build/Scan + Dev 배포 + DAST |
| `release/*` | 전체 + Staging 배포 (수동 승인) |
| `main` | Prod 배포 (수동 승인) |
| `hotfix/*` | 빠른 빌드 + Prod 긴급 배포 |

### Trunk-based
| 액션 | 동작 |
|------|------|
| `main` Push | Build + Test + SAST + Dev 배포 |
| Tag `v*.*` | Staging → Prod (수동 승인) |

---

## Jenkins 초기 플러그인

```
필수:
  git, gitlab-plugin, pipeline, workflow-aggregator,
  docker-pipeline, ssh-agent, credentials-binding,
  sonarqube, jacoco, junit, dependency-check-jenkins-plugin,
  html-publisher, build-timeout, timestamper, nexus-artifact-uploader

선택(알람):
  slack, mailer
```

---

## Jenkins 자격증명 등록

| ID | 종류 | 용도 |
|----|------|------|
| `gitlab-token` | Secret text | GitLab API 호출 |
| `nexus-credentials` | Username with password | Nexus push/pull |
| `sonarqube-token` | Secret text | SonarQube 분석 |
| `bastion-ssh-key` | SSH key | Bastion 경유 배포 |
| `slack-token` | Secret text | 알람 |

---

## GitLab Webhook 설정

```
GitLab → Project → Settings → Webhooks
URL: http://<JENKINS_IP>:8080/project/<job_name>
Secret Token: <Jenkins gitlab plugin이 생성한 token>
Trigger: Push events, Merge request events, Tag push events
```

---

## 배포 전략

### Rolling
순차적으로 인스턴스를 교체. 다운타임 최소.

### Blue-Green
새 환경(green) 띄우고 트래픽 전환. 즉시 롤백 가능.
별도 인프라 필요 (compose에서는 docker-compose.override.yml로 구현).

### Canary
일부(예: 10%) 트래픽만 새 버전으로. 점진적 확대.
Nginx weight 또는 Service Mesh 필요.

본 스킬은 기본 Rolling을 제공하며, Blue-Green/Canary는 추후 확장 영역입니다.

---

## Quality Gate 정책 (SonarQube)

```
신규 코드 기준:
  Coverage ≥ 80%
  Duplicated Lines ≤ 3%
  Maintainability Rating = A
  Reliability Rating = A
  Security Rating = A
  Security Hotspots Reviewed = 100%
```

이 기준 미달 시 Jenkins 빌드 자동 실패.
SonarQube → Quality Gates → "Sonar way" 수정 또는 신규 정의.
