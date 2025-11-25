# auto_discover_complete가 KVS에 기록되지 않는 원인 분석

**작성일**: 2025-11-25  
**문제**: `auto_discover_complete` 로그는 나타나지만 상세 로깅(`auto_discover_init`, `auto_discover_result` 등)이 KVS에 저장되지 않음  
**원인 분석**: ✅ 진행 중

---

## 1. 현재 증상

### KVS 조회 결과 (check-latest.ps1)
```
✅ auto_discover_complete (13:10:04)
   kFactor: auto_discover_complete
   kValue: {"status": "complete", "timestamp": "2025-11-25 22:10:04"}
   
❌ auto_discover_init (없음)
❌ auto_discover_result (없음)
❌ auto_discover_full_result (없음)
❌ auto_discover_error_log (없음)
```

### 의미
- **`auto_discover_complete` 만 기록됨** → **마지막 라인 (381번)만 실행됨**
- **중간 로깅이 모두 없음** → **kvs_put 함수 호출 실패 또는 스킵**

---

## 2. 소스 코드 분석

### giipAgent3.sh 구조 (라인 272-381)

```bash
# 라인 272-273: auto-discover 섹션 시작
# ================================================================
# [NEW] Auto-Discover Phase (before Gateway processing)
# ================================================================
echo "[giipAgent3.sh] 🔵 DEBUG: About to enter auto-discover phase" >&2
log_message "INFO" "[5.2] Starting auto-discover phase..."

# 라인 276-278: 로깅 #1 - 자동 발견 시작 알림
echo "[giipAgent3.sh] 🟢 [5.2] Starting auto-discover-linux.sh execution" >&2

# 라인 280-285: 스크립트 경로 결정
auto_discover_script="${SCRIPT_DIR}/giipscripts/auto-discover-linux.sh"
if [ ! -f "$auto_discover_script" ]; then
    auto_discover_script="${SCRIPT_DIR}/lib/giipscripts/auto-discover-linux.sh"
fi

# 라인 287-289: 파일 존재 여부 확인 및 디버그
echo "[giipAgent3.sh] 📍 DEBUG: auto_discover_script path: $auto_discover_script (exists: ...)" >&2

# ⚠️ 라인 290-295: 여기서 문제 발생 가능!
if [ ! -f "$auto_discover_script" ]; then
    log_message "WARN" "auto-discover script not found in both paths"
    # ✅ 이 경우만 kvs_put 호출 (failure case)
    kvs_put "lssn" "${lssn}" "auto_discover_init" "{\"status\":\"failed\",\"reason\":\"script_not_found\"...}"
    echo "[giipAgent3.sh] ⚠️ [5.2.1] auto-discover-linux.sh NOT FOUND..." >&2
else
    # 라인 298: 로깅 #2 - auto_discover_init (성공 케이스)
    echo "[giipAgent3.sh] 📍 DEBUG: About to call kvs_put for auto_discover_init" >&2
    kvs_put "lssn" "${lssn}" "auto_discover_init" "{\"status\":\"starting\"...}"
    kvs_put_result=$?
    echo "[giipAgent3.sh] 📍 DEBUG: kvs_put returned: $kvs_put_result" >&2
    
    # ... (중간 로깅 코드)
    # 라인 305-375: auto-discover 실행 및 결과 처리
    
fi

# ✅ 라인 381: auto_discover_complete (항상 실행)
echo "[giipAgent3.sh] 🟢 [5.2.end] Auto-discover phase completed" >&2
kvs_put "lssn" "${lssn}" "auto_discover_complete" "{\"status\":\"complete\",\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}"
```

---

## 3. 문제 원인 분석

### 원인 1️⃣: **조건부 실행 (if-else 구조)**

**현재 코드 흐름:**
```
라인 290: if [ ! -f "$auto_discover_script" ]; then
         ├─ 파일 없음 → kvs_put "auto_discover_init" (failure)
         └─ 파일 있음 → else 블록
               └─ 라인 298: kvs_put "auto_discover_init" (starting)
               └─ 라인 305-375: 실행 및 중간 로깅

라인 381: kvs_put "auto_discover_complete" (✅ 항상 실행)
```

