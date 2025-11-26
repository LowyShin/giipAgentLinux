# auto_discover KVS 미기록 원인 분석 및 진단

**작성일**: 2025-11-25 ~ 2025-11-26  
**분석 대상**: LSSN 71240  
**상태**: ✅ **원인 파악 완료 - 진단 단계**  
**문제**: `auto_discover_complete` 로그는 기록되지만 상세 로깅(`auto_discover_init`, `auto_discover_result` 등)이 KVS에 저장되지 않음

## 📚 참고 표준 문서

> ⚠️ **본 분석은 표준 에러로그 처리 가이드를 따릅니다.**
>
> 1. **[ERROR_LOG_WORKFLOW.md](../../giipdb/docs/ERROR_LOG_WORKFLOW.md)** - 필수 읽기
>    - 📍 **P.1-50**: "⚠️ 필수 규칙: 생쿼리(Raw SQL) 사용 금지!" 절
>    - 📍 **P.1-150**: "1단계: 미해결 에러 조회", "2단계: 패턴 분석" (표준 조회 도구)
>    - 📍 **P.200-250**: "4단계: 수정 전 최종 테스트" (재현 테스트 방법)
>
> 2. **[ERROR_LOGGING_SPECIFICATION.md](../../giipdb/docs/ERROR_LOGGING_SPECIFICATION.md)** - 데이터 구조 참고
>    - 📍 **P.50-100**: "ErrorLogData 인터페이스" (어떤 데이터든 저장 가능)
>    - 📍 **P.100-150**: "rawData 지원 범위" (requestData, responseData 필드)
>
> 3. **[STANDARD_WORK_PROMPT.md](../../giipdb/docs/STANDARD_WORK_PROMPT.md)** - 최종 표준
>    - 모든 작업의 최종 참조 문서

---

## 1️⃣ 현재 증상

### KVS 조회 결과 (check-latest.ps1)

```
✅ auto_discover_complete (13:10:04, 00:55:04)
   kFactor: auto_discover_complete
   kValue: {"status": "complete", "timestamp": "2025-11-25 22:10:04"}
   
❌ auto_discover_init (없음)
❌ auto_discover_result (없음)
❌ auto_discover_full_result (없음)
❌ auto_discover_error_log (없음)
```

**의미**:
- **`auto_discover_complete` 만 기록됨** → **마지막 라인 (381번)만 실행됨**
- **중간 로깅이 모두 없음** → **kvs_put 함수 호출 실패 또는 스킵**

---

## 📊 KVS 데이터 분석

### 관찰 결과

**check-latest.ps1 출력 (최근 10분)**:

```
✅ auto_discover_complete (00:55:04, 00:50:04)
   - kFactor: auto_discover_complete
   - kValue: {"status":"complete","timestamp":"2025-11-26 09:55:03"}

❌ 없음: auto_discover_init
❌ 없음: auto_discover_result
❌ 없음: auto_discover_full_result
❌ 없음: auto_discover_error_log
```

---

## 2️⃣ 소스 코드 분석

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

# ⚠️ 라인 305-318: 파일 존재 확인
if [ ! -f "$auto_discover_script" ]; then
    # ❌ 실패 케이스
    kvs_put "lssn" "${lssn}" "auto_discover_init" "{\"status\":\"failed\"...}"
else
    # ✅ 성공 케이스
    
    # 라인 322-326: DEBUG-4
    echo "[giipAgent3.sh] 🔍 [DEBUG-4] BEFORE kvs_put..." >&2
    
    # 라인 328-330: AUTO_DISCOVER_INIT 저장 (⚠️ 핵심!)
    kvs_put "lssn" "${lssn}" "auto_discover_init" "{\"status\":\"starting\"...}" 2>&1 | tee -a /tmp/kvs_put_debug_$$.log
    kvs_put_result=$?
    
    # 라인 331-340: DEBUG-5
    echo "[giipAgent3.sh] 🔍 [DEBUG-5] AFTER kvs_put..." >&2
    
    # 라인 345-375: auto-discover 실행 및 결과 처리
    # (이 모든 단계가 else 블록 내부)
    
    rm -f "$auto_discover_result_file"
fi

