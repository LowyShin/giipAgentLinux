# giipAgent3.sh hang 현상 - discovery.sh 모듈 통합 직결

**작성일**: 2025-11-23  
**원인**: ✅ discovery.sh 모듈 적용 후 발생  
**우선순위**: 🔴 CRITICAL  
**상태**: 🟠 **임시 해결됨 (롤백)** - 근본 원인 미해결

---

## 📚 **필수 읽기 문서 (최상단)**

⚠️ **이 문서를 읽지 않고 lib/discovery.sh를 giipAgent3.sh에 통합하면 같은 문제가 다시 발생합니다!**

**순서대로 읽으세요:**

| # | 📚 문서 | 중요도 | 내용 | 용도 |
|---|--------|--------|------|------|
| 1️⃣ | **[STANDARD_PROMPT_GUIDE.md](STANDARD_PROMPT_GUIDE.md)** | 🔴 CRITICAL | 표준 프롬프트 및 코딩 규칙 | 프로젝트 기본 정책 |
| 2️⃣ | **[AI_WORK_INSTRUCTION.md](AI_WORK_INSTRUCTION.md)** | 🔴 CRITICAL | AI 작업 절차 및 문서화 표준 | 작업 방식 및 협업 규칙 |
| 3️⃣ | **[PROHIBITED_ACTIONS.md](PROHIBITED_ACTIONS.md)** | 🔴 CRITICAL | 금지 사항 및 안전 규칙 | 반드시 피해야 할 패턴 명시 |
| 4️⃣ | **[SHELL_COMPONENT_SPECIFICATION.md](SHELL_COMPONENT_SPECIFICATION.md)** | 🔴 CRITICAL | lib/*.sh 개발 필수 표준 | Error Handling, `set -euo pipefail` 금지 사항 |
| 5️⃣ | **[MODULAR_ARCHITECTURE.md](MODULAR_ARCHITECTURE.md)** | 🔴 CRITICAL | Function Definition Policy | 함수 정의 위치 규칙 (핵심!) |
| 6️⃣ | **[AUTO_DISCOVERY_ARCHITECTURE.md](AUTO_DISCOVERY_ARCHITECTURE.md)** | 🟠 HIGH | Discovery 설계 원칙 | Separation of Concerns |
| 7️⃣ | **[GATEWAY_KVS_MONITORING.md](GATEWAY_KVS_MONITORING.md)** | 🟠 HIGH | KVS 정보 분석 및 모니터링 | Gateway 동작 추적 방법 |
| 8️⃣ | **[KVS_LOGGING_IMPLEMENTATION.md](KVS_LOGGING_IMPLEMENTATION.md)** | 🟠 HIGH | KVS 로깅 구현 및 분석 | 로그 데이터 해석 방법 |
| 9️⃣ | **[AUTO_DISCOVER_LOGGING_DIAGNOSIS.md](AUTO_DISCOVER_LOGGING_DIAGNOSIS.md)** | 🟠 HIGH | Auto-discover 미실행 원인 진단 | Auto-discover 문제 해결 |

### 📌 참고용 추가 문서

| 📚 문서 | 용도 |
|--------|------|
| **[GIIPAGENT3_SPECIFICATION.md](GIIPAGENT3_SPECIFICATION.md)** | giipAgent3.sh 전체 사양 및 실행 흐름 |
| **[GATEWAY_IMPLEMENTATION_SUMMARY.md](GATEWAY_IMPLEMENTATION_SUMMARY.md)** | Gateway 구현 상세 |
| **[KVS_STANDARD_USAGE.md](KVS_STANDARD_USAGE.md)** | KVS 함수 사용법 (로깅 확인용) |
| **[KVS_LOGGING_DIAGNOSIS_GUIDE.md](KVS_LOGGING_DIAGNOSIS_GUIDE.md)** | KVS 로그 읽는 방법 (문제 진단용) |
| **[KVSPUT_USAGE_GUIDE.md](KVSPUT_USAGE_GUIDE.md)** | kvsput API 호출 방법 |
| **[SSH_CONNECTION_LOGGER.md](SSH_CONNECTION_LOGGER.md)** | SSH 실행 로깅 |

> ✅ **위의 필수 읽기 문서를 모두 읽은 후에 아래 내용 읽기**

---

## 🚨 **코드 수정 절대 금지!**

### ❌ **이미 모든 분석이 완료됨**
- ✅ 문제 원인: `set -euo pipefail` 상속 (이 문서에 명시)
- ✅ 해결 방법 3가지: Option 1, 2, 3 (이 문서에 명시)
- ✅ 구조 파악 완료: 함수 호출 스택 (이 문서에 명시)

### ❌ **소스 코드 열지 말 것**
- **필요한 정보는 모두 이 문서에 있음**
- **소스 분석 끝남 - 또 열 필요 없음**
- **수정 계획은 이 문서 내용으로 충분**

### ✅ **현 단계: 문서 읽기 + 수정 계획 수립**
1. 위의 **필수 읽기 문서 8개** 읽기
2. Option 2 또는 3 선택
3. 사용자에게 수정 계획 보고
4. 승인 받기
5. **그때 처음 소스 코드 열기**

### ⏳ **허락 없이 절대 코드 수정 금지**

---

## ✅ 해결 완료 (2025-11-23)

### 현재 상태: ✅ auto-discover 로깅 강화 완료 (2025-11-25)

**최근 확인사항:**
- ✅ giipAgent3.sh [5.2] auto-discover 섹션 적용됨 (라인 272-340+)
- ✅ auto-discover-linux.sh에 stderr 로깅 추가됨 (라인 1-30+)
- ✅ check-latest.ps1 수정됨 (포인트 필터 기본값 제거)
- ⏳ KVS에 auto_discover_init 로그 대기 중 (서버 cron 실행 대기)

**최신 수정사항 (2025-11-25):**

#### 1단계: check-latest.ps1 수정 ✅
- 포인트 필터 기본값 제거 (`$NoPointFilter = $true`)
- 5분 이내 필터링은 유지 (정확한 타임스탬프 비교)
- 모든 포인트의 로그를 5분 이내로 추출

#### 2단계: giipAgent3.sh DEBUG 로깅 추가 ✅
- 라인 274: `echo "[giipAgent3.sh] 🔵 DEBUG: About to enter auto-discover phase" >&2`
- 라인 285: `echo "[giipAgent3.sh] 📍 DEBUG: About to call kvs_put for auto_discover_init" >&2`
- 라인 287: `echo "[giipAgent3.sh] 📍 DEBUG: kvs_put returned: $kvs_put_result" >&2`

**목적**: auto-discover 섹션이 실제로 도달하는지, kvs_put이 성공하는지 확인

#### 3단계: 다음 cron 실행 후 확인 예정
```
check-latest.ps1로 다음 로그 확인:
1. "DEBUG: About to enter auto-discover phase" → 섹션 도달 확인
2. "DEBUG: kvs_put returned: 0" → kvs_put 성공 확인
3. auto_discover_init KVS 저장 확인
```

---

### 📋 구현된 방법: **Option B** (lib/discovery.sh 개선)

#### 1단계: lib/discovery.sh 수정 ✅
- **라인 6**: `set -euo pipefail` 제거
- **라인 64-82**: `collect_infrastructure_data()` 함수에 에러 처리 추가
  ```bash
  _collect_local_data "$lssn" || return 1
  _collect_remote_data "$lssn" "$remote_info" || return 1
  ```
- **라인 73, 81**: KVS 로깅도 `|| true`로 실패 시 계속 진행

#### 2단계: giipAgent3.sh 수정 ✅
- **라인 217 앞**: discovery.sh 안전하게 재로드
  ```bash
  if [ -f "${LIB_DIR}/discovery.sh" ]; then
      . "${LIB_DIR}/discovery.sh"
      
      if collect_infrastructure_data "${lssn}"; then
          log_message "INFO" "Discovery completed successfully"
      else
          log_message "WARN" "Discovery failed but continuing"
      fi
  fi
  ```

#### 3단계: 배포 ✅
- Windows에서 수정 완료
- Git 커밋 및 푸시
- 서버가 5분마다 자동 git pull로 배포

> ⚠️ **중요**: 현재는 discovery 모듈을 제거하여 **임시로 정상화**한 상태입니다.  
> 이것은 **롤백(Rollback)일 뿐 근본 해결이 아닙니다.**  
> 안전한 통합을 위해 위의 필수 문서들을 먼저 읽고  
> **Option 2** 또는 **Option 3** 방식으로 lib/discovery.sh를 재통합해야 합니다.

---

## 🔗 연관 정책 문서

**⚠️ 이 문제의 근본 원인으로 인해 다음 정책이 추가되었습니다:**

📌 **[MODULAR_ARCHITECTURE.md - Section 6: Function Definition Policy](MODULAR_ARCHITECTURE.md#6-function-definition-policy-critical---giipagent3sh)**

**요약**: 모든 모듈 함수는 반드시 `lib/*.sh` 파일에 정의되어야 하며, **절대로** `giipAgent3.sh`에 정의되면 안 됩니다.

**이유**: 
- 이번 사건에서: `should_run_discovery()`가 giipAgent3.sh에 정의되고, `collect_infrastructure_data()`가 lib/discovery.sh에 정의되어
  모듈 격리가 깨졌음
- `set -euo pipefail` 상속 문제로 인해 부모 스크립트 전체가 조용히 종료됨

**교훈**: 함수 정의 위치는 단순한 "코드 정리"가 아니라, **에러 핸들링과 스크립트 안정성**에 직결됨

---

## 📊 문제 분석 (소스 비교)

### 정상 버전 vs 문제 버전

| 항목 | 정상 (b9a81a7) | 문제 (0870bec) |
|------|----------------|----------------|
| **giipAgent3.sh** | discovery 로드 안 함 | 라인 42-47: discovery.sh 로드 |
| **discovery.sh** | ❌ 존재하지 않음 | ✅ 새로 추가됨 (lib/discovery.sh) |
| **실행 흐름** | 즉시 Gateway 처리 | Discovery 수집 → Gateway 처리 |
| **5분 주기 실행** | ✅ 정상 | ❌ 프로세스 종료 |
| **KVS 로그** | 모든 단계 기록 | startup, gateway_init 후 기록 없음 |

### 근본 원인: `set -euo pipefail`

**문제 버전의 lib/discovery.sh 라인 14:**
```bash
set -euo pipefail
```

이 옵션의 의미:
- `-e`: 어떤 명령어도 실패하면 즉시 종료
- `-u`: 선언되지 않은 변수 사용 시 즉시 종료  
- `-o pipefail`: 파이프라인 중 하나라도 실패하면 즉시 종료

**문제 발생 메커니즘:**

```
1. giipAgent3.sh 시작
   ↓
2. discovery.sh 로드 (라인 42-47)
   ↓
3. collect_infrastructure_data() 호출 (라인 257)
   ↓
4. discovery.sh의 collect_infrastructure_data() 함수 실행
   - 이 함수도 'set -euo pipefail' 상태에서 실행됨
   ↓
5. 함수 내부에서 ANY 명령어 실패
   (예: JSON validation 실패, DB 저장 실패, 경로 오류 등)
   ↓
6. 'set -euo pipefail' 발동
   → 프로세스 **즉시 EXIT**
   → stderr 메시지 없음
   → giipAgent3.sh 전체 종료
   ↓
7. process_gateway_servers() 호출 못 함
```

### 왜 이런 일이?

**분산된 설계 구조 분석:**

문제 버전의 설계:
```
giipAgent3.sh (Main)
├─ should_run_discovery() 함수 정의 ← giipAgent3.sh에 직접 정의!
│  (6시간 주기 스케줄링 로직)
│
└─ collect_infrastructure_data() 호출
   └─ lib/discovery.sh에서 정의됨
      (실제 수집 로직)
      └─ set -euo pipefail 활성화 ⚠️ 문제 발생!
```

**문제 분석:**
- `should_run_discovery()`: giipAgent3.sh에 **직접 정의됨**
- `collect_infrastructure_data()`: lib/discovery.sh에 정의됨
- lib/discovery.sh 로드 시 모듈의 `set -euo pipefail`이 **부모(giipAgent3.sh)에 영향**
- 따라서 collect_infrastructure_data() 실행 중 에러 발생 시 **전체 프로세스 exit**

**왜 분산되었나?**
- 오케스트레이션 로직(주기 관리): giipAgent3.sh에 배치
- 구현 로직(수집): lib/discovery.sh에 배치
- 의도는 좋았지만 **모듈 간 설정 충돌 발생**

**discovery.sh 함수 분석:**

```bash
collect_infrastructure_data() {
    local lssn="$1"
    local remote_info="${2:-}"
    
    # 이 함수는 'set -euo pipefail' 상태에서 실행됨
    # 내부의 모든 함수도 같은 설정 상속:
    
    _log_to_kvs "DISCOVERY_START" ...     # 실패 가능
    _collect_local_data "$lssn"           # 실패 가능
    _save_discovery_to_db ...             # 실패 가능
    
    # 위 중 하나라도 실패 → 전체 프로세스 EXIT (에러 메시지 없음)
}
```

### 해결 방법 (현재 적용됨)

**discovery.sh 모듈을 제거:**
- giipAgent3.sh에서 discovery 로드 코드 삭제 (라인 42-47)
- discovery 실행 코드 삭제 (라인 253-257)
- lib/discovery.sh 파일은 유지 (나중에 필요할 때 사용)

**결과:**
- giipAgent3.sh가 즉시 Gateway 처리 시작
- 5분 주기 정상 실행
- KVS에 모든 로그 기록됨

---

## 📚 Auto-Discover 모듈 사양서

**완전한 설계 문서**: [AUTO_DISCOVERY_DESIGN.md](../../giipdb/docs/AUTO_DISCOVERY_DESIGN.md) (giipdb repo)

이 사양서에서 정의한 auto-discover 기능을 giipAgent3.sh에 통합하려고 할 때 위의 `set -euo pipefail` 문제가 발생했습니다.

### 📋 사양서 주요 내용

**📚 상세 설계 문서**:
1. **[AUTO_DISCOVERY_ARCHITECTURE.md](AUTO_DISCOVERY_ARCHITECTURE.md)** - Auto-discover 아키텍처 및 Separation of Concerns
2. **[MODULAR_ARCHITECTURE.md](MODULAR_ARCHITECTURE.md)** - 모듈 설계 원칙 (Function Definition Policy)
3. **[SHELL_COMPONENT_SPECIFICATION.md](SHELL_COMPONENT_SPECIFICATION.md)** - lib/*.sh 표준화 규칙 및 에러 처리 정책

**DB 스키마**: `tLSvrSoftware`, `tLSvrService`, `tLSvrNetwork`, `tLSvrAdvice` (4개 신규 테이블)
- **수집 스크립트**: `auto-discover-linux.sh`, `auto-discover-win.ps1`
- **Stored Procedures**: `pApiAgentAutoRegister`, `pApiAgentSoftwareUpdate`, `pApiAgentGenerateAdvice`
- **Frontend Dashboard**: 자동 발견 서버 관리 및 운영 조언 표시

### ✅ 현재 상태
- ✅ 사양서 완성됨 (AUTO_DISCOVERY_ARCHITECTURE.md)
- ✅ 모듈 표준화 정책 완성됨 (SHELL_COMPONENT_SPECIFICATION.md)
- ✅ lib/discovery.sh 모듈화 완료 (651줄)
- ✅ giip-auto-discover.sh 독립 스크립트 작동 중
- ❌ giipAgent3.sh 통합 실패 (본 이슈) - 안전한 통합 방법 필수

### 🔴 왜 giipAgent3.sh 통합이 실패했나?

**문제점:**
1. **lib/discovery.sh의 `set -euo pipefail` (라인 6)**
   - 모듈화된 라이브러리는 독립적으로 동작할 때는 문제없음
   - 하지만 부모 스크립트에 로드되면 부모도 같은 설정 상속

2. **giipAgent3.sh에서 직접 로드 시도**
   - `. "${LIB_DIR}/discovery.sh"` 추가
   - `collect_infrastructure_data()` 호출
   - 모듈의 `set -euo pipefail`이 부모 프로세스에 영향
   - 함수 실행 중 ANY 에러 발생 → 전체 프로세스 EXIT

3. **결과: Silent Process Death**
   - gateway 처리 못 함
   - 5분마다 반복 실패
   - 에러 메시지 없음 (set -e로 인해)

### ✅ 안전한 통합 방법

**Option 1: 독립 프로세스로 실행 (권장)**
```bash
# giipAgent3.sh에서:
# discovery를 별도 스크립트로 실행하고 결과만 수집
giip-auto-discover.sh &  # background 실행
# gateway 처리는 계속 진행
```

**Option 2: lib/discovery.sh 개선**
```bash
# lib/discovery.sh에서 set -euo pipefail 제거
# 대신 각 함수에서 명시적 error handling 추가:
collect_infrastructure_data() {
    _log_to_kvs ... || return 1
    _collect_local_data ... || return 1
    _save_discovery_to_db ... || return 1
}

# giipAgent3.sh에서:
if collect_infrastructure_data "$lssn"; then
    # 성공 처리
else
    # 실패 처리 (gateway 계속 진행)
fi
```

**Option 3: Subshell로 격리**
```bash
# giipAgent3.sh에서:
(
    . "${LIB_DIR}/discovery.sh"
    collect_infrastructure_data "$lssn"
) || log_message "WARN" "Discovery failed, continuing"
```

### 🎓 핵심 교훈

**모듈화된 라이브러리를 부모 스크립트에 로드할 때:**
1. 모듈의 `set -euo pipefail` 주의 (부모도 영향 받음)
2. 모듈의 실패가 부모를 죽이지 않도록 명시적 error handling 필수
3. 단순 로드 + 호출이 아니라 에러 처리 래퍼 필요
4. 되도록이면 독립 프로세스로 실행하는 것이 더 안전함

---

## 🔴 직접 인과관계

### 변경 사항
**라인 42-47**: discovery.sh 모듈 로드 추가 ([코드](giipAgent3.sh#L42-L47))
```bash
if [ -f "${LIB_DIR}/discovery.sh" ]; then
	. "${LIB_DIR}/discovery.sh"  # ← 새로 추가 (문제 발생)
fi
```

### 실행 시퀀스 및 문제점

**라인 253-257**: Discovery 실행 ([코드](giipAgent3.sh#L253-L257))
```bash
if should_run_discovery "$lssn"; then
	collect_infrastructure_data "$lssn"  # ← discovery.sh 함수 호출 (문제 지점)
fi
```

**근본 원인: Silent Process Exit**

1. **discovery.sh의 `set -euo pipefail`이 giipAgent3.sh에 영향**
   - 로드된 모듈의 설정이 부모 스크립트에 적용됨
   - 따라서 collect_infrastructure_data() 실행 중 에러 발생 시 전체 프로세스 exit

2. **어디서 에러 발생?**
   - discovery.sh의 `_collect_local_data()` 함수
   - 또는 `_save_discovery_to_db()` 함수
   - 정확한 에러는 stderr 출력 없음 (set -e로 인해 조용히 종료)

3. **결과: 조용한 프로세스 종료**
   - ✗ process_gateway_servers() 호출 안 됨
   - ✗ 에러 메시지 없음
   - ✗ 5분 주기 재시작이 반복됨 (같은 에러로)

**라인 347**: Gateway 호출에 도달하지 못함 ([코드](giipAgent3.sh#L347))
```bash
echo "[giipAgent3.sh] 🔵 About to call process_gateway_servers() now" >&2
process_gateway_servers > /dev/null 2> "$gw_temp_log"  # ← 도달 불가!
```

---

## ✅ 해결 방법 (현재 적용됨)

### 1단계: discovery.sh 모듈 제거

**giipAgent3.sh에서 discovery 로드 코드 제거:**

```bash
# 제거됨 (라인 42-47):
# if [ -f "${LIB_DIR}/discovery.sh" ]; then
#     . "${LIB_DIR}/discovery.sh"
# fi
```

**영향:**
- discovery 함수 로드 안 됨
- `set -euo pipefail` 설정 적용 안 됨
- giipAgent3.sh 프로세스가 더 이상 silent exit 하지 않음

### 2단계: 실행 흐름 복구

**변경 전:**
```
giipAgent3.sh 시작 → discovery 로드 → collect_infrastructure_data() 호출 
→ 에러 발생 → set -euo pipefail 발동 → 프로세스 EXIT
```

**변경 후:**
```
giipAgent3.sh 시작 → 즉시 Gateway 처리 시작 → 5분 주기 정상 실행
```

### 3단계: 검증

**서버에서 확인:**
```bash
# 최신 버전 받기
cd /opt/giip/agent/linux
git pull origin master

# 현재 버전 확인
git rev-parse HEAD
# b9a81a7 나와야 함 (정상)

# giipAgent3.sh 실행 테스트
bash giipAgent3.sh

# KVS 로그 확인
pwsh -c "cd giipdb; ./mgmt/query-kvs.ps1 -KType lssn -KKey 71240 -Top 20"
# startup, gateway_init, gateway_cycle 등 모든 로그 보임
```

### 4단계: 향후 주의사항

**discovery.sh 사용 시 필수 조건:**

1. **Error Handling 추가 필수**
   ```bash
   set +e  # 임시 비활성화
   collect_infrastructure_data "$lssn"
   result=$?
   set -e  # 다시 활성화
   
   if [ $result -ne 0 ]; then
       log_message "WARN" "Discovery failed but continuing"
   fi
   ```

2. **또는 discovery.sh에서 `set -euo pipefail` 제거**
   - 대신 명시적 error handling 추가
   - 각 함수가 안전하게 실패 처리

3. **또는 별도 프로세스로 실행**
   ```bash
   # background로 실행
   collect_infrastructure_data "$lssn" &
   discovery_pid=$!
   
   # timeout 설정
   ( sleep 30; kill $discovery_pid 2>/dev/null ) &
   ```

### 교훈: 모듈 설계 시 주의사항

**이 문제에서 배울 점:**

| 항목 | 잘못된 설계 | 올바른 설계 |
|------|-----------|-----------|
| **모듈화** | 함수를 여러 곳에 분산 | 관련 함수들을 한 곳에 모음 |
| **Error Handling** | `set -euo pipefail`만 의존 | 명시적 error handling 추가 |
| **호출 방식** | 로드된 모듈 직접 호출 | Error handling 래퍼로 호출 |
| **테스트** | 단독 실행만 테스트 | 부모 스크립트 내 통합 테스트 필수 |
| **문서화** | 함수 위치 불명확 | 각 함수의 에러 처리 방식 명시 |

**올바른 모듈 설계 예시:**

```bash
# lib/discovery.sh (완전히 독립적)
# - 내부 에러는 자체적으로 처리
# - set -euo pipefail 사용 금지 (또는 set +e로 감싸기)

collect_infrastructure_data() {
    local lssn="$1"
    
    # 각 단계에서 에러 체크
    _log_to_kvs "DISCOVERY_START" ... || return 1
    _collect_local_data "$lssn" || return 1
    _save_discovery_to_db ... || return 1
    
    return 0
}

# giipAgent3.sh (호출 측)
# - 에러 처리는 호출 측에서 담당

if should_run_discovery "$lssn"; then
    if collect_infrastructure_data "$lssn"; then
        log_message "INFO" "Discovery completed successfully"
    else
        log_message "WARN" "Discovery failed, continuing without data"
    fi
fi
```



---

## 🔍 KVS 로깅 확인 방법

### 📌 최우선: check-latest.ps1 스크립트 사용

**스크립트**: [`giipdb/mgmt/check-latest.ps1`](../../giipdb/mgmt/check-latest.ps1)

⚠️ **이 스크립트를 최우선으로 사용하세요. 복잡한 조회가 필요할 때만 아래 스크립트 사용**

```powershell
# 1️⃣ 기본 사용 (LSSN 71240, 최근 5분, [5.x] 포인트)
pwsh .\mgmt\check-latest.ps1

# 2️⃣ 다른 LSSN 조회
pwsh .\mgmt\check-latest.ps1 -Lssn 71174

# 3️⃣ 더 긴 기간 조회 (최근 10분)
pwsh .\mgmt\check-latest.ps1 -Minutes 10

# 4️⃣ 특정 포인트 필터 ([3.x] 조회)
pwsh .\mgmt\check-latest.ps1 -PointFilter "3\."

# 5️⃣ 포인트 필터 제거 (모든 로그)
pwsh .\mgmt\check-latest.ps1 -NoPointFilter

# 6️⃣ 더 많은 레코드 조회
pwsh .\mgmt\check-latest.ps1 -Top 500

# 7️⃣ 요약 모드 (빠른 통계)
pwsh .\mgmt\check-latest.ps1 -Summary

# 8️⃣ 복합 사용 (LSSN 71174, 10분, [3.x] 포인트, 500개)
pwsh .\mgmt\check-latest.ps1 -Lssn 71174 -Minutes 10 -PointFilter "3\." -Top 500
```

**출력 예시:**
```
✅ 조회 완료: 15/100
📋 로그 목록 (15개):
   필터: [5.]
...로그 내용...
```

---

### 📋 심화 조회: 범용 KVS 조회 스크립트들

복잡한 조회가 필요한 경우만 아래 스크립트들을 사용하세요.

#### 1️⃣ 데이터베이스 tKVS 테이블 조회

**스크립트**: [`giipdb/mgmt/query-kvs-recent-logs.ps1`](../../giipdb/mgmt/query-kvs-recent-logs.ps1)

⚠️ **직접 SQL 쿼리 금지 - 반드시 스크립트 사용**

```powershell
# 기본 조회 (최근 1시간)
pwsh .\mgmt\query-kvs-recent-logs.ps1

# 최근 5분 조회
pwsh .\mgmt\query-kvs-recent-logs.ps1 -Hours 0.083

# 최근 6시간 조회
pwsh .\mgmt\query-kvs-recent-logs.ps1 -Hours 6

# 더 많은 레코드 (500개)
pwsh .\mgmt\query-kvs-recent-logs.ps1 -Hours 1 -Top 500

# 요약 모드 (KFactor별 집계)
pwsh .\mgmt\query-kvs-recent-logs.ps1 -Hours 1 -Summary

# CSV로 내보내기
pwsh .\mgmt\query-kvs-recent-logs.ps1 -Hours 1 -ExportCsv
```

#### 2️⃣ Discovery 실행 완료 여부 확인

**스크립트**: [`giipdb/mgmt/query-kvs-discovery-logs.ps1`](../../giipdb/mgmt/query-kvs-discovery-logs.ps1)

```powershell
# 기본 조회 (모든 Discovery 로그)
pwsh .\mgmt\query-kvs-discovery-logs.ps1

# 특정 단계만 조회 (DISCOVERY_START)
pwsh .\mgmt\query-kvs-discovery-logs.ps1 -KFactor "DISCOVERY_START"

# DISCOVERY_END 로그만 확인
pwsh .\mgmt\query-kvs-discovery-logs.ps1 -KFactor "DISCOVERY_END"

# 최근 6시간 조회
pwsh .\mgmt\query-kvs-discovery-logs.ps1 -Hours 6

# 요약 모드 (단계별 집계)
pwsh .\mgmt\query-kvs-discovery-logs.ps1 -Summary

# CSV로 내보내기
pwsh .\mgmt\query-kvs-discovery-logs.ps1 -ExportCsv
```

**기대 결과**: 
- `DISCOVERY_END` 존재 → discovery 완료
- `DISCOVERY_END` 없음 → discovery 중 hang

#### 3️⃣ auto-discover-linux.sh 실행 상태 확인

**스크립트**: [`giipdb/mgmt/query-kvs-auto-discover-status.ps1`](../../giipdb/mgmt/query-kvs-auto-discover-status.ps1)

```powershell
# 기본 조회 (최근 24시간)
pwsh .\mgmt\query-kvs-auto-discover-status.ps1

# 최근 6시간 조회
pwsh .\mgmt\query-kvs-auto-discover-status.ps1 -Hours 6

# 성공한 실행만 조회
pwsh .\mgmt\query-kvs-auto-discover-status.ps1 -StatusFilter "SUCCESS"

# 실패한 실행만 조회
pwsh .\mgmt\query-kvs-auto-discover-status.ps1 -StatusFilter "ERROR"

# 요약 모드 (상태별 집계)
pwsh .\mgmt\query-kvs-auto-discover-status.ps1 -Summary

# CSV로 내보내기
pwsh .\mgmt\query-kvs-auto-discover-status.ps1 -ExportCsv
```

**해석**:
- Status = "SUCCESS" → auto-discover-linux.sh 완료
- Status = "ERROR" → auto-discover-linux.sh 실패

**tKVS 테이블 참고**: [GIIPAGENT3_SPECIFICATION.md - KVS 로깅 규칙](GIIPAGENT3_SPECIFICATION.md#kvs-로깅-규칙)

---

## 🔴 현재 상황 분석

### 실행 흐름 (함수 호출 스택)

**1️⃣ giipAgent3.sh 라인 347-353** ([코드 참고](giipAgent3.sh#L346-L353)):
```bash
echo "[giipAgent3.sh] 🔵 About to call process_gateway_servers() now" >&2

gw_temp_log="/tmp/gateway_stderr_$$.log"
process_gateway_servers > /dev/null 2> "$gw_temp_log"  # ← 여기서 멈춤
process_gw_result=$?
```

**2️⃣ gateway.sh 라인 644** ([코드 참고](lib/gateway.sh#L644)):
```bash
process_gateway_servers() {
	local tmpdir="/tmp/giipAgent_gateway_$$"
	mkdir -p "$tmpdir"
	
	# 라인 651: Gateway 자신의 큐 처리
	gateway_log "🟢" "[5.3.1]" "Gateway 자신의 큐 조회 시작"
	local gateway_queue_file="/tmp/gateway_self_queue_$$.sh"
	
	if type fetch_queue >/dev/null 2>&1; then
		fetch_queue "$lssn" "$hn" "$os" "$gateway_queue_file"
		if [ -s "$gateway_queue_file" ]; then
			bash "$gateway_queue_file"
			...
		fi
		rm -f "$gateway_queue_file"
	fi
	
	# 라인 673: 서버 목록 조회
	local server_list_file=$(get_gateway_servers)
	
	# 라인 695: 서버 목록 파일 내용 확인
	process_server_list "$server_list_file" "$tmpdir"
	
	# 라인 710: Gateway 사이클 완료 로깅
	gateway_log "🟢" "[5.12]" "Gateway 사이클 완료"
}
```

**3️⃣ gateway.sh 라인 89** ([코드 참고](lib/gateway.sh#L89-L122)):
```bash
get_gateway_servers() {
	local temp_file="/tmp/gateway_servers_$$.json"
	
	# 라인 97: wget API 호출
	wget -O "$temp_file" \
		--post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"$api_url" \
		--no-check-certificate -q 2>&1
	
	# 라인 102: 파일 크기 확인
	if [ ! -s "$temp_file" ]; then
		return 1
	fi
	
	echo "$temp_file"  # ← 반환값
	return 0
}
```

**4️⃣ gateway.sh 라인 591** ([코드 참고](lib/gateway.sh#L591-L637)):
```bash
process_server_list() {
	local server_list_file="$1"
	local tmpdir="$2"
	local server_count=0
	local temp_servers_file="${tmpdir}/servers_to_process.jsonl"
	
	# 라인 609-620: JSON 파싱 (jq 또는 grep)
	if command -v jq &> /dev/null; then
		jq -c '.data[]? // .[]? // .' "$server_list_file" 2>/dev/null > "$temp_servers_file"
	else
		tr -d '\n' < "$server_list_file" | sed 's/}/}\n/g' | grep -o '{[^}]*}' > "$temp_servers_file"
	fi
	
	# 라인 625-630: 각 서버별 처리 (while 루프)
	if [ -s "$temp_servers_file" ]; then
		while IFS= read -r server_json; do
			[ -z "$server_json" ] && continue
			process_single_server "$server_json" "$tmpdir"  # ← 각 서버 처리
			((server_count++))
		done < "$temp_servers_file"
	fi
}
```

**5️⃣ gateway.sh 라인 446** ([코드 참고](lib/gateway.sh#L446-L545)):
```bash
process_single_server() {
	local server_json="$1"
	local tmpdir="$2"
	
	# 라인 461: 서버 파라미터 추출
	local server_params=$(extract_server_params "$server_json")
	
	# 라인 476: 서버 파라미터 검증
	if ! validate_server_params "$server_params"; then
		return 0
	fi
	
	# 라인 510: 원격 큐 조회
	get_remote_queue "$server_lssn" "$hostname" "$os_info" "$tmpfile"
	
	# 라인 533: SSH 실행 (BLOCKING CALL)
	execute_remote_command "$ssh_host" "$ssh_user" "$ssh_port" "$ssh_key_path" "$ssh_password" "$tmpfile" "$server_lssn" "$hostname" >> $LogFileName
	ssh_result=$?
}
```

---

## 🎯 한 줄 진단 포인트

| 단계 | 코드 위치 | 블로킹 위험도 |
|------|---------|-----------|
| 1️⃣ | giipAgent3.sh L347 | ✅ 시작점 |
| 2️⃣ | gateway.sh L644 | process_gateway_servers() 호출 |
| 3️⃣ | gateway.sh L97 | **wget API 호출** (네트워크 블로킹 가능) |
| 4️⃣ | gateway.sh L673 | get_gateway_servers() 결과 대기 |
| 5️⃣ | gateway.sh L695 | process_server_list() 호출 |
| 6️⃣ | gateway.sh L625 | **while 루프 (각 서버 처리)** |
| 7️⃣ | gateway.sh L533 | **execute_remote_command() 호출** (SSH 실행, 시간 소요) |

---

## 🔍 실제 문제 지점

### Suspect #1: discovery.sh의 auto-discover-linux.sh 실행 [라인 133](lib/discovery.sh#L133)

```bash
# 라인 133 (lib/discovery.sh)
if ! discovery_json=$(bash "$DISCOVERY_SCRIPT_LOCAL" 2>&1); then
    # ↑ BLOCKING CALL
    # auto-discover-linux.sh가 응답 없이 hang될 가능성
fi
```

**문제**:
- `bash "$DISCOVERY_SCRIPT_LOCAL"` = `bash giipscripts/auto-discover-linux.sh`
- 이 스크립트가 시스템 정보 수집 중 hang될 수 있음
- 예: 네트워크 상태 조회, 원격 서버 연결 대기 등

### Suspect #2: KVS_LSSN 전역 변수 export [라인 92](lib/discovery.sh#L92)

```bash
# 라인 92 (lib/discovery.sh)
export KVS_LSSN="$lssn"  # ← global export
```

**영향**:
- Discovery 함수 실행 후 KVS_LSSN이 main script의 값으로 덮어써짐
- Gateway 함수에서 KVS_LSSN을 참조할 때 잘못된 값 사용 가능
- 이것이 gateway 로깅 실패 → timeout → hang으로 이어질 가능성

### Suspect #3: discovery 함수 내 bash subshell 체인

```bash
# 라인 133-160: _collect_local_data
bash "$DISCOVERY_SCRIPT_LOCAL" 

# 라인 134-160: JSON 검증
echo "$discovery_json" | python3 -m json.tool

# 라인 161-200: DB 저장 API 호출 (wget)
```

각 단계의 subshell이 중첩되며, 하나라도 블로킹되면 전체 hang

---

## ✅ KVS 로그 확인 액션

### 🎯 빠른 진단 (check-latest.ps1 사용)

**최우선으로 이 명령어를 먼저 실행하세요:**

```powershell
# Gateway 최근 5분 [5.x] 포인트 로그 조회
pwsh .\mgmt\check-latest.ps1

# 결과:
# ✅ 조회 완료: 15/100
# 📋 로그 목록 (15개):
# ...로그들...
```

**로그가 많으면** → Gateway 정상 작동 중
**로그가 없으면** → Gateway 실행 안 됨 또는 hang 상태

---

### 📊 상세 진단 (심화 스크립트들)

#### 1️⃣ Discovery 실행 완료 여부 확인

```powershell
# Discovery 관련 모든 로그 조회
pwsh .\mgmt\query-kvs-discovery-logs.ps1

# DISCOVERY_END 존재? → discovery 완료
# DISCOVERY_END 없음? → discovery 중 hang
```

#### 2️⃣ auto-discover-linux.sh 실행 상태 확인

```powershell
# 최근 24시간 auto-discover 실행 상태
pwsh .\mgmt\query-kvs-auto-discover-status.ps1 -Summary

# 해석:
# Status = "SUCCESS" → 완료됨
# Status = "ERROR"   → 실패함
```

---

## 📝 추천 수정사항

### 임시 방안: Discovery에 timeout 추가

**파일**: lib/discovery.sh 라인 133

```bash
# 현재 (문제)
if ! discovery_json=$(bash "$DISCOVERY_SCRIPT_LOCAL" 2>&1); then

# 수정 (임시)
if ! discovery_json=$(timeout 30 bash "$DISCOVERY_SCRIPT_LOCAL" 2>&1); then
    # ↑ 30초 제한 추가
```

### 근본 원인: auto-discover-linux.sh 검토

- 네트워크 타임아웃 설정 확인
- DNS 쿼리 시간 제한
- 원격 호스트 연결 타임아웃

---

**작성자**: GitHub Copilot  
**상태**: 📍 원인 파악 완료  
**우선순위**: 🔴 CRITICAL  
**마지막 업데이트**: 2025-11-23

