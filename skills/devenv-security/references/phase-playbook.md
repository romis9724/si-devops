# devenv-security — PHASE 실행 피드북

PHASE 0~8 절차, 오류 코드, 헬스체크, 참조 경로. **현재 PHASE**에 해당하는 절만 읽습니다.

## 목차 (PHASE)

에디터에서 `PHASE n` 또는 키워드로 검색합니다.

| PHASE | 주제 |
|------|------|
| 0 | 프리셋 확인 |
| 1 | 사전 검증 · RUN_PROFILE |
| 2 | 설치 방식 선택 |
| 3 | 환경 정보 수집 |
| 4 | 구성 검토 |
| 5 | 병렬 설치 |
| 6 | Jenkins 연동 |
| 7 | devenv-app 병합 |
| 8 | 완료 요약 · preset |
| - | 오류 처리 · 헬스 · 참조 파일 |

## PHASE 0: 프리셋 확인

**진입 조건**: 스킬 시작 시 가장 먼저 실행합니다.
**완료 조건**: 프리셋 사용 여부 응답을 받은 후 PHASE 1로 이동합니다. 프리셋이 없으면 즉시 PHASE 1로 이동합니다.

### 프리셋 로드 절차

preset.json 파일 존재 여부를 확인하세요.
- 위치: [`../SKILL.md`](../SKILL.md) **preset.json (`security` 섹션)** 절과 동일 규칙 — `${DEVENV_HOME}/preset.json` (`DEVENV_HOME` 미설정 시 `~/devenv-${PROJECT_NAME}/preset.json`)

security 섹션이 없는 경우: 바로 PHASE 1으로 이동합니다.

security 섹션이 있는 경우, 다음 메시지를 출력하고 사용자 응답을 기다리세요:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 이전 보안 설정을 불러왔습니다.

  SonarQube  버전: 10.4-community
  OWASP ZAP  버전: 2.17.0
  보안 서버 IP: 10.0.1.8

 이 설정을 사용할까요?
   1. 예, 이전 설정 사용
   2. 아니오, 새로 설정
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

응답에 따라:
- "1" → 이전 설정을 로드한 상태로 PHASE 1로 이동
- "2" → 설정을 초기화하고 PHASE 1로 이동

### preset.json security 섹션 구조 (참고)

```json
{
  "security": {
    "server_ip": "10.0.1.8",
    "sonarqube": {
      "enabled": true,
      "version": "10.4-community",
      "port": 9000,
      "admin_password_ref": "secrets/security.env#SONAR_ADMIN_PASSWORD"
    },
    "owasp_zap": {
      "enabled": true,
      "version": "2.17.0",
      "port": 8090
    },
    "trivy": {
      "enabled": true,
      "offline_mode": false
    },
    "dependency_check": {
      "enabled": true,
      "jenkins_tool_name": "dependency-check",
      "nvd_api_key_ref": "secrets/security.env#NVD_API_KEY"
    }
  }
}
```

---

## PHASE 1: 사전 검증

**진입 조건**: PHASE 0 완료 후 진입합니다.
**완료 조건**: 검증 결과와 실행 프로필(app 설치 전/후)을 확정한 뒤, 신규 설치 대상이 있으면 PHASE 2로 이동합니다. 신규 설치 대상이 없으면 Jenkins 재확인 여부를 묻고 응답을 기다립니다.

### 1-0a. 동시성 락 + 체크포인트

- `${DEVENV_HOME}/.devenv.lock`(미설정 시 `~/devenv-${PROJECT_NAME}/.devenv.lock`) — **preset.json과 동일 디렉터리**에만 둡니다. 스킬 리포지토리 `out_dir` 등에 별도 `preset.json`을 만들지 않습니다.
- `preset.json.security`에 `current_phase`, `completed_steps[]`, `last_run_at`를 저장해 재개 가능 상태를 유지합니다.

### 1-0. 권한 계정 확인 (필수)

아래 질문을 먼저 수행하고 사용자 응답을 기다리세요:

> 설치를 수행할 Linux 계정을 확인합니다.
>   1. 현재 계정으로 진행 (sudo 가능)
>   2. root로 전환 후 진행
>
> 계정명(예: ubuntu/root)을 입력해 주세요.

검증:

```bash
whoami
id
sudo -n true >/dev/null 2>&1 || echo "SUDO_PASSWORD_REQUIRED"
```

`sudo -n true` 실패 + root 아님이면 중단하고 root/sudo 계정으로 재진입을 안내합니다.
비밀번호는 저장하지 않습니다.

### 1-1. devenv-core 필수 확인

devenv-core 설치 여부를 먼저 확인합니다.