**문제점:**
- **라인 381이 `if-else` 블록 밖에 있음** ✅ (이건 정상)
- **라인 298-375가 `else` 블록 내에 있음** ⚠️ (조건부 실행)
  - 스크립트 파일이 없으면 중간 로깅이 모두 스킵됨
  - 하지만 완료 로깅만 실행되는 상황 발생

---

### 원인 2️⃣: **파일 경로 문제**

**두 가지 경로 시도:**
```bash
# 경로 1: 로컬 개발 환경
auto_discover_script="${SCRIPT_DIR}/giipscripts/auto-discover-linux.sh"

# 경로 2: 실제 서버
auto_discover_script="${SCRIPT_DIR}/lib/giipscripts/auto-discover-linux.sh"
```

**가능한 시나리오:**
1. 두 경로 모두 파일 없음 → `auto_discover_init` failure 로그 ✅ 기록됨
2. 파일 존재 → `auto_discover_init` starting 로그 ✅ 기록되어야 함 (하지만 KVS에 없음)

**현재 증상 분석:**
- ✅ `auto_discover_complete` 만 기록됨
- ❌ `auto_discover_init` 미기록
- → **파일이 존재하는데도 `kvs_put` 실패?**

---

### 원인 3️⃣: **kvs_put 함수 실패**

**kvs.sh에서 kvs_put 함수 (라인 161-200):**

```bash
kvs_put() {
    local ktype=$1
    local kkey=$2
    local kfactor=$3
    local kvalue_json=$4
    
    # 유효성 검사
    if [ -z "$sk" ] || [ -z "$apiaddrv2" ]; then
        echo "[KVS-Put] ⚠️  Missing required variables (sk, apiaddrv2)" >&2
        return 1  # ⚠️ 실패 반환
    fi
    
    # API 호출 (wget)
    wget -O "$response_file" \
        --post-data="text=...&token=...&jsondata=..." \
        "${kvs_url}" \
        --no-check-certificate \
        --server-response \
        -v 2>"$stderr_file"
    
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "[KVS-Put] ⚠️  Failed (exit_code=${exit_code}): ..." >&2
        # ⚠️ 실패해도 함수는 계속 진행
        # 하지만 반환값은 error
    fi
}
```

**kvs_put 실패 가능 원인:**
1. **필수 변수 없음**: `$sk` 또는 `$apiaddrv2` 미정의
   - giipAgent3.sh가 이 변수들을 로드했는지 확인 필요
2. **네트워크 오류**: wget이 API 호출 실패
3. **API 서버 문제**: giipApiSk2 응답 오류

---

### 원인 4️⃣: **stderr 리다이렉트 누락**

**giipAgent3.sh에서 kvs_put 호출:**

```bash
# 라인 303
kvs_put "lssn" "${lssn}" "auto_discover_init" "{...}"
kvs_put_result=$?
```

**문제점:**
```bash
# ✅ 올바른 호출 (디버그 로그 캡처)
kvs_put "..." 2>&1
kvs_result=$?

# ❌ 현재 방식
kvs_put "..."  # stderr 무시될 수 있음
kvs_result=$?
```

kvs_put 내부의 에러 로그가 stderr로 출력되는데, 
giipAgent3.sh에서 이를 캡처하지 않음 → **실패 원인을 알 수 없음**

---

## 4. 추가 로깅 요청 위치

### 4.1 현재 추가된 로깅

**giipAgent3.sh (라인 272-381):**
```
[5.2] auto-discover 섹션 진입 확인
[5.2.1] 스크립트 파일 존재 여부 확인
[5.2.2] 환경 정보 (LSSN, Hostname, OS, PID)
[5.2.3] 실행 시작 시간
[5.2.4] 실행 완료 또는 실패
[5.2.5] 실행 종료 시간
[5.2.6] 결과 파일 크기
[5.2.7] 결과 저장 (KVS)
[5.2.8] 전체 결과 저장 (KVS)
[5.2.9] 임시 파일 정리
[5.2.end] auto-discover 단계 완료 (KVS)
```

