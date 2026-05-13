---
name: devenv-security
description: >
  개발 인프라에 보안 점검 도구를 추가하는 스킬.
  다음 상황에서 반드시 이 스킬을 사용하세요:
  - "보안 서버 설치", "보안 도구 구성", "보안점검 환경 만들기" 언급 시
  - "SonarQube 설치", "OWASP ZAP 설치", "Trivy 설치", "Dependency-Check 설치" 요청 시
  - "SAST 설정", "DAST 설정", "컨테이너 이미지 스캔", "라이브러리 취약점 검사" 요청 시
  - "보안 파이프라인 구성", "Quality Gate 설정", "Jenkins 보안 연동" 요청 시
  - devenv-core 설치 완료 후 보안 점검 레이어를 추가하고 싶을 때
  devenv-core(GitLab/Jenkins/Nexus/Docker)가 반드시 먼저 설치되어 있어야 하며,
  SonarQube(SAST) + OWASP ZAP(DAST) + Trivy(이미지 스캔) + Dependency-Check(라이브러리 취약점)를
  자동으로 구성하고 Jenkins 파이프라인에 Quality Gate를 연동합니다.
---

# devenv-security

## 빠른 탐색

| 찾는 내용 | 문서 |
|-----------|------|
| PHASE 0~8 절차·오류·헬스·스크립트 경로 | [`references/phase-playbook.md`](references/phase-playbook.md) |
| RUN_PROFILE·환경변수 계약·에이전트 분업·담당 도구 표 | [`references/harness-and-orchestration.md`](references/harness-and-orchestration.md) |
| 사전 요구·커널/포트 | [`references/prerequisites.md`](references/prerequisites.md) |
| 함정·사례 | [`references/lessons-learned.md`](references/lessons-learned.md) |
| 증상별 조치 | [`references/troubleshooting.md`](references/troubleshooting.md) |
| 게이트·스캔 비용 점검 | [`references/optimization-checklist.md`](references/optimization-checklist.md) |
| 에어갭·TLS·업그레이드·매트릭스 | [`references/airgap.md`](references/airgap.md), [`references/tls-migration.md`](references/tls-migration.md), [`references/upgrade-and-rollback.md`](references/upgrade-and-rollback.md), [`references/compatibility-matrix.md`](references/compatibility-matrix.md) |
| 비밀 파일 예시 | [`secrets/security.env.example`](secrets/security.env.example) |

**계약**: 충돌 시 [`../devenv-common/contracts/devenv-contract.md`](../devenv-common/contracts/devenv-contract.md) 우선.
**안 맞는 경우**: ISO 27001 / PCI-DSS 등 컴플라이언스 인증 요구 환경 — 본 스킬은 dev/staging 게이트용.

## 동작 방식 (PHASE)

| PHASE | 내용 |
|-------|------|
| 0 | 프리셋 확인 (`preset.json` 이전 설정 로드) |
| 1 | 사전 검증 + `RUN_PROFILE` 확정 (core/app 감지 + 보안 서비스 상태) |
| 2 | 설치 방식 선택 (신규 설치 대상이 있을 때만) |
| 3 | 환경 정보 수집 (상세 설정 시) |
| 4 | 구성 검토 (수집값 요약 후 사용자 최종 확인) |
| 5 | 병렬 설치 (독립 서비스를 병렬 에이전트로 동시 설치) |
| 6 | Jenkins 연동 (SonarQube Quality Gate + 파이프라인 자동 연동) |
| 7 | devenv-app 병합 / 건너뜀 (app 설치 후면 병합) |
| 8 | 완료 요약 + `preset.json` `security` 섹션 갱신 |

대화 스크립트·검증 표·JSON 예시는 [`references/phase-playbook.md`](references/phase-playbook.md).

**정리(teardown)**: 보안 컨테이너만 따로 내리는 `--scope=security` 옵션은 향후 추가 예정. 현재는 `devenv-core`의 `bash scripts/teardown.sh`가 SonarQube/ZAP 등 보안 컨테이너까지 일괄 정리합니다.

## preset.json (`security` 섹션)

- **위치**: `${DEVENV_HOME}/preset.json` (미설정 시 `~/devenv-${PROJECT_NAME}/preset.json`). **별도 파일을 두지 않음.**
- **책임**: `security` 섹션만 추가/갱신. `core` 등 다른 섹션은 변경하지 않음.
- **민감값**: `preset.json`에는 **`*_ref` 참조 키만**. 실제 비밀번호·토큰은 **`${DEVENV_HOME}/secrets/security.env`** (`chmod 600`)에만. [`secrets/security.env.example`](secrets/security.env.example)을 위 경로에 복사하면 `install-security.sh`가 자동 로드.
- **macOS**: `vm.max_map_count` `sysctl` 시도 안 함. Compose에 `SONAR_SEARCH_JAVAADDITIONALOPTS=-Dnode.store.allow_mmap=false` 적용.

## 행동 원칙

1. 한 번에 질문 1개. 응답 후에만 다음 PHASE 진행.
2. 확정된 값은 재질문 금지 (`RUN_PROFILE`, 포트, 버전, 모드).
3. 출력은 요약 우선 (성공 1줄 집계, 실패/경고만 상세). 이전 PHASE 요약 재출력 금지.
4. 로그는 실패 지점 중심만. 전체 덤프 금지.
5. 설치 시작 전 sudo/root 권한 계정 확인.

## 품질 게이트 (strict)

`devenv-app`이 생성·병합하는 Jenkins 파이프라인과 **같은 엄격성**:

- **순서**: `scan → gate → publish`. 게이트 실패 시 산출물 게시 **차단**.
- **Sonar**: `waitForQualityGate abortPipeline: true`.
- **Trivy / Dependency-Check**: 실패 숨김 (`|| true`, 임의 `--exit-code 0`) **금지**.
- 초기 `warn` → 안정화 시 `strict` 전환은 [`references/harness-and-orchestration.md`](references/harness-and-orchestration.md).