```bash
# preset.json에서 core 섹션 확인
# 또는 실제 서비스 헬스체크로 검증

# Jenkins 확인
curl -fsS http://<CORE_IP>:8080/login  # 응답 있으면 OK

# GitLab 확인
curl -fsS http://<CORE_IP>/users/sign_in  # 응답 있으면 OK
```

devenv-core가 없거나 비정상인 경우, 다음 메시지를 출력하고 실행을 중단하세요:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 실행 중단: devenv-core가 필요합니다
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 devenv-security는 devenv-core 위에서 동작합니다.
 먼저 devenv-core를 설치하세요:
   → "devenv-core 설치해줘" 라고 입력하면 시작됩니다.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 1-2. 보안 서비스 상태 확인

각 서비스에 대해 아래 3가지 케이스로 분류합니다.

```
케이스 A: 미설치         → 신규 설치 대상으로 분류
케이스 B: 설치 + 정상    → 스킵 (기존 유지)
케이스 C: 설치 + 비정상  → 오류 원인 분석 → 해결 → 재설치
```

**SonarQube 확인**

```bash
curl -fsS http://<SECURITY_IP>:9000/api/system/status
# 정상: {"status":"UP"}
# 비정상: 연결 거부 or {"status":"STARTING"} 장시간 지속
```

**OWASP ZAP 확인**

```bash
curl -fsS http://<SECURITY_IP>:8090
# 정상: ZAP UI HTML 응답
# 비정상: 연결 거부
```

**Trivy 확인** (호스트 바이너리 설치 금지 — `docker run` 기본)

```bash
docker run --rm aquasec/trivy:latest --version
# 정상: Version 출력
# 실패: Docker 미기동 또는 레지스트리 차단
```

**Dependency-Check 확인** (기본: Jenkins 플러그인 + Global Tool 이름 `dependency-check`)

```bash
curl -fsS http://<JENKINS_IP>:8080/pluginManager/api/json?depth=1 \
  | grep -q dependency-check-jenkins-plugin && echo "plugin OK"
# CLI(dependency-check.sh)는 사용자가 컨테이너 방식을 명시 선택한 경우에만 요구
```

### 1-3. 검증 결과 요약 출력

다음 형식으로 검증 결과를 출력하세요:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 사전 검증 결과
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 devenv-core     ✅ 정상 (Jenkins + GitLab 확인됨)

 보안 서비스 현황:
   SonarQube      ❌ 미설치    → 신규 설치 예정
   OWASP ZAP      ✅ 정상      → 스킵 (기존 유지)
   Trivy          ❌ 미설치    → 신규 설치 예정
   Dep-Check      ⚠️ 비정상   → 오류 분석 후 재설치
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 신규 설치 대상: SonarQube, Trivy, Dependency-Check
```

신규 설치 대상이 없으면 (모두 정상) 다음 메시지를 출력하고 사용자 응답을 기다리세요:

```
> 모든 보안 서비스가 정상 동작 중입니다. 추가 설치가 필요 없습니다.
> Jenkins 연동 상태를 다시 확인할까요?
> 1. 예, 재확인
> 2. 아니오, 종료
```

응답에 따라:
- "1" → PHASE 6으로 이동
- "2" → 스킬을 종료

### 1-4. 실행 프로필 확정 (devenv-app 설치 전/후 분기)

반드시 PHASE 1에서 `devenv-app` 설치 여부를 먼저 확정하고 이후 PHASE에서 동일 플래그를 재사용하세요.

판별 순서:
1. `preset.json`의 `app` 섹션 존재 여부 확인
2. app 섹션이 없으면 샘플 앱 경로 존재 여부 확인 (`sample-apps/backend`, `sample-apps/frontend`)
3. 둘 다 없으면 **pre-app 프로필**로 확정

프로필 정의:
- **pre-app 프로필 (devenv-app 설치 전)**: 기본 보안 인프라 설치/검증 중심으로 진행, PHASE 7은 자동 건너뜀
- **post-app 프로필 (devenv-app 설치 후)**: 기본 보안 인프라 + 기존 프로젝트 병합(sonar/Jenkinsfile) 수행 가능

출력 형식:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 실행 프로필 확정
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 devenv-app 감지: 아니오
 적용 프로필 : pre-app (기본 점검 플로우)
 후속 처리   : PHASE 7 자동 건너뜀
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

또는

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 실행 프로필 확정
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 devenv-app 감지: 예
 적용 프로필 : post-app (기존 프로젝트 병합 가능)
 후속 처리   : PHASE 7에서 병합 여부 확인
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 1-5. 비정상 서비스 오류 분석

케이스 C (설치 + 비정상) 서비스에 대해 원인을 분석하고 다음 형식으로 출력하세요:

```
[Dependency-Check 비정상 감지]
오류 유형 확인 중...
→ NVD 데이터베이스 업데이트 실패로 추정됩니다.
  원인: NVD API 키 미설정 또는 네트워크 차단
  해결: PHASE 3에서 NVD API 키를 입력하거나 오프라인 모드로 설정합니다.