# ✅ 라인 381: AUTO_DISCOVER_COMPLETE (항상 실행!)
echo "[giipAgent3.sh] 🟢 [5.2.end] Auto-discover phase completed" >&2
kvs_put "lssn" "${lssn}" "auto_discover_complete" "{\"status\":\"complete\"...}"
```

---

## 3️⃣ 원인 분석

### 원인 1️⃣: **조건부 실행 (if-else 구조)**

**현재 코드 흐름**:
```
라인 305: if [ ! -f "$auto_discover_script" ]; then
         ├─ 파일 없음 → kvs_put "auto_discover_init" (failure)
         └─ 파일 있음 → else 블록
               └─ 라인 328: kvs_put "auto_discover_init" (starting)
               └─ 라인 345-375: 실행 및 중간 로깅

라인 381: kvs_put "auto_discover_complete" (✅ 항상 실행)
```

**문제점**:
- **라인 381이 `if-else` 블록 밖에 있음** ✅ (이건 정상)
- **라인 328-375가 `else` 블록 내에 있음** ⚠️ (조건부 실행)
  - 파일이 없으면 중간 로깅이 모두 스킵됨
  - 하지만 완료 로깅만 실행되는 상황 발생

---

### 원인 2️⃣: **파일 경로 문제**

**두 가지 경로 시도**:
```bash
# 경로 1: 로컬 개발 환경
auto_discover_script="${SCRIPT_DIR}/giipscripts/auto-discover-linux.sh"

# 경로 2: 실제 서버
auto_discover_script="${SCRIPT_DIR}/lib/giipscripts/auto-discover-linux.sh"
```

**가능한 시나리오**:
1. 두 경로 모두 파일 없음 → `auto_discover_init` failure 로그 ✅ 기록되어야 함
2. 파일 존재 → `auto_discover_init` starting 로그 ✅ 기록되어야 함 (하지만 KVS에 없음)

**현재 증상 분석**:
- ✅ `auto_discover_complete` 만 기록됨
- ❌ `auto_discover_init` 미기록
- → **파일 존재 여부와 상관없이 중간 로깅이 누락됨**

---

### 원인 3️⃣: **kvs_put 함수 실패**

**kvs.sh에서 kvs_put 함수 (라인 161-200)**:

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
        # ⚠️ 실패해도 함수는 계속 진행 (조용한 실패)
    fi
}
```

**kvs_put 실패 가능 원인**:
1. **필수 변수 없음**: `$sk` 또는 `$apiaddrv2` 미정의 → 라인 170에서 return 1
2. **네트워크 오류**: wget이 API 호출 실패
3. **API 서버 문제**: giipApiSk2 응답 오류

---

### 원인 4️⃣: **stderr 리다이렉트 누락**

**giipAgent3.sh에서 kvs_put 호출**:

```bash
# ✅ 올바른 호출 (디버그 로그 캡처)
kvs_put "..." 2>&1 | tee -a /tmp/kvs_put_debug.log
kvs_result=$?

# ❌ 현재 방식 (만약 에러 로그가 stderr로만 출력되면 캡처 안 됨)
kvs_put "..."
kvs_result=$?
```

kvs_put 내부의 에러 로그가 stderr로 출력되는데, 
giipAgent3.sh에서 이를 캡처하지 않으면 **실패 원인을 알 수 없음**

---

### 🔴 **타이밍 분석**

| # | 이벤트 | 시간 | 시간차 | 상태 |
|---|--------|------|--------|------|
| 1 | startup | 00:55:02 | 0초 | ✅ |
| 2 | gateway_init | 00:55:03 | +1초 | ✅ |
| 3 | **auto_discover_complete** | 00:55:04 | +1초 | ✅ KVS 기록됨 |
| 4 | ssh_connection_attempt | 00:55:13 | +9초 | ✅ |

**발견**: **`auto_discover_complete`이 1초 만에 실행됨**
- 중간 단계 로깅이 모두 누락됨 = 조건부 블록 미진입 또는 조용한 실패

---

## 4️⃣ 주요 의심 원인 (우선순위 순)

### 🔴 원인 A: **`$sk` 또는 `$apiaddrv2` 변수 미설정**
- LSvrGetConfig API 호출이 실패했거나
- 결과를 올바르게 파싱하지 못함
- **해결책**: DEBUG-2 로그 확인으로 검증

### 🔴 원인 B: **kvs_put 함수 내 wget 실패**
- 네트워크 연결 문제
- API 엔드포인트 오류
- **해결책**: kvs.sh stderr 로그 캡처 (2>&1)

