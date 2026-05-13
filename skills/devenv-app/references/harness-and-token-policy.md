# devenv-app — 하네스·토큰·완료 기준

SKILL.md에서 분리한 운영 규약입니다. 전역 규약은 `../devenv-common/contracts/devenv-contract.md`를 우선합니다.

## 하네스 엔지니어링 최적화 규약

재현성, 실패 격리, 빠른 복구를 위해 PHASE 6~7에 아래 규약을 적용합니다.

1. **게이트 기반 실행**: `Build → Artifact → Deploy → Smoke` 순서로 통과한 repo만 성공 처리합니다.
2. **부분 성공 보존**: `backend/frontend/admin`은 독립 실패 도메인으로 간주하고, 실패한 repo만 재시도합니다.
3. **재시도 예산 고정**: 네트워크/일시 오류는 항목당 최대 3회(5s/10s/20s) 재시도 후 실패 확정합니다.
4. **장애 근거 수집**: 실패 시점에 `최근 로그 50줄 + 마지막 HTTP 코드 + 마지막 성공 단계`를 함께 기록합니다.
5. **복구 범위 제한**: 자동 복구는 재시도/재등록/Webhook 동기화까지로 제한하고, destructive 동작은 사용자 확인 후 실행합니다.

### 에이전트 분업 규약 (필요 시)

PHASE 6에서 병렬화 이점이 큰 경우 에이전트를 다음처럼 분업합니다.

- **Agent A (GitLab)**: 그룹/프로젝트 존재 확인 + push 결과 수집
- **Agent B (Jenkins)**: 잡 등록/JCasC 동기화 + queue/build 상태 폴링
- **Agent C (Deploy/Smoke)**: 컨테이너 상태 + endpoint smoke 검증

공유 상태(`preset.json`) 갱신은 race를 피하기 위해 메인 에이전트가 순차로 수행합니다.

### 안전한 변경 원칙 (신규)

- 기본 정책은 **비파괴(non-destructive)** 입니다.
- 기존 Git 이력이 있는 저장소는 강제 push를 기본 선택지로 제공하지 않습니다.
- 이력 충돌 시 우선순위:
  1) 스킵 후 수동 병합
  2) 백업 브랜치 생성 후 병합/치환
  3) 사용자 명시 승인 시에만 제한적 강제 동작
- 실패 보고는 `last stage + last http/code + tail logs(30~50)`를 반드시 포함합니다.

---

## LLM 사용 토큰 최적화 규약

에이전트 응답 품질을 유지하면서 사용 토큰을 줄이기 위해 아래 규칙을 적용합니다.

0. 기본 출력 모드는 `compact`를 사용합니다 (`../devenv-common/contracts/devenv-contract.md` 8절).
   - 진행: 1줄
   - PHASE 결과: 3줄 이내
   - 최종 결과: 5줄 이내
1. **지연 로딩**: 현재 PHASE에 필요한 references 섹션만 읽고, 나머지는 요청 시 로딩합니다.
2. **요약 우선 응답**: 기본 출력은 변경점/결과 중심 5~8줄 요약으로 제공하고, 상세는 요청 시 확장합니다.
3. **중복 제거**: 이미 출력한 표/명령/설명은 재인용하지 않고 delta만 전달합니다.
4. **로그 압축**: 성공 로그는 상태 라인 1줄만, 실패 시에만 마지막 30~50줄을 첨부합니다.
5. **컨텍스트 절단**: PHASE 완료 시 과거 상세를 5줄 내 요약으로 축약하고 원문을 계속 들고 가지 않습니다.
6. **긴 표 지연 출력**: 긴 매트릭스/카탈로그는 제목+핵심 항목만 먼저 보여주고 전체표는 "상세 요청" 시 출력합니다.
7. **답변 길이 기본값**: 일반 응답은 짧고 명확하게 유지하고, "자세히" 요청이 있을 때만 장문으로 확장합니다.

### 출력 모드 플래그

- `OUTPUT_MODE=compact|verbose` (기본: `compact`)
- `compact`에서는 아래 단일 라인 템플릿을 우선 사용합니다.
  - 진행: `[PHASE X] app | status=ok|wait|fail | next=<action>`
  - 오류: `[APP-EXXX] <summary> | cause=<1-line> | action=<1-line> | next=retry|skip|abort`
  - 완료: `[DONE] app | core=ok security=ok|skip observe=ok|skip app=ok|partial | next=<action>`

---

## 통합 최적화 프레임워크 (Infra / Dev / DevOps / Harness)

아래 4개 관점을 동시에 만족해야 "완료"로 판단합니다.

### 1) 인프라 관점 (Infra)

- **가용성**: 핵심 엔드포인트(GitLab/Jenkins/Nexus/DB/Backend/Frontend/Admin) 헬스체크 통과
- **격리성**: 서비스별 네트워크/포트 충돌 없음, 충돌 시 대체 포트 반영
- **복구성**: 컨테이너 비정상 시 자동 재시작 1회 + 실패 원인 로그 수집
- **일관성**: single/multi 모드 자동 계산 변수(`HOST_PORT_*`, `NEXUS_REGISTRY`) 불일치 없음

### 2) 개발자 관점 (Developer Experience)

- **생산성**: 샘플 코드가 즉시 실행 가능(backend `/health`, frontend 기본 진입)
- **가독성**: 생성 코드/문서에 TODO 위치와 확장 지점 명확히 표시
- **디버깅성**: 실패 시 "원인 1줄 + 로그 tail + 다음 액션"을 동일 포맷으로 제공
- **재실행성**: 같은 입력으로 재실행 시 동일 결과(idempotent)

### 3) DevOps 관점

- **파이프라인 안정성**: Build/Test/Push/Deploy 단계별 성공 기준 고정
- **배포 신뢰성**: 이미지 push 성공 후에만 deploy, deploy 후 smoke check 필수
- **관측성**: 빌드 결과 + 배포 상태 + smoke 결과를 단일 요약으로 출력
- **롤포워드 우선**: 실패 repo만 재시도하여 전체 리드타임 최소화

### 4) 하네스 엔지니어링 관점

- **게이트 실행**: `Build → Artifact → Deploy → Smoke` 순차 게이트 강제
- **실패 격리**: repo 단위 실패 고정 후 다른 repo 계속 진행
- **근거 기반 판정**: HTTP 코드, 컨테이너 상태, Jenkins result를 함께 판단
- **표준 입력/출력**: 부분 실패 시 고정 템플릿(1|2|3)과 고정 로그 스키마 사용

### PHASE별 완료 기준 (Definition of Done)

| PHASE | DoD (완료 기준) |
|---|---|
| PHASE 1 | core 응답 + Docker 정보 확인, 필수 선행조건 통과 |
| PHASE 3 | 모든 질문 응답 저장 + config/env 반영 준비 완료 |
| PHASE 5 | DB 헬스체크 통과 + placeholder 상태 확인 |
| PHASE 6 | repo별 4게이트(Build/Artifact/Deploy/Smoke) 판정 완료 |
| PHASE 7 | 요약 출력 + preset 저장 + 다음 액션 안내 완료 |

### 운영 KPI (권장)

1. **P6 성공률**: PHASE 6 1회 통과율
2. **MTTR-lite**: 부분 실패 후 재시도 성공까지 시간
3. **재시도 효율**: `repo-only` 재시도 비율(전체 재실행 대비)
4. **토큰 효율**: 실행당 평균 응답 길이(요약 포맷 준수율)