```

---

## PHASE 2: 설치 방식 선택

**진입 조건**: PHASE 1 완료 후 신규 설치 대상이 1개 이상 있을 때만 진입합니다.
**완료 조건**: 사용자 응답을 받은 후, "1" 선택 시 PHASE 4로 이동, "2" 선택 시 PHASE 3으로 이동합니다.

다음 메시지를 출력하고 사용자 응답을 기다리세요:

```
> 설치 방식을 선택해주세요.
>
>   1. 빠른 시작 — 기본값으로 자동 설치
>                  (SonarQube 10.4-community, Trivy 최신, ZAP 2.17.0)
>
>   2. 상세 설정 — 버전/포트/옵션을 직접 구성
>
> 선택 (기본: 1):
```

응답에 따라:
- "1" 또는 Enter → 기본값을 모두 적용하고 PHASE 4(구성 검토)로 이동
- "2" → PHASE 3으로 이동하여 각 옵션을 질문

### 기본값 목록

| 항목 | 기본값 |
|------|--------|
| 보안 서버 IP | devenv-core와 동일 서버 (단일 서버 모드) |
| SonarQube 버전 | 10.4-community |
| SonarQube 포트 | 9000 |
| SonarQube 관리자 비밀번호 | changeme (첫 로그인 시 변경 강제) |
| OWASP ZAP 버전 | 2.17.0 |
| OWASP ZAP 포트 | 8090 |
| Trivy 버전 | latest |
| Trivy 오프라인 모드 | false |
| Dependency-Check 버전 | 9.0.9 |
| NVD API 키 | 없음 (제한 모드) |
| Quality Gate 실패 시 빌드 | 즉시 실패 처리 (strict 기본) |

---

## PHASE 3: 환경 정보 수집 (상세 설정 선택 시)

**진입 조건**: PHASE 2에서 "2. 상세 설정"을 선택한 경우에만 진입합니다.
**완료 조건**: 신규 설치 대상 서비스의 모든 그룹 질문에 응답을 받은 후 PHASE 4로 이동합니다.

신규 설치 대상 서비스에 대해서만 질문합니다. 각 그룹의 질문은 하나씩 순서대로 진행합니다.

### [그룹 A] 서버 기본 설정

**질문 A-1.** 다음 메시지를 출력하고 사용자 응답을 기다리세요:

```
> 보안 서비스 설치 위치를 선택해주세요.
>   1. devenv-core와 동일 서버 (단일 서버 권장)
>   2. 별도 보안 전용 서버
```

응답에 따라:
- "1" → 보안 서버 IP를 core IP와 동일하게 설정, 질문 A-2로 이동
- "2" → 질문 A-2로 이동

**질문 A-2.** "2. 별도 보안 전용 서버" 선택 시에만 다음 메시지를 출력하고 사용자 응답을 기다리세요:

```
> 보안 서버 IP를 입력해주세요. (예: 10.0.1.8)
```

입력값을 보안 서버 IP로 저장하고 질문 A-3으로 이동합니다.

**질문 A-3. (Linux 호스트에서만)** `uname`이 Linux일 때만 다음을 출력합니다. macOS/Darwin에서는 **이 질문 전체를 생략**하고 [그룹 B]로 이동합니다 (macOS는 `sysctl` 시도 금지; Sonar는 compose의 `SONAR_SEARCH_JAVAADDITIONALOPTS=-Dnode.store.allow_mmap=false`로 대응).

```
> vm.max_map_count를 SonarQube 기동에 필요한 값(262144)으로 자동 설정할까요? (Linux만)
>   1. 예 — SonarQube 기동을 위해 자동으로 sysctl 수정
>   2. 아니오 — 수동으로 처리
```

응답을 저장하고 [그룹 B]로 이동합니다.

### [그룹 B] SonarQube 설정 (미설치 시만)

SonarQube가 신규 설치 대상이 아니면 이 그룹 전체를 건너뜁니다.

**질문 B-1.** 다음 메시지를 출력하고 사용자 응답을 기다리세요:

```
> SonarQube 버전을 선택해주세요.
>   1. 10.4-community [기본]
>   2. 10.3-community
>   3. 직접 입력
```

응답에 따라:
- "1" 또는 Enter → 10.4-community로 설정, 질문 B-2로 이동
- "2" → 10.3-community로 설정, 질문 B-2로 이동
- "3" → 버전 직접 입력을 요청하고, 입력값을 저장한 후 질문 B-2로 이동

**질문 B-2.** 다음 메시지를 출력하고 사용자 응답을 기다리세요:

```
> SonarQube 포트를 입력해주세요. (기본: 9000)
```

입력이 없으면 9000을 사용합니다. 응답을 저장하고 질문 B-3으로 이동합니다.

**질문 B-3.** 다음 메시지를 출력하고 사용자 응답을 기다리세요:

```
> SonarQube 관리자 초기 비밀번호를 입력해주세요. (기본: changeme)
```

입력이 없으면 changeme를 사용합니다. 응답을 저장하고 질문 B-4로 이동합니다.

**질문 B-4.** 다음 메시지를 출력하고 사용자 응답을 기다리세요:

```
> Quality Gate 실패 시 Jenkins 빌드를 어떻게 처리할까요?
>   1. 빌드 실패 처리 (엄격 모드) [기본]
>   2. 경고만 출력 (빌드 계속 - 예외 모드)
```

응답을 저장하고 [그룹 C]로 이동합니다.

### [그룹 C] OWASP ZAP 설정 (미설치 시만)

OWASP ZAP이 신규 설치 대상이 아니면 이 그룹 전체를 건너뜁니다.

**질문 C-1.** (고정) `softwaresecurityproject/*` 이미지 publish 중단에 따라 **Docker Hub `zaproxy/zap-stable:2.17.0`만** 사용합니다. 버전 선택 질문은 하지 않습니다. 질문 C-2로 이동합니다.

**질문 C-2.** 다음 메시지를 출력하고 사용자 응답을 기다리세요:

```
> OWASP ZAP 포트를 입력해주세요. (기본: 8090)
```

입력이 없으면 8090을 사용합니다. 응답을 저장하고 질문 C-3으로 이동합니다.

**질문 C-3.** 다음 메시지를 출력하고 사용자 응답을 기다리세요:

```
> ZAP 스캔 대상 URL을 입력해주세요. (예: http://10.0.1.5:8080)
> (devenv-app의 Backend URL이 감지된 경우 자동으로 표시됩니다)
```

입력값을 저장하고 [그룹 D]로 이동합니다.

### [그룹 D] Trivy 설정 (미설치 시만)

Trivy가 신규 설치 대상이 아니면 이 그룹 전체를 건너뜁니다.

**질문 D-1.** 기본 스캔 방식은 **`docker run --rm <이미지> ...`** 입니다. 호스트에 `trivy` 바이너리를 설치하지 않습니다. 필요 시에만 다음을 묻습니다:

```
> Trivy 컨테이너 이미지 (기본: aquasec/trivy:latest)
> Enter 유지 또는 이미지 태그를 입력하세요.
```

**질문 D-2.** 다음 메시지를 출력하고 사용자 응답을 기다리세요:

```
> Trivy 오프라인(Air-gap) 모드를 사용할까요?
>   1. 아니오 — 자동으로 DB 업데이트 [기본]
>   2. 예 — 오프라인 모드 (DB를 별도로 준비해야 함)
```

응답을 저장하고 질문 D-3으로 이동합니다.

**질문 D-3.** 다음 메시지를 출력하고 사용자 응답을 기다리세요:

```
> 스캔 대상 Nexus Docker 레지스트리 주소를 입력해주세요. (예: 10.0.1.3:5000)
> (devenv-core의 Nexus 주소가 감지된 경우 자동으로 표시됩니다)
```

입력값을 저장하고 [그룹 E]로 이동합니다.

### [그룹 E] Dependency-Check 설정 (미설치 또는 비정상 시만)

Dependency-Check가 신규 설치 대상이 아니면 이 그룹 전체를 건너뜁니다.

**질문 E-1.** 다음 메시지를 출력하고 사용자 응답을 기다리세요:

```
> Dependency-Check 버전을 선택해주세요.
>   1. 9.0.9 [기본]
>   2. 직접 입력
```

응답에 따라:
- "1" 또는 Enter → 9.0.9로 설정, 질문 E-2로 이동
- "2" → 버전 직접 입력을 요청하고, 입력값을 저장한 후 질문 E-2로 이동

**질문 E-2.** 다음 메시지를 출력하고 사용자 응답을 기다리세요:

```
> NVD API 키를 설정할까요?
>   1. 없음 (제한된 속도로 DB 업데이트)
>   2. 직접 입력 (https://nvd.nist.gov/developers/request-an-api-key 에서 발급)
```

응답에 따라:
- "1" → NVD API 키 없음으로 설정, 질문 E-3으로 이동
- "2" → API 키 직접 입력을 요청하고, 입력값을 저장한 후 질문 E-3으로 이동

**질문 E-3.** 다음 메시지를 출력하고 사용자 응답을 기다리세요:

```
> Dependency-Check 실행 방식을 선택해주세요.
>   1. Jenkins 플러그인 방식 [기본] — Global Tool 이름은 반드시 dependency-check 로 통일
>   2. Docker 컨테이너 방식 (명시 선택 시에만 허용; 기본 플로우에서는 비권장)
```

응답을 저장하고 PHASE 4로 이동합니다.

---

## PHASE 4: 구성 검토

**진입 조건**: PHASE 2에서 "1. 빠른 시작" 선택 또는 PHASE 3의 모든 그룹 질문 완료 후 진입합니다.
**완료 조건**: 사용자가 "y"로 확인하면 PHASE 5로 이동합니다. 수정 요청 시 해당 그룹 질문으로 돌아갑니다.

수집된 모든 정보를 요약하고, 다음 메시지를 출력한 후 사용자 응답을 기다리세요:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 devenv-security 구성 요약
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 [서버]         10.0.1.8 (devenv-core와 동일)

 [SonarQube]    10.4-community / 포트: 9000
                관리자: admin / changeme
                Quality Gate: 경고 모드 (빌드 계속)

 [OWASP ZAP]    2.17.0 / 포트: 8090
                스캔 대상: http://10.0.1.5:8080

 [Trivy]        latest / 온라인 모드
                레지스트리: 10.0.1.3:5000

 [Dep-Check]    9.0.9 / Jenkins 플러그인 방식
                NVD API 키: 없음 (제한 모드)

 [Jenkins 연동] Quality Gate stage 자동 추가
                대상 잡: backend, frontend, admin

 [작업 구분]
   SonarQube    → 신규 설치
   OWASP ZAP    → 스킵 (기존 유지)
   Trivy        → 신규 설치
   Dep-Check    → 재설치 (오류 해결 후)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

> 이대로 진행할까요? (y / 수정할 항목을 말씀해주세요)
```

응답에 따라:
- "y" → PHASE 5로 이동
- 수정 요청 → 해당 항목 그룹 질문으로 돌아가 재질문한 후 다시 PHASE 4로 돌아옴

---

## PHASE 5: 병렬 설치

**진입 조건**: PHASE 4에서 사용자 확인 후 진입합니다.
**완료 조건**: 모든 서비스 설치 및 헬스체크 완료 후 PHASE 6으로 이동합니다.

서비스 간 독립성을 기반으로 병렬 설치를 수행합니다.

### PHASE별 timeout budget (고정 계약)

| PHASE | 작업 | budget | retry |
|---|---|---|---|
| 5 | sonar UP | 180s | 30 × 6s |
| 5 | zap API | 60s | 12 × 5s |
| 5 | trivy DB init | 300s | 10 × 30s |
| 6 | jenkins crumb | 10s | 3 × 3s |
| 6 | scriptText | 30s | 3 × 10s |

### 병렬 설치 구성

```
병렬 그룹 1 (동시 실행):
  - Agent A: SonarQube 컨테이너 설치 + 초기화 대기
  - Agent B: Trivy `docker run` 기반 DB 준비/검증 (호스트 바이너리 설치 없음)

병렬 그룹 2 (그룹 1 완료 후):
  - Agent C: OWASP ZAP 컨테이너 설치 (미설치 시)
  - Agent D: Dependency-Check 재설치/설치

순차 실행:
  - SonarQube 완전 기동 확인 (status: UP)
  - 각 서비스 헬스체크
```

### SonarQube/Trivy/ZAP/Dependency-Check 설치 절차 (요약)

토큰 절약을 위해 SKILL 본문에는 단계만 유지하고, 상세 명령은 스크립트/레퍼런스로 위임합니다.

- SonarQube:
  1) Linux: `vm.max_map_count` 확인·영속화(가능 시). macOS: **sysctl 시도 금지**, compose `SONAR_SEARCH_JAVAADDITIONALOPTS=-Dnode.store.allow_mmap=false` 적용
  2) compose 기동
  3) readiness(`UP`) 확인
  4) 초기 비밀번호/Quality Gate 설정
- Trivy:
  1) `docker run --rm aquasec/trivy:latest --version` 등으로 검증
  2) DB 초기화(온라인) 또는 오프라인 모드 준비
- ZAP:
  1) 프로파일 기반 컨테이너 기동
  2) UI endpoint readiness 확인
  3) daemon 모드 false negative 방지를 위해 compose healthcheck override를 강제
- Dependency-Check:
  1) Jenkins 플러그인 방식 우선
  2) 컨테이너 방식은 확장 compose 사용 시에만 허용

상세는 아래를 참조:
- `scripts/install-security.sh`
- `scripts/health-check.sh`
- `references/troubleshooting.md`
- `references/optimization-checklist.md`

### 설치 진행 상태 출력

```
[설치 진행 중]
  Agent A  SonarQube    ████████░░░░  기동 대기 중... (45s)
  Agent B  Trivy        ████████████  완료 ✅
  Agent C  OWASP ZAP    ████░░░░░░░░  컨테이너 시작 중...
  Agent D  Dep-Check    ██████████░░  Jenkins 플러그인 설치 중...
```

---

## PHASE 6: Jenkins 연동

**진입 조건**: PHASE 5 완료 후 진입합니다. (또는 PHASE 1에서 Jenkins 재확인을 선택한 경우)
**완료 조건**: 모든 Jenkins 잡 연동 완료 후 PHASE 7로 이동합니다. (단, pre-app 프로필이어도 PHASE 6은 동일하게 수행)

SonarQube Quality Gate를 Jenkins 파이프라인에 자동으로 연동합니다.

### 6-1 ~ 6-3. Jenkins 연동 요약

토큰 절약을 위해 Jenkins 연동 상세 예시는 생략하고, 아래 규약만 유지합니다.

- 자격증명:
  - SonarQube 서버/토큰을 Jenkins에 등록
  - 가능하면 JCasC 기반으로 선언형 관리
  - 모든 Jenkins POST 요청(`/scriptText`, credentials delete 포함)은 crumb 발급 후 헤더를 포함 (`scripts/lib/jenkins.sh` 표준). xpath에 `[` `]`가 있으므로 **`curl -G --data-urlencode 'xpath=...'`** 로만 조회합니다.
  - crumb 누락/실패 시 **`[SEC-E601]`** (CSRF).
    - `curl -G "${JENKINS_URL}/crumbIssuer/api/xml" --data-urlencode 'xpath=concat(//crumbRequestField,":",//crumb)'`
    - `POST ... -H "$CRUMB"`
- Jenkinsfile 삽입 규칙:
  - `SonarQube Analysis`
  - `Quality Gate`
  - `Trivy Image Scan`
  - `Dependency Check`
- Gate 동작:
  - 기본은 strict 모드이며, 실패 시 파이프라인을 즉시 중단합니다.
  - 예외적으로 warn 모드가 필요한 경우에만 사용자 명시 승인 후 1회성으로 허용합니다.
  - strict 기준: `신규 critical=0 + coverage>=70% + 4주 연속 green`
  - PR 스캔은 `sonar.pullrequest.{key,branch,base}`를 필수 전달
  - GitLab MR decoration 절차는 `references/pr-scan-guide.md`를 기준으로 적용

- SonarInstallation 생성자 호환:
  - sonar plugin 2.18.2 기준 9-arg 생성자를 기본 사용
  - 시그니처 불일치 시 introspection으로 constructor를 감지 후 인자 수를 조정
  - 참고: `references/jenkins-sonar-installation.groovy`

- SonarQube webhook:
  - Jenkins waitForQualityGate 연동을 위해 SonarQube webhook을 자동 등록

상세 블록/샘플은 `references/troubleshooting.md` 및 구현 스크립트 기준을 우선합니다.

### 6-4. 연동 대상 Jenkins 잡

devenv-core가 생성한 잡 목록을 자동 감지하여 모두 연동합니다.

```
연동 대상 잡 확인 중...
  - backend    ✅ Jenkinsfile 업데이트 완료
  - frontend   ✅ Jenkinsfile 업데이트 완료
  - admin      ✅ Jenkinsfile 업데이트 완료
```

### 6-5. SonarQube 프로젝트 자동 생성

연동 대상 잡(`backend/frontend/admin`)에 대해 프로젝트를 idempotent하게 생성/재사용합니다.

---

## PHASE 7: devenv-app 병합 (감지 시)

**진입 조건**: PHASE 6 완료 후 진입합니다.
**완료 조건**: 사용자 응답을 받은 후, "1" 선택 시 병합을 실행하고 PHASE 8로 이동합니다. "2" 선택 시 병합 없이 PHASE 8로 이동합니다. devenv-app이 없으면 즉시 PHASE 8로 이동합니다.

### 7-1. devenv-app 감지 (PHASE 1 결과 재사용)

PHASE 1에서 확정한 실행 프로필을 그대로 사용하세요. 이 단계에서 재탐지하지 마세요.

- pre-app 프로필이면, 이 PHASE 전체를 자동 건너뜁니다.
- post-app 프로필이면, 7-2 병합 제안으로 진행합니다.

devenv-app이 설치되지 않은 경우(= pre-app), 나중에 devenv-app 설치 후 아래 명령으로 수동 병합이 가능합니다:

```
"devenv-security에 보안 설정 추가해줘" 라고 입력하면 이 단계만 재실행됩니다.
```

### 7-2. 병합 제안 (post-app 프로필에서만)

post-app 프로필인 경우에만 다음 메시지를 출력하고 사용자 응답을 기다리세요:

```
> devenv-app이 감지되었습니다. (Spring Boot backend + React frontend)
> 샘플 앱에 보안 설정을 추가할까요?
>
>   추가될 내용:
>   - backend/ → sonar-project.properties
>   - backend/ → Jenkinsfile에 SonarQube + Trivy 스테이지
>   - frontend/ → sonar-project.properties
>   - frontend/ → Jenkinsfile에 SonarQube 스테이지
>   - (Jenkinsfile은 GitLab에도 자동 push됩니다)
>
>   1. 예, 보안 설정 추가
>   2. 아니오, 건너뜀
```

응답에 따라:
- "1" → 7-3으로 이동하여 병합 실행 후 PHASE 8로 이동
- "2" → PHASE 8로 이동

### 7-3. 병합 실행 (YES 선택 시)

- `backend/frontend`에 `sonar-project.properties` 추가
- Jenkinsfile 보안 stage 삽입
- GitLab에 비파괴 방식으로 반영
- 결과를 `preset.json security.jenkins_integration`에 기록

---

## PHASE 8: 완료 요약 + 프리셋 저장

**진입 조건**: PHASE 7 완료 후 진입합니다.
**완료 조건**: 완료 요약을 출력하고 preset.json을 저장한 후 스킬을 종료합니다.

### 8-1. 설치 완료 요약 출력

다음 형식으로 완료 요약을 출력하세요:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 devenv-security 설치 완료
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 서비스              상태      URL                      계정
 ─────────────────────────────────────────────────────────
 SonarQube         ✅ 신규   http://10.0.1.8:9000      admin / changeme
 OWASP ZAP         ⏭️ 스킵   http://10.0.1.8:8090      (기존 유지)
 Trivy             ✅ 신규   (CLI 도구 — trivy --help)
 Dependency-Check  🔧 재설치  (Jenkins 플러그인)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Jenkins 연동: backend / frontend / admin 잡 업데이트 완료
 devenv-app 병합:   sonar-project.properties + Jenkinsfile 반영됨
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

 다음 단계:
   1. SonarQube 초기 로그인 후 비밀번호 변경
      → http://10.0.1.8:9000  (admin / changeme)
   2. Jenkins 빌드 실행하여 Quality Gate strict 실패 동작 확인
   3. Trivy 스캔 테스트: trivy image <이미지명>
   4. ZAP 스캔 테스트: http://10.0.1.8:8090
```

### 8-2. 상태 아이콘 기준

| 아이콘 | 의미 |
|--------|------|
| ✅ 신규 | 이번에 새로 설치됨 |
| ⏭️ 스킵 | 기존 정상 서비스 — 변경 없음 |
| 🔧 재설치 | 오류 해결 후 재설치됨 |

### 8-3. preset.json 갱신

설치 완료 후 `security` 섹션의 핵심 상태만 저장합니다.
- 저장 대상: 버전, 포트, 활성화 여부, 설치 상태, Jenkins 연동 상태
- 저장 금지: 불필요한 샘플 payload/중복 필드
- 민감값은 **`preset.json`에 `*_ref` 참조만** 저장하고, 실값은 `${DEVENV_HOME}/secrets/security.env` (`chmod 600`)에만 둡니다. 예시는 저장소 `secrets/security.env.example` → 위 경로로 복사. `install-security.sh`는 파일이 있으면 Compose 렌더 전에 자동 `source`합니다.
- PHASE 종료 시 구조화 로그 1줄 출력 (zsh 호환: 필드명 `state`, 변수명 `status` 사용 금지):
  - `[PHASE-DONE] {phase, state, services, duration_s, errors[]}`
- 중요 작업 분기에는 `[DECISION-POINT]` 마커를 남깁니다. (strict 전환, 볼륨 삭제, EOL 업그레이드)
- PR 설명 작성 시 SEC 코드-변경 매핑은 `references/sec-code-mapping.md`를 사용합니다.

---

## 오류 처리 (compact)

상세 대화문은 반복 토큰이 크므로 본문에서는 코드/분류/기본 조치만 유지합니다.
구체 메시지 템플릿은 `references/troubleshooting.md`를 참조합니다.

오류는 아래 4개 카테고리로 분류합니다.

- `TRANSIENT`: 재시도 가능한 일시 오류
- `CONFIG`: 사용자 입력/설정 오류
- `ENVIRONMENT`: 의존성/실행환경 부재
- `FATAL`: 중단이 필요한 치명 오류

| 코드 | 분류 | 증상 | 기본 조치 |
|---|---|---|---|
| `SEC-E101` | ENVIRONMENT | SonarQube 즉시 종료 (`vm.max_map_count`) | sysctl 보정 후 재시도 |
| `SEC-E201` | ENVIRONMENT | ZAP 이미지 `zaproxy/zap-stable:2.17.0` pull 실패 | Docker Hub/네트워크 확인 (고정 태그, fallback 없음) |
| `SEC-E202` | CONFIG | SonarInstallation 생성자 mismatch | `references/jenkins-sonar-installation.groovy` 의 (Secret) null + Array.newInstance 패턴 적용 |
| `SEC-E601` | CONFIG | Jenkins CSRF crumb 누락/실패 | `curl -G` crumb 조회 + 모든 POST에 crumb 헤더 (`scripts/lib/jenkins.sh`) |
| `SEC-E204` | CONFIG | heredoc + pipe stdin 충돌 | 변수 캡처 후 `python3 -c` 단일 인자 패턴 사용 |
| `SEC-E301` | CONFIG | ZAP 포트 충돌 | 대체 포트 재할당 후 재시도 |
| `SEC-E401` | TRANSIENT | SonarQube 기동 지연 | budget 내 재시도 후 로그 점검 |
| `SEC-E501` | ENVIRONMENT | NVD 연결 실패 | API 키 입력 또는 제한 모드 진행 |
| `SEC-E602` | TRANSIENT | Jenkins 플러그인 재시작 필요 | 즉시/안전 재시작 선택 |

오류 출력은 compact 규약을 유지합니다.

```text
[SEC-EXXX] short summary
cause=<1-line>
action=<1-line>
next=retry|skip|abort
```

---

## 헬스체크 기준

```bash
# SonarQube
curl -fsS http://<SECURITY_IP>:9000/api/system/status | grep '"status":"UP"'

# OWASP ZAP (ZAP UI 응답 확인)
curl -fsS http://<SECURITY_IP>:8090 > /dev/null && echo "ZAP OK"

# Trivy (docker 기본)
docker run --rm aquasec/trivy:latest --version

# Dependency-Check (Jenkins 플러그인 방식)
curl -fsS http://<JENKINS_IP>:8080/pluginManager/api/json?depth=1 \
  | grep -o '"dependency-check-jenkins-plugin"' | head -1
```

---

## 참조 파일

아래 경로는 **표준 예시 경로**입니다. 구현체 구조에 따라 동일 역할의 파일로 매핑해도 됩니다.

| 파일 | 내용 |
|------|------|
| `scripts/00-preflight.sh` | 설치 전 필수 도구/리소스/포트/커널 파라미터 점검 |
| `docker-compose.security.yml` | SonarQube + OWASP ZAP 컨테이너 정의 |
| `scripts/install-security.sh` | 보안 서비스 설치 스크립트 |
| `scripts/health-check.sh` | 전체 헬스체크 (보안 서비스 포함) |
| `scripts/jenkins-install-plugins.sh` | Jenkins 플러그인 설치 자동화 |
| `scripts/jenkins-configure.sh` | Sonar 연동/crumb/웹훅 설정 |
| `scripts/bootstrap-sonar.sh` | admin 비밀번호 변경 + 토큰 발급 |
| `scripts/backup.sh` | Sonar DB/볼륨 백업 |
| `scripts/uninstall-security.sh` | 보안 스택 제거 (`--keep-volumes` 지원) |
| `scripts/lib/jenkins.sh` | Jenkins GET/POST + crumb 헬퍼 |
| `references/optimization-checklist.md` | 보안 게이트/스캔 비용/운영 KPI 점검 |
| `references/jenkins-sonar-installation.groovy` | SonarInstallation 버전별 생성자 참고 |
| `references/tls-migration.md` | HTTP→HTTPS 전환 가이드 |
| `references/airgap.md` | 에어갭 절차 (Trivy DB/오프라인 플러그인) |
| `references/upgrade-and-rollback.md` | SonarQube 업그레이드/롤백 절차 |
| `references/compatibility-matrix.md` | Jenkins LTS x sonar-plugin x SonarQube 매트릭스 |
| `references/pr-scan-guide.md` | PR 스캔 파라미터 + GitLab MR decoration |
| `references/sec-code-mapping.md` | SEC-E 코드별 변경 매핑표 |
| `preset.json` | 이전 설치 설정 저장/로드 |
| `sample-apps/backend/sonar-project.properties` | SonarQube 백엔드 프로젝트 설정 |
| `sample-apps/frontend/sonar-project.properties` | SonarQube 프론트엔드 프로젝트 설정 |
| `tests/golden/phase{1..8}.txt` | compact 출력 회귀 기준 |
| `tests/verify-golden.sh` | golden 출력 검증 스크립트 |