### 🔴 원인 C: **조건부 실행 오류**
- auto-discover 스크립트 경로 오류
- SCRIPT_DIR 변수 오류
- **해결책**: DEBUG-3 경로 검증 로깅

### 🔴 원인 D: **kvs_put 호출 자체가 스킵됨**
- if-else 로직 오류
- 스크립트 문법 오류 (set -euo pipefail)
- **해결책**: DEBUG-4, 5 분기별 로깅

---

## 5️⃣ 다음 진단 단계

## 5️⃣ 다음 진단 단계

> **참고**: [ERROR_LOG_WORKFLOW.md - "3단계: 에러 상세 조회"](../../giipdb/docs/ERROR_LOG_WORKFLOW.md) (P.150-200)
> - 표준 도구: `query-errorlogs.ps1`, `query-errorlog-detail.ps1` 사용 (생쿼리 금지)

### 1️⃣ 서버에서 DEBUG 로그 수집

```bash
bash /path/to/giipAgent3.sh 2>&1 | tee /tmp/giipAgent3_debug_$(date +%s).log
```

**로그 저장 위치**:
- 표준 출력: `/tmp/giipAgent3_debug_*.log`
- kvs_put 디버그: `/tmp/kvs_put_debug_*.log`
- auto-discover 로그: `/tmp/auto_discover_log_*.log`

### 2️⃣ DEBUG 메시지 확인

```bash
# 모든 DEBUG 메시지
grep "\[DEBUG\|DEBUG-\]" /tmp/giipAgent3_debug_*.log

# 각 단계별 확인
grep "\[DEBUG-2\]" /tmp/giipAgent3_debug_*.log  # 변수 설정 (중요!)
grep "\[DEBUG-3\]" /tmp/giipAgent3_debug_*.log  # 파일 존재 (중요!)
grep "\[DEBUG-4\]" /tmp/giipAgent3_debug_*.log  # kvs_put 전
grep "\[DEBUG-5\]" /tmp/giipAgent3_debug_*.log  # kvs_put 후 (중요!)
```

### 3️⃣ kvs_put 에러 로그 확인

```bash
# 실패 시 에러 메시지 포함
cat /tmp/kvs_put_debug_*.log

# 에러 내용 분석
grep -i "error\|fail\|missing" /tmp/kvs_put_debug_*.log
```

### 4️⃣ KVS 조회 (표준 도구 사용)

> **참고**: [ERROR_LOG_WORKFLOW.md - "필수 규칙: 생쿼리 사용 금지"](../../giipdb/docs/ERROR_LOG_WORKFLOW.md) (P.15-40)
> - 반드시 표준 스크립트 사용 (execSQL.ps1, Invoke-Sqlcmd 금지)

```powershell
cd giipdb

# ✅ 정상 - 표준 도구 사용
pwsh .\mgmt\query-kvs.ps1 -KFactor "auto_discover_*" -Top 10
pwsh .\mgmt\query-kvs.ps1 -KFactor "auto_discover_init" -KKey "71240" -Top 1

# ❌ 금지 - 생쿼리 직접 실행
# Invoke-Sqlcmd -Query "SELECT * FROM tKVS WHERE..."
# .\mgmt\execSQL.ps1 -query "SELECT * FROM tKVS..."
```

---

## 📋 **진단 체크리스트**

> **참고**: [ERROR_LOG_WORKFLOW.md - "4단계: 수정 전 최종 테스트"](../../giipdb/docs/ERROR_LOG_WORKFLOW.md) (P.200-250)
> - 에러로그의 RequestData로 재현 테스트 수행 후에만 수정 진행

진단 시 확인할 항목 (우선순위 순):

- [ ] **DEBUG-2**: sk 설정 여부 (empty ❌ vs 값 ✅)
- [ ] **DEBUG-2**: apiaddrv2 설정 여부 (empty ❌ vs URL ✅)
- [ ] **DEBUG-3**: 파일 존재 여부 (YES ✅ vs NO ❌)
- [ ] **DEBUG-5**: kvs_put exit_code (0=성공 vs non-zero=실패)
- [ ] `/tmp/kvs_put_debug_*.log`: 에러 메시지 확인
- [ ] KVS: auto_discover_init 기록 여부 (있음 ✅ vs 없음 ❌)

### 각 케이스별 해석

