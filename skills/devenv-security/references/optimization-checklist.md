# devenv-security Optimization Checklist

## 목적

`devenv-security` 실행 시 보안 품질과 파이프라인 신뢰성을 동시에 확보하기 위한 점검표입니다.

## 설치 전

- core 의존성 확인: Jenkins/GitLab/Nexus 응답 확인
- 비밀정보 정책 확인: 토큰/패스워드 로그 평문 출력 금지
- 프로필 확정: `pre-app` 또는 `post-app`을 PHASE 1에서 1회 확정

## 실행 게이트

- 순서: `scan-ready -> install -> health -> jenkins-integration -> publish`
- 품질 게이트 실패 시 publish 차단
- 재시도: `3회`, `5s/10s/20s`

## 헬스체크 최소 기준

- SonarQube: `/api/system/status` = `UP`
- ZAP: UI endpoint 응답
- Trivy: `trivy --version`
- Dependency-Check: Jenkins 플러그인 존재 확인

## 운영 최적화

- `--changed-only` 기본 활용으로 스캔 비용 절감
- 동일 원인 실패 묶음 처리로 재시도 루프 최소화
- strict gate 전환 시점(레포/브랜치) 문서화
