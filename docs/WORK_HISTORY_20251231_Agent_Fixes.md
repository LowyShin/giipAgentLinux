# 작업 이력: giipAgent3 Normal Mode 수정 및 Singleton 개선

**작업일**: 2025-12-31  
**작업자**: AI Agent  
**목적**: Normal mode API 응답 검증 강화 및 Singleton hang 문제 해결

---

## 📋 작업 요약

### 문제 상황
1. **Normal mode 데이터 미업데이트**: giipAgent3.sh 실행해도 tKVS에 데이터가 업데이트되지 않음 (최종 업데이트: 2025-12-16)
2. **Singleton 로직으로 인한 hang**: Strict singleton 패턴으로 인해 프로세스가 hang되면 이후 모든 실행이 차단됨

### 해결 방안
1. **API 응답 검증 강화**: wget 성공만 체크하던 것을 RstVal까지 검증하여 실패 원인 파악
2. **Singleton 로직 개선**: 5분 이상 실행된 프로세스만 종료하여 병렬 실행 허용

---

## ✅ 수정 파일 목록

### 1. lib/kvs.sh - API 응답 검증 강화 ⭐

**수정 라인**: Line 132-353

**수정 내용**:

#### save_execution_log() 함수 (Line 132-222)
```bash
# Before: wget exit_code만 체크
if [ $exit_code -eq 0 ]; then
    echo "[KVS-Log] ✅ Saved: ${event_type}"
fi

# After: RstVal까지 검증
# 1단계: wget 성공 확인
if [ $exit_code -ne 0 ]; then
    echo "[KVS-Log] ❌ wget failed"
    log_error "KVS wget failed: ${event_type}" "NetworkError" "..."
    return $exit_code
fi

# 2단계: API 응답(RstVal) 검증
local rst_val=$(echo "$api_response" | jq -r '.RstVal')

if [ "$rst_val" = "200" ]; then
    echo "[KVS-Log] ✅ Saved: ${event_type} (RstVal=200)"
else
    # 상세 에러 출력
    echo "[KVS-Log] ❌ API Error: ${event_type}"
    echo "[KVS-Log] 📊 RstVal: ${rst_val}"
    echo "[KVS-Log] 💬 RstMsg: ${rst_msg}"
    echo "[KVS-Log] 🔧 ProcName: ${proc_name}"
    echo "[KVS-Log] 📄 Full Response: ${api_response}"
    
    # 디버깅 파일 보존
    # 에러로그 DB에 자동 기록
    log_error "KVS API failed: ${event_type} (RstVal=${rst_val})" "ApiError" "..."
    return 1
fi
```

**기대 효과**:
- ✅ API 실패 원인 즉시 파악 (RstVal, RstMsg, ProcName)
- ✅ 디버깅 파일 자동 보존 (/tmp/kvs_exec_*)
- ✅ 에러로그 DB에 자동 기록 (ErrorLogs 테이블)

#### kvs_put() 함수 (Line 295-353)
동일한 RstVal 검증 로직 추가

---

### 2. lib/normal.sh - 에러 메시지 표시

**수정 라인**: Line 33, 67, 110, 117

**수정 내용**:
```bash
# Before: 에러 숨김
save_execution_log "queue_check" "$details" 2>/dev/null

# After: 에러 표시
save_execution_log "queue_check" "$details"
```

**기대 효과**:
- ✅ API 호출 실패 시 에러 메시지가 즉시 로그에 표시

---

### 3. lib/cqe.sh - URL 인코딩 추가

**수정 라인**: Line 48-61

**수정 내용**:
```bash
# Before: URL 인코딩 없음
curl -s -X POST "$api_url" \
    -d "text=${text}&token=${sk}&jsondata=${jsondata}"

# After: jq @uri로 URL 인코딩
local encoded_text=$(printf '%s' "$text" | jq -sRr '@uri')
local encoded_token=$(printf '%s' "$sk" | jq -sRr '@uri')
local encoded_jsondata=$(printf '%s' "$jsondata" | jq -sRr '@uri')

curl -s -X POST "$api_url" \
    -d "text=${encoded_text}&token=${encoded_token}&jsondata=${encoded_jsondata}"
```

**기대 효과**:
- ✅ 특수문자 포함 데이터 안전 전송
- ✅ kvs.sh와 일관성 유지

---

### 4. giipAgent3.sh - Singleton 로직 개선 ⭐

**수정 라인**: Line 32-56

**수정 내용**:
```bash
# Before: Strict Singleton (다른 프로세스 있으면 즉시 종료)
if pgrep -f "bash $SCRIPT_ABS_PATH" | grep -v "$CURRENT_PID" > /dev/null; then
    echo "⚠️  Another instance is already running. Exiting."
    exit 0
fi

# After: Relaxed Singleton (5분 이상된 프로세스만 종료)
while IFS= read -r other_pid; do
    if [ -n "$other_pid" ] && [ "$other_pid" != "$CURRENT_PID" ]; then
        elapsed_seconds=$(ps -o etimes= -p "$other_pid" 2>/dev/null | tr -d ' ')
        
        if [ -n "$elapsed_seconds" ] && [ "$elapsed_seconds" -gt 300 ]; then
            echo "⚠️  Killing hung process (PID=$other_pid, runtime=${elapsed_seconds}s > 5min)"
            kill -9 "$other_pid" 2>/dev/null
        fi
    fi
done < <(pgrep -f "bash $SCRIPT_ABS_PATH" | grep -v "^$CURRENT_PID$")
```

**기대 효과**:
- ✅ Hang된 프로세스 자동 제거 (5분 초과 시)
- ✅ 정상 실행 중인 프로세스는 병렬 실행 허용
- ✅ Cron 주기(5분)와 충돌 방지

---