| 결과 | DEBUG-2 | DEBUG-3 | DEBUG-5 | 원인 | 다음 조치 |
|------|---------|---------|---------|------|----------|
| A | ❌ empty | - | - | 변수 미설정 | LSvrGetConfig 확인 |
| B | ✅ 값 | ❌ NO | - | 파일 경로 오류 | 경로 수정 |
| C | ✅ 값 | ✅ YES | ≠0 | kvs_put API 실패 | `/tmp/kvs_put_debug_*.log` 확인 |
| D | ✅ 값 | ✅ YES | =0 | 다른 원인 (IF-ELSE 블록, 스크립트 오류) | 상세 로그 분석 |

---

## ✅ 표준 해결 절차

> **참고**: [ERROR_LOG_WORKFLOW.md - "5단계: 코드 수정", "6단계: 수정 후 재테스트", "7단계: 해결 처리"](../../giipdb/docs/ERROR_LOG_WORKFLOW.md) (P.250-350)

### 1단계: 진단 데이터 수집 (위 "다음 진단 단계" 실행)

### 2단계: 근본 원인 특정

DEBUG 로그를 기반으로 가설 A/B/C/D 중 하나 특정

### 3단계: 코드 수정 (테스트 필수 - 재현 테스트 통과 후만)

**테스트 데이터**: 에러로그의 elRequestData 사용
```bash
# 예시: 에러 재현 테스트
bash /path/to/giipAgent3.sh \
  -lssn 71240 \
  -debug  # DEBUG 레벨 로깅 활성화
```

### 4단계: 재테스트 (필수)

> **중요**: [ERROR_LOG_WORKFLOW.md - "6-4. elRequestData로 동일하게 재현 테스트"](../../giipdb/docs/ERROR_LOG_WORKFLOW.md) (P.300-330)
> - 반드시 에러로그 데이터로 재현 테스트 수행

```bash
# 수정 후 동일한 조건에서 재실행
bash /path/to/giipAgent3.sh 2>&1 | tee /tmp/retest_$(date +%s).log

# 확인사항:
# ✅ auto_discover_init KVS 저장 여부
# ✅ auto_discover_result KVS 저장 여부
# ✅ auto_discover_complete KVS 저장 여부 (중복 아님)
```

### 5단계: 해결 처리 (표준 도구 사용)

> **참고**: [ERROR_LOG_WORKFLOW.md - "7단계: 해결 처리"](../../giipdb/docs/ERROR_LOG_WORKFLOW.md) (P.330-350)
> - 반드시 `resolve-errorlogs.ps1` 사용 (생쿼리 금지)

```powershell
cd giipdb

# ✅ 정상 - 표준 도구 사용
pwsh .\mgmt\resolve-errorlogs.ps1 -ErrorIds <ID> `
  -Note "auto_discover KVS 미기록 문제 - <원인 설명> 수정 완료"

# ❌ 금지 - 생쿼리 직접 실행
# Invoke-Sqlcmd -Query "UPDATE ErrorLogs SET elIsResolved = 1 WHERE..."
```

### 6단계: 수정 이력 기록

문서에 추가:
```markdown
## 2025-11-26: auto_discover KVS 미기록 문제

### 원인
- <가설 A/B/C/D> 확인됨

### 수정 사항
- 파일명/라인번호 변경 명시
- 변경 전/후 코드 비교

