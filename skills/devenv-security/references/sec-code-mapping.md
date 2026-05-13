# SEC-E 코드 변경 매핑

| 코드 | 반영 파일 | 변경 요약 |
|---|---|---|
| SEC-E201 | `scripts/install-security.sh`, `templates/compose/security.yml.tpl` | ZAP 이미지 고정 `zaproxy/zap-stable:2.17.0` 검증 |
| SEC-E202 | `scripts/jenkins-configure.sh`, `references/jenkins-sonar-installation.groovy` | SonarInstallation 9-arg + `(Secret) null` + `Array.newInstance` |
| SEC-E601 | `scripts/lib/jenkins.sh` | Jenkins CSRF crumb 누락 시 명시 (`curl -G --data-urlencode xpath=...`) |
| SEC-E204 | `references/phase-playbook.md`, `references/harness-and-orchestration.md` | heredoc+pipe stdin 회피, zsh에서 변수명 `status` 금지 등 |
