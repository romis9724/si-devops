# Air-gap 모드 절차

1. Trivy DB를 온라인 환경에서 준비
   - `trivy image --download-db-only`
   - 기본 DB 경로(`~/.cache/trivy/db`)를 tarball로 묶어 반입
   - 오프라인 환경에서 동일 경로에 복원
2. SonarQube plugin offline 설치
   - `.jar`를 `${SONARQUBE_HOME}/extensions/plugins`에 배치
   - 컨테이너 재기동
3. Dependency-Check NVD mirror 또는 사전 데이터셋 사용
4. 설치 스크립트는 외부 pull 대신 로컬 artifact 우선 사용