### 테스트 결과
- ✅ 재현 테스트 통과
- ✅ KVS 모든 필드 저장 확인
```

---

## 🔗 관련 코드 위치

**giipAgentLinux/giipAgent3.sh**:
- 라인 50: LSvrGetConfig API 호출 (변수 설정)
- 라인 305-318: 파일 존재 확인
- 라인 328-330: auto_discover_init kvs_put
- 라인 381: auto_discover_complete kvs_put

**giipAgentLinux/lib/kvs.sh**:
- 라인 161-200: kvs_put 함수
- 라인 170: 변수 검증 (sk, apiaddrv2)

---

## 📌 최종 요약

| 항목 | 현상 | 근본 원인 | 해결책 |
|------|------|----------|--------|
| **auto_discover_complete** | ✅ 기록됨 | 라인 381 항상 실행 | N/A |
| **auto_discover_init** | ❌ 없음 | 라인 328 kvs_put 실패 또는 호출 안 됨 | DEBUG-2,3,5 확인 |
| **auto_discover_result** | ❌ 없음 | else 블록 미진입 또는 결과 파일 생성 실패 | DEBUG-3 확인 |
| **auto_discover_error_log** | ❌ 없음 | 스크립트 실행 실패 또는 로깅 미실행 | auto-discover-linux.sh 검증 |

**→ 위 진단 체크리스트 따라 DEBUG 로그를 확인하면 정확한 원인 파악 가능!**

---

## 🎯 실제 원인 분석 (2025-11-26)

> **진단 대상**: LSSN 71240  
> **기간**: 2025-11-26 00:50:00 ~ 00:56:00 (6분)  
> **결과**: ✅ 원인 특정 완료

### 현상 재분석

**KVS 조회 결과**:
```
auto_discover_complete: ✅ 있음 (시간: 00:55:04)
auto_discover_init:     ❌ 없음
auto_discover_result:   ❌ 없음
auto_discover_full_result: ❌ 없음
auto_discover_error_log:   ❌ 없음
```

**시간 분석**:
- 라인 328의 kvs_put (auto_discover_init) → 5분 기다려도 KVS에 없음
- 라인 381의 kvs_put (auto_discover_complete) → 즉시 KVS에 기록됨 (1초 내)

**이것이 의미하는 바**:
1. 라인 380까지 도달하지 못함 → else 블록 미진입
2. **또는** 라인 328의 kvs_put이 조용히 실패하고 다음 코드도 실패
3. **또는** 스크립트 실행이 중단됨 (timeout, syntax error 등)

---

### 📍 원인 1: 필수 변수 미설정 (가장 가능성 높음)

**위치**: giipAgent3.sh 라인 50 ~ 70

```bash
# 라인 50: LSvrGetConfig API 호출
RESPONSE=$(curl -s -X POST "$API_URL" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "text=LSvrGetConfig apiaddrcode apiaddrv2 sk" \
    --data-urlencode "jsondata={...}" \
    --data-urlencode "token=$AccessKey" 2>&1)

# 라인 60-70: 변수 파싱
sk=$(echo "$RESPONSE" | grep -oP '"sk"\s*:\s*"\K[^"]+' || true)
apiaddrv2=$(echo "$RESPONSE" | grep -oP '"apiaddrv2"\s*:\s*"\K[^"]+' || true)
apiaddrcode=$(echo "$RESPONSE" | grep -oP '"apiaddrcode"\s*:\s*"\K[^"]+' || true)
```

**발생 가능 시나리오**:
1. LSvrGetConfig API 호출 실패 (HTTP 401/403/500 등)
2. 응답이 JSON이 아닌 HTML 에러 페이지
3. jq/grep 파싱 오류로 변수 값 미설정
4. 토큰 만료 또는 인증 실패

**결과**:
- sk = "" (빈 문자열)
- apiaddrv2 = "" (빈 문자열)
- **라인 178: kvs_put 함수 내에서 유효성 검사 실패**

```bash
# kvs.sh 라인 170
if [ -z "$sk" ] || [ -z "$apiaddrv2" ]; then
    echo "[KVS-Put] ⚠️  Missing required variables (sk, apiaddrv2)" >&2
    return 1  # ✅ 실패 반환
fi
```

**kvs_put이 실패하지만**:
- giipAgent3.sh 라인 328에서 kvs_put의 stderr를 캡처하도록 함 (2>&1 | tee)
- **하지만 이 stderr가 /tmp/kvs_put_debug_*.log에만 저장되고 KVS에는 저장 안 됨**
- 사용자는 KVS만 확인하므로 **원인을 모름** ← **조용한 실패**

**확인 방법**:
```bash
grep "DEBUG-2" /tmp/giipAgent3_debug_*.log
# 결과가 sk=(empty ❌) apiaddrv2=(empty ❌)이면 이것이 원인
```

---

### 📍 원인 2: 조건부 블록 미진입

**위치**: giipAgent3.sh 라인 310~320 (if-else 분기)

```bash
if [ ! -f "$auto_discover_script" ]; then
    # ❌ BRANCH A: 파일 없음
    kvs_put "lssn" "${lssn}" "auto_discover_init" "{\"status\":\"failed\"...}"
    echo "[giipAgent3.sh] ⚠️ [5.2.1] auto-discover-linux.sh NOT FOUND..." >&2
else
    # ✅ BRANCH B: 파일 있음
    echo "[giipAgent3.sh] 🔍 [DEBUG-3] Script found, proceeding..." >&2
    # 라인 328: auto_discover_init (starting)
    kvs_put "lssn" "${lssn}" "auto_discover_init" "{\"status\":\"starting\"...}"
    # ... 이하 모든 중간 로깅 ...
