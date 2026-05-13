---
name: devenv-common
description: >-
  개발 인프라 스킬(devenv-core, devenv-security, devenv-observe, devenv-app) 실행 시
  공통 정책을 적용한다. preset/runtime 경로, healthcheck 기준, retry/backoff,
  오류 출력 포맷, compact 출력 모드를 통일해야 할 때 사용한다.
---

# devenv-common

## 목적

개별 스킬을 대체하지 않고, 4개 스킬의 공통 기준을 먼저 고정해 실행 일관성을 보장한다.

## 전역 기준 문서

- 기준: [`contracts/devenv-contract.md`](contracts/devenv-contract.md)
- 충돌 시 전역 기준 우선. 적용 대상: [`../devenv-core`](../devenv-core/SKILL.md), [`../devenv-security`](../devenv-security/SKILL.md), [`../devenv-observe`](../devenv-observe/SKILL.md), [`../devenv-app`](../devenv-app/SKILL.md).

## 실행 절차

1. 전역 기준 문서를 읽는다.
2. 실행할 스킬 문서를 읽는다.
3. 아래 6개 항목 충돌 확인 후 전역 기준으로 정렬:
   - preset/runtime 경로, canonical healthcheck endpoint, port collision policy, retry/backoff, destructive compose option (`--remove-orphans` 기본 금지), output contract (compact/verbose).
4. 정렬 후에만 개별 PHASE 실행 진행.
5. 실행 중 게이트는 전역 계약 **13절 (인프라/DevOps/Harness 최적화)** 기준: `preflight → install → health → integration → smoke`. 게이트 실패 시 다음 단계 중단.

## 출력·템플릿

기본 `OUTPUT_MODE=compact`. 진행 1줄 / PHASE 결과 3줄 / 최종 5줄. 상세는 요청 시.

```text
[PHASE X] common-check | status=ok|fail | next=<action>
[COMMON-EXXX] <summary> | cause=<1-line> | action=<1-line> | next=retry|skip|abort
[DONE] common | contract=applied | next=<skill-phase>
```

## 비목표

- 서비스 설치/배포 직접 수행 X
- 인프라 리소스 직접 변경 X
- 개별 스킬의 도메인 로직 대체 X

## 최적화 체크리스트

1. idempotency-first — 정상 리소스 재생성 X
2. non-destructive-first — 파괴적 동작 기본 비활성
3. bounded retries — 3회/5s-10s-20s 예산
4. evidence-first — 실패 근거(step/code/tail) 기록
5. kpi-ready — first-pass/mttr 관점 요약 가능