**auto-discover-linux.sh (라인 1-333):**
```
[START] 스크립트 시작 (PID, 시간)
[Parameters] 수신 파라미터 (LSSN, Hostname, OS)
[Step 1] OS 정보 수집
[Step 2] CPU 정보 수집
[Step 3] 메모리 정보 수집
[Step 4] Hostname 수집
[Step 5] 네트워크 수집
[Final] JSON 생성
[COMPLETED] 스크립트 완료 시간
```

### 4.2 **추가로 필요한 로깅** (KVS 저장 실패 원인 파악용)

#### A. kvs_put 호출 전/후 검증 로깅

**giipAgent3.sh 라인 298 수정:**
```bash
# 추가 로깅 #1: kvs_put 호출 전 변수 검증
echo "[giipAgent3.sh] 🔍 DEBUG: About to kvs_put auto_discover_init" >&2
echo "[giipAgent3.sh] 🔍 DEBUG: sk exists: $([ -z "$sk" ] && echo 'NO ❌' || echo 'YES ✅')" >&2
echo "[giipAgent3.sh] 🔍 DEBUG: apiaddrv2 exists: $([ -z "$apiaddrv2" ] && echo 'NO ❌' || echo 'YES ✅')" >&2
echo "[giipAgent3.sh] 🔍 DEBUG: apiaddrv2=$apiaddrv2" >&2

# 기존 코드
kvs_put "lssn" "${lssn}" "auto_discover_init" "{\"status\":\"starting\",\"script_path\":\"${auto_discover_script}\",\"lssn\":${lssn},\"hostname\":\"${hn}\"}" 2>&1 | tee -a /tmp/kvs_put_debug.log
kvs_put_result=$?

# 추가 로깅 #2: kvs_put 결과 검증
echo "[giipAgent3.sh] 🔍 DEBUG: kvs_put returned: $kvs_put_result (0=success, non-zero=failure)" >&2
if [ $kvs_put_result -ne 0 ]; then
    echo "[giipAgent3.sh] ❌ ERROR: kvs_put FAILED for auto_discover_init!" >&2
    echo "[giipAgent3.sh] 📋 Debug log from kvs_put:" >&2
    [ -f /tmp/kvs_put_debug.log ] && tail -20 /tmp/kvs_put_debug.log | sed 's/^/  [DEBUG] /'
fi
```

#### B. 조건부 분기 검증 로깅

**giipAgent3.sh 라인 290 수정:**
```bash
# 파일 존재 여부 상세 로깅
if [ ! -f "$auto_discover_script" ]; then
    echo "[giipAgent3.sh] ❌ BRANCH: auto-discover script NOT found" >&2
    echo "[giipAgent3.sh] 📋 Searched paths:" >&2
    echo "[giipAgent3.sh]   - Path 1: ${SCRIPT_DIR}/giipscripts/auto-discover-linux.sh" >&2
    echo "[giipAgent3.sh]   - Path 2: ${SCRIPT_DIR}/lib/giipscripts/auto-discover-linux.sh" >&2
    echo "[giipAgent3.sh]   - SCRIPT_DIR=$SCRIPT_DIR" >&2
    # ... failure 코드
else
    echo "[giipAgent3.sh] ✅ BRANCH: auto-discover script FOUND at $auto_discover_script" >&2
    # ... success 코드
fi
```

#### C. 환경 설정 로딩 검증

**giipAgent3.sh 시작 부분 (라인 1-50):**
```bash
# 추가 로깅: common.sh, kvs.sh 로드 확인
echo "[giipAgent3.sh] 🔍 DEBUG: Loading common.sh..." >&2
source "$lib_dir/common.sh" || { echo "FAILED to load common.sh"; exit 1; }
echo "[giipAgent3.sh] ✅ common.sh loaded" >&2

echo "[giipAgent3.sh] 🔍 DEBUG: Loading kvs.sh..." >&2
source "$lib_dir/kvs.sh" || { echo "FAILED to load kvs.sh"; exit 1; }
echo "[giipAgent3.sh] ✅ kvs.sh loaded" >&2

# LSvrGetConfig API 호출로 sk, apiaddrv2 확인
echo "[giipAgent3.sh] 🔍 DEBUG: Calling LSvrGetConfig to set api variables..." >&2
echo "[giipAgent3.sh] 🔍 DEBUG: After LSvrGetConfig:" >&2
echo "[giipAgent3.sh]   - sk=${sk:-(empty)}" >&2
echo "[giipAgent3.sh]   - apiaddrv2=${apiaddrv2:-(empty)}" >&2
```