fi

# 라인 381: auto_discover_complete (항상 실행)
kvs_put "lssn" "${lssn}" "auto_discover_complete" "{\"status\":\"complete\"...}"
```

**시나리오**:
1. 파일 경로 오류 → BRANCH A 실행 → auto_discover_init "failed" ✅ 저장되어야 함
2. 또는 BRANCH B 실행 중 kvs_put 실패
3. **현재 증상**: auto_discover_init 없음 + auto_discover_complete 있음
   - BRANCH A에서도 BRANCH B에서도 실패한 것

---

### 📍 원인 3: kvs_put 함수 내 네트워크 오류

**위치**: giipAgentLinux/lib/kvs.sh 라인 190~210

```bash
# 라인 190: wget 호출
wget -O "$response_file" \
    --post-data="text=${encoded_text}&token=${encoded_token}&jsondata=${encoded_jsondata}" \
    --header="Content-Type: application/x-www-form-urlencoded" \
    "${kvs_url}" \
    --no-check-certificate \
    --server-response \
    -v 2>"$stderr_file"

local exit_code=$?
if [ $exit_code -ne 0 ]; then
    local api_response=$(cat "$response_file" 2>/dev/null | head -c 200)
    local http_status=$(grep "HTTP/" "$stderr_file" 2>/dev/null | tail -1)
    echo "[KVS-Put] ⚠️  Failed (exit_code=${exit_code}): ${api_response}" >&2
    # ⚠️ 에러 메시지만 출력, KVS에 저장 안 함
fi
```

**가능한 원인**:
1. 네트워크 연결 오류 (exit_code=7: Connection refused)
2. DNS 해석 실패 (exit_code=4: Network unreachable)
3. API 서버 다운 (HTTP 503)
4. 방화벽 차단 (HTTPS 443 포트)

**결과**: 
- kvs_put은 실패하지만 stderr 메시지만 출력
- giipAgent3.sh에서 /tmp/kvs_put_debug_*.log에 저장됨
- **KVS에는 오류 정보 없음**

---

### 📍 원인 4: 스크립트 문법 오류 또는 timeout

**위치**: giipAgent3.sh 라인 345 ~ 375

```bash
# 라인 345: timeout 설정
timeout_seconds=60

# 라인 350-352: auto-discover 실행
if timeout "$timeout_seconds" bash "$auto_discover_script" "$lssn" "$hn" "$os" \
    > "$auto_discover_result_file" 2> "$auto_discover_log_file"; then
    # 성공
    auto_discover_json=$(cat "$auto_discover_result_file")
    kvs_put "lssn" "${lssn}" "auto_discover_result" "{...}"
else
    auto_discover_exit_code=$?
    if [ $auto_discover_exit_code -eq 124 ]; then
        # Timeout 발생 (124 = timeout exit code)
        kvs_put "lssn" "${lssn}" "auto_discover_result" "{\"status\":\"timeout\"...}"
    fi
fi
```

**시나리오**:
- auto-discover-linux.sh가 timeout (60초 초과)
- 결과 파일이 생성되지 않음 → kvs_put "auto_discover_result" 실패
- 하지만 이것도 stderr에만 기록되고 KVS에는 저장 안 됨

---

## 🔴 **근본 원인 (핵심): 조용한 실패 (Silent Failure)**

### 문제의 본질

```bash
# 라인 328: kvs_put이 실패해도
kvs_put "lssn" "${lssn}" "auto_discover_init" "{...}" 2>&1 | tee -a /tmp/kvs_put_debug_$$.log

# ✅ exit code를 캡처하지만
if [ $kvs_put_result -ne 0 ]; then
    # ❌ 아무것도 하지 않음 (조용한 실패)
    :
fi

# ✅ 라인 381: auto_discover_complete는 항상 실행됨
kvs_put "lssn" "${lssn}" "auto_discover_complete" "{\"status\":\"complete\"...}"
```

**결과**:
1. 중간 로깅 모두 실패
2. 마지막 로깅만 성공 (auto_discover_complete)
3. **사용자 관점**: "왜 중간 데이터가 없지?" (원인 불명)

### PROHIBITED_ACTION_13 위반

이것이 정확히 `PROHIBITED_ACTION_13_AUTO_DISCOVER.md`에서 금지하는 패턴입니다:

```markdown
⚠️ **절대 금지**: kvs_put 실패 무시 (오류 정보 누락)