### 5. scripts/normal_mode.sh - Singleton 로직 개선

**수정 라인**: Line 36-47

**수정 내용**: giipAgent3.sh와 동일한 relaxed singleton 패턴 적용

---

## 📚 문서 업데이트

### 1. WORK_TEMPLATES_ERRORLOG.md

**추가 섹션**: "AI 진단용 데이터 소스" (Line 115-207)

**내용**:
- ✅ tKVS 조회 방법 (표준 스크립트 + 해석 방법)
- ✅ tLogSP 조회 방법 (표준 스크립트 + 해석 방법)
- ✅ ErrorLogs 조회 방법 참조
- ✅ 실전 진단 시나리오 예시

**UTC 시간 경고 추가**: 최상단에 DB 시간은 UTC라는 경고 추가

---

### 2. PROHIBITED_ACTION_11_LOG_REQUEST.md

**업데이트**: "올바른 방법" 섹션 대폭 확장 (Line 21-202)

**내용**:
- ✅ tKVS, tLogSP, ErrorLogs 세 테이블의 상세 조회 방법
- ✅ 각 테이블별 표준 스크립트 목록
- ✅ 직접 SQL 조회 방법 (스크립트 없을 때)
- ✅ 진단 워크플로우 예시

---

### 3. query-kvs.ps1 수정

**수정 라인**: Line 30-32

**수정 내용**:
```powershell
# Before: 같은 디렉토리에서 dbconfig.json 찾음
$configPath = Join-Path $scriptPath "dbconfig.json"

# After: 상위 디렉토리의 mgmt/에서 찾음
$repoRoot = Split-Path -Parent $scriptPath
$configPath = Join-Path $repoRoot "mgmt\dbconfig.json"
```

**기대 효과**:
- ✅ scripts/ 디렉토리에서도 정상 실행

---

### 4. query-errorlog-detail.ps1 수정

**수정 라인**: Line 25-28

**수정 내용**:
```powershell
# Before: JSON 모드에서도 메시지 출력
Write-Host "🔍 에러로그 상세 조회: ID = $ErrorId"

# After: JSON 모드에서는 메시지 숨김
if (-not $Json) {
    Write-Host "🔍 에러로그 상세 조회: ID = $ErrorId"
}
```

**기대 효과**:
- ✅ -Json 옵션 사용 시 순수 JSON만 출력

---

## 🎯 테스트 및 검증

### 검증 단계

**1. Hung 프로세스 제거**
```bash
# 서버에서 수동 실행 (한 번만)
pkill -f giipAgent3.sh
```

**2. 다음 Cron 실행 대기** (5분 후)

**3. 로그 확인**
```bash
cd /home/giip/giipAgentLinux
tail -100 log/giipAgent2_$(date +%Y%m%d).log
grep "\[KVS-Log\]" log/giipAgent2_$(date +%Y%m%d).log | tail -20
```

**4. tKVS 확인**
```powershell
cd giipdb
pwsh .\scripts\query-kvs.ps1 -KKey "71174" -KFactor "giipagent" -Top 5
```

**5. ErrorLogs 확인**
```powershell
pwsh .\scripts\errorlogproc\query-recent-errors.ps1
```

---

## 📊 예상 결과

### Case 1: 성공 (RstVal=200)
```
[KVS-Log] ✅ Saved: startup (RstVal=200)
[KVS-Log] ✅ Saved: shutdown (RstVal=200)
```
➡️ **tKVS에 최신 데이터 업데이트**

### Case 2: API 에러 (RstVal ≠ 200)
```
[KVS-Log] ❌ API Error: startup
[KVS-Log] 📊 RstVal: 401
[KVS-Log] 💬 RstMsg: Unauthorized
[KVS-Log] 🔧 ProcName: pApiKVSPutbySk
[KVS-Log] 📄 Full Response: {...}
[KVS-Log] 📤 Request jsondata: {...}
```
➡️ **ErrorLogs 테이블에 자동 기록**  
➡️ **디버깅 파일 보존** (/tmp/kvs_exec_*)

### Case 3: 네트워크 에러 (wget 실패)
```
[KVS-Log] ❌ wget failed: startup (exit_code=1)
[KVS-Log] ⚠️  HTTP Status: ...
```
➡️ **ErrorLogs 테이블에 NetworkError로 기록**

---

## 🔄 재발 방지

1. **Singleton 로직**: 5분 timeout으로 hang 프로세스 자동 제거
2. **API 검증**: RstVal 체크로 실패 즉시 파악
3. **에러 로깅**: 모든 실패를 ErrorLogs DB에 자동 기록
4. **문서화**: 진단 방법을 문서에 명시하여 반복 작업 방지

---

## 🔗 관련 문서

- [NORMAL_MODE_API_DIAGNOSIS.md](./NORMAL_MODE_API_DIAGNOSIS.md) - 초기 분석
- [NORMAL_MODE_API_FIX_COMPLETED.md](./NORMAL_MODE_API_FIX_COMPLETED.md) - 이전 수정
- [API_RESPONSE_VALIDATION_COMPLETED.md](./API_RESPONSE_VALIDATION_COMPLETED.md) - API 검증 완료 보고
- [WORK_TEMPLATES_ERRORLOG.md](../../giipdb/docs/WORK_TEMPLATES_ERRORLOG.md) - 에러로그 처리 템플릿
- [PROHIBITED_ACTION_11_LOG_REQUEST.md](../../giipdb/docs/PROHIBITED_ACTION_11_LOG_REQUEST.md) - 로그 요청 금지

---

**작성 완료**: 2025-12-31  
**상태**: ✅ 코드 수정 완료, 서버 배포 대기  
**다음 작업**: Hung 프로세스 제거 → Cron 실행 대기 → 로그 확인