---

## 5. 현재 KVS 저장 안 되는 이유 - 최종 진단

### 🔴 **주요 의심 원인 (우선순위 순)**

1. **`$sk` 또는 `$apiaddrv2` 변수 미설정**
   - LSvrGetConfig API 호출이 실패했거나
   - 결과를 올바르게 파싱하지 못함
   - **해결책**: 라인 50 확인 로깅으로 검증

2. **kvs_put 함수 내 wget 실패**
   - 네트워크 연결 문제
   - API 엔드포인트 오류
   - **해결책**: kvs.sh stderr 로그 캡처 (2>&1)

3. **조건부 실행 오류**
   - auto-discover 스크립트 경로 오류
   - SCRIPT_DIR 변수 오류
   - **해결책**: 라인 287 경로 검증 로깅

4. **kvs_put 호출 자체가 스킵됨**
   - if-else 로직 오류
   - 스크립트 문법 오류 (set -euo pipefail 때문)
   - **해결책**: 분기별 로깅 추가

---

## 6. 권장 조치

### ✅ 즉시 추가할 로깅

**파일**: `giipAgentLinux/giipAgent3.sh`

1. **라인 50 근처 (설정 로드 후)**
   ```bash
   echo "[giipAgent3.sh] 🔍 DEBUG: sk=${sk:-(empty)}, apiaddrv2=${apiaddrv2:-(empty)}" >&2
   ```

2. **라인 287 (파일 존재 확인 전)**
   ```bash
   echo "[giipAgent3.sh] 🔍 DEBUG: SCRIPT_DIR=$SCRIPT_DIR" >&2
   echo "[giipAgent3.sh] 🔍 DEBUG: Checking auto-discover script at: $auto_discover_script" >&2
   ```

3. **라인 298 (kvs_put 호출 전후)**
   ```bash
   echo "[giipAgent3.sh] 🔍 DEBUG: About to kvs_put auto_discover_init" >&2
   kvs_put "lssn" "${lssn}" "auto_discover_init" "{...}" 2>&1 | tee -a /tmp/kvs_put_debug.log
   echo "[giipAgent3.sh] 🔍 DEBUG: kvs_put returned: $?" >&2
   ```

### ✅ 검증 단계

1. **서버에서 giipAgent3.sh 실행**
   ```bash
   bash /path/to/giipAgent3.sh 2>&1 | tee /tmp/giipAgent3_debug.log
   ```

2. **디버그 로그 확인**
   ```bash
   grep "DEBUG" /tmp/giipAgent3_debug.log
   cat /tmp/kvs_put_debug.log
   ```

3. **KVS 조회**
   ```powershell
   pwsh .\mgmt\check-latest.ps1 -Lssn 71240
   ```

---

## 📌 요약

| 항목 | 현상 | 원인 | 해결책 |
|------|------|------|--------|
| **auto_discover_complete** | ✅ 기록됨 | 라인 381 항상 실행 | N/A |
| **auto_discover_init** | ❌ 없음 | kvs_put 실패 또는 호출 안 됨 | 라인 298 디버그 로깅 |
| **auto_discover_result** | ❌ 없음 | else 블록 미진입 또는 결과 파일 없음 | 라인 290 분기 로깅 |
| **auto_discover_error_log** | ❌ 없음 | auto-discover 실패 또는 로깅 미실행 | auto-discover-linux.sh 검증 |

---

## 🔗 관련 문서

- [AUTO_DISCOVER_LOGGING_ENHANCED.md](AUTO_DISCOVER_LOGGING_ENHANCED.md) - 로깅 구현
- [AUTO_DISCOVER_LOGGING_DIAGNOSIS.md](AUTO_DISCOVER_LOGGING_DIAGNOSIS.md) - 진단 방법
- [KVS_STORAGE_STANDARD.md](KVS_STORAGE_STANDARD.md) - KVS 저장 표준
- [giipAgent3.sh](../../giipAgentLinux/giipAgent3.sh) - 실제 코드 (라인 272-381)

