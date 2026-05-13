# Lessons Learned — devenv-security

보안 스킬은 `devenv-core`와 동일한 인프라(WSL2/Docker/GitLab/Jenkins/Nexus) 위에서 동작하므로 함정 사례를 공유합니다.

→ **공통 인프라 함정**: [`../../devenv-core/references/lessons-learned.md`](../../devenv-core/references/lessons-learned.md)

보안 특화 함정(SonarQube `vm.max_map_count`, ZAP API 키, Trivy DB 동기화, Dependency-Check NVD 캐시 등)은 [`troubleshooting.md`](troubleshooting.md) "증상별 카탈로그"를 봅니다.