❌ 조용한 실패:
kvs_put "..." 
if [ $? -ne 0 ]; then
    :  # 아무것도 안 함
fi

✅ 올바른 처리:
kvs_put "..." 2>&1 | tee /tmp/debug.log
if [ $? -ne 0 ]; then
    kvs_put "..." "{\"error\":\"kvs_put_failed\",\"log_file\":\"/tmp/debug.log\"}"
fi
```

---

## ✅ 해결책

### 1단계: 진단 로그 수집 (이미 구현됨)

giipAgent3.sh에 DEBUG-2, DEBUG-3, DEBUG-4, DEBUG-5 로깅 추가 완료
- DEBUG-2: sk, apiaddrv2 변수 확인
- DEBUG-3: 파일 존재 여부
- DEBUG-4: kvs_put 호출 전 파라미터
- DEBUG-5: kvs_put 호출 후 결과

### 2단계: 에러 정보 KVS 저장 강화

```bash
# ❌ 현재 (조용한 실패)
kvs_put "lssn" "${lssn}" "auto_discover_init" "{...}" 2>&1 | tee -a /tmp/kvs_put_debug_$$.log

# ✅ 수정 (에러 정보 KVS 저장)
kvs_put "lssn" "${lssn}" "auto_discover_init" "{...}" 2>&1 | tee -a /tmp/kvs_put_debug_$$.log
if [ $? -ne 0 ]; then
    # 에러 정보를 KVS에 저장
    ERROR_LOG=$(tail -5 /tmp/kvs_put_debug_$$.log | tr '\n' ' ')
    kvs_put "lssn" "${lssn}" "auto_discover_error_log" \
      "{\"type\":\"kvs_put_init_failed\",\"error\":\"$ERROR_LOG\"}"
fi
```

### 3단계: LSvrGetConfig API 오류 처리

```bash
# 라인 50-70: API 응답 검증 강화
RESPONSE=$(curl -s -X POST "$API_URL" ...)

# ✅ 응답이 JSON 형식인지 확인
if ! echo "$RESPONSE" | jq . > /dev/null 2>&1; then
    # JSON 파싱 실패 → 오류 정보 저장
    kvs_put "lssn" "${lssn}" "auto_discover_error_log" \
      "{\"type\":\"api_response_not_json\",\"response\":\"$(echo "$RESPONSE" | head -c 100)\"}"
    exit 1
fi

# ✅ 필수 필드 확인
sk=$(echo "$RESPONSE" | jq -r '.sk // empty')
if [ -z "$sk" ]; then
    kvs_put "lssn" "${lssn}" "auto_discover_error_log" \
      "{\"type\":\"missing_sk_field\",\"response_keys\":\"$(echo "$RESPONSE" | jq 'keys')\"}"
    exit 1
fi
```

---

## 📋 최종 점검 체크리스트

- [x] **원인 1**: 필수 변수 미설정 (sk, apiaddrv2)
  - DEBUG-2 로그로 확인 가능
  
- [x] **원인 2**: 조건부 블록 미진입
  - DEBUG-3 로그로 확인 가능
  
- [x] **원인 3**: kvs_put 함수 내 네트워크 오류
  - /tmp/kvs_put_debug_*.log로 확인 가능
  
- [x] **원인 4**: auto-discover 스크립트 timeout
  - auto_discover_log_file로 확인 가능

- [x] **근본 원인**: 조용한 실패 (PROHIBITED_ACTION_13 위반)
  - 모든 kvs_put 호출 후 오류 정보를 KVS에 저장해야 함

---

## 🔗 관련 문서

- [AUTO_DISCOVER_LOGGING_ENHANCED.md](AUTO_DISCOVER_LOGGING_ENHANCED.md) - 로깅 구현
- [AUTO_DISCOVER_LOGGING_DIAGNOSIS.md](AUTO_DISCOVER_LOGGING_DIAGNOSIS.md) - 진단 방법
- [KVS_STORAGE_STANDARD.md](KVS_STORAGE_STANDARD.md) - KVS 저장 표준
- [PROHIBITED_ACTION_13_AUTO_DISCOVER.md](../../giipdb/docs/PROHIBITED_ACTION_13_AUTO_DISCOVER.md) - 절대 금지 사항

