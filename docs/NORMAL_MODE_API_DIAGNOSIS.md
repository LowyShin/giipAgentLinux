# giipAgent3.sh Normal Mode API 전송 진단 보고서

**작성일**: 2025-12-31  
**대상**: giipAgent3.sh의 normal mode

## 📋 진단 요약

giipAgent3.sh의 normal mode에서 데이터가 API로 제대로 전송되지 않는 것으로 보이는 문제를 진단했습니다.

## 🔍 API 호출 흐름 분석

### 1. Normal Mode 실행 경로

```bash
giipAgent3.sh (메인)
  ↓
scripts/normal_mode.sh (라인 338-371에서 호출)
  ↓
lib/normal.sh의 run_normal_mode() 함수
  ↓
API 호출 지점들:
```

### 2. API 호출 지점 상세

#### 2-1. save_execution_log 호출 (KVSPut API)

**파일**: `lib/normal.sh`

- **Line 87**: 시작 시 startup 이벤트 로깅
  ```bash
  save_execution_log "startup" "$startup_details"
  ```

- **Line 110**: 큐 체크 결과 로깅 (큐 없음 - 404)
  ```bash
  save_execution_log "queue_check" "$queue_check_details" 2>/dev/null
  ```

- **Line 117**: API 에러 발생 시 로깅
  ```bash
  save_execution_log "error" "$error_details" 2>/dev/null
  ```

- **Line 122**: 종료 시 shutdown 이벤트 로깅
  ```bash
  save_execution_log "shutdown" "$shutdown_details"
  ```

**구현**: `lib/kvs.sh`의 `save_execution_log()` 함수 (Line 67-164)

**API 호출 방식**:
```bash
# ✅ 올바른 패턴 (giipapi_rules.md 준수)
text="KVSPut kType kKey kFactor"
jsondata="{\"kType\":\"lssn\",\"kKey\":\"${lssn}\",\"kFactor\":\"giipagent\",\"kValue\":${kvalue}}"

wget -O "$response_file" \
    --post-data="text=${encoded_text}&token=${encoded_token}&jsondata=${encoded_jsondata}" \
    --header="Content-Type: application/x-www-form-urlencoded" \
    "${kvs_url}" \
    --no-check-certificate \
    --server-response \
    -v 2>"$stderr_file"
```

#### 2-2. queue_get 호출 (CQEQueueGet API)

**파일**: `lib/cqe.sh`의 `queue_get()` 함수 (Line 20-133)

**호출 위치**: `lib/normal.sh` Line 94
```bash
queue_get "$lssn" "$hostname" "$os" "$tmpFileName"
```

**API 호출 방식**:
```bash
# ✅ 올바른 패턴 (giipapi_rules.md 준수)
text="CQEQueueGet lssn hostname os op"
jsondata="{\"lssn\":${lssn},\"hostname\":\"${hostname}\",\"os\":\"${os}\",\"op\":\"op\"}"

curl -s -X POST "$api_url" \
    -d "text=${text}&token=${sk}&jsondata=${jsondata}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --insecure -o "$temp_response" 2>&1
```

## ✅ 코드 검증 결과

### 1. API 호출 패턴 확인

두 API 모두 **giipapi_rules.md 규칙을 올바르게 준수**하고 있습니다:

- ✅ `text`: 파라미터 이름만 포함
- ✅ `jsondata`: 실제 값들을 JSON 형식으로 전송
- ✅ `token`: sk 값 사용 (sk 파라미터 아님!)
- ✅ giipApiSk2 엔드포인트 사용 (`${apiaddrv2}`)

### 2. 잠재적 문제점

#### 2-1. save_execution_log의 2>/dev/null 리다이렉션

**문제**: Line 110, 117에서 `2>/dev/null`로 에러 출력을 억제하고 있어 실패 원인 파악이 어려울 수 있습니다.

```bash
# 현재 (에러 메시지 숨김)
save_execution_log "queue_check" "$queue_check_details" 2>/dev/null

# 권장 (디버깅을 위해 에러 메시지 표시)
save_execution_log "queue_check" "$queue_check_details"
```

#### 2-2. URL 인코딩 방식 차이

**save_execution_log** (lib/kvs.sh):
```bash
# jq @uri를 사용한 URL 인코딩
local encoded_jsondata=$(printf '%s' "$jsondata" | jq -sRr '@uri')
```

**queue_get** (lib/cqe.sh):
```bash
# URL 인코딩 없이 직접 전송
curl -s -X POST "$api_url" \
    -d "text=${text}&token=${sk}&jsondata=${jsondata}" \
    ...
```

⚠️ **잠재적 이슈**: `queue_get`은 URL 인코딩을 하지 않아서, `jsondata`에 특수문자가 포함되면 API 호출이 실패할 수 있습니다.

## 🔧 권장 조치사항

### 1. 즉시 확인 사항

#### 1-1. 로그 파일 확인
```bash
# 로그 파일 위치: {giipAgentLinux}/log/giipAgent2_YYYYMMDD.log

# 최근 로그 확인
tail -f log/giipAgent2_$(date +%Y%m%d).log

# KVS 로그 필터링
grep "\[KVS-Log\]" log/giipAgent2_$(date +%Y%m%d).log

# API 에러 확인
grep "Failed to save\|API call failed" log/giipAgent2_$(date +%Y%m%d).log
```

#### 1-2. 임시 파일 확인
```bash
# KVS API 호출 디버깅 파일들
ls -lh /tmp/kvs_exec_* /tmp/kvs_put_* /tmp/queue_response_*

# 최근 응답 확인
cat /tmp/kvs_exec_response_* 2>/dev/null || echo "No response files found"
cat /tmp/kvs_exec_stderr_* 2>/dev/null || echo "No stderr files found"
```

### 2. 디버깅 강화

#### 2-1. normal.sh 수정 (에러 메시지 표시)

**변경 전**:
```bash
save_execution_log "queue_check" "$queue_check_details" 2>/dev/null
save_execution_log "error" "$error_details" 2>/dev/null
```

**변경 후**:
```bash
save_execution_log "queue_check" "$queue_check_details"  # 에러 메시지 표시
save_execution_log "error" "$error_details"               # 에러 메시지 표시
```

#### 2-2. queue_get URL 인코딩 추가

**파일**: `lib/cqe.sh` (Line 20-133)

**변경 전**:
```bash
curl -s -X POST "$api_url" \
    -d "text=${text}&token=${sk}&jsondata=${jsondata}" \
    ...
```

**변경 후**:
```bash
# URL 인코딩 추가
local encoded_text=$(printf '%s' "$text" | jq -sRr '@uri' 2>/dev/null || echo "$text")
local encoded_token=$(printf '%s' "$sk" | jq -sRr '@uri' 2>/dev/null || echo "$sk")
local encoded_jsondata=$(printf '%s' "$jsondata" | jq -sRr '@uri' 2>/dev/null || echo "$jsondata")

curl -s -X POST "$api_url" \
    -d "text=${encoded_text}&token=${encoded_token}&jsondata=${encoded_jsondata}" \
    ...
```

### 3. 설정 파일 검증

```bash
# giipAgent.cnf 위치 확인 (부모 디렉토리!)
CONFIG_FILE="../giipAgent.cnf"

# 필수 변수 확인
grep -E "^(sk|apiaddrv2|lssn)=" ../giipAgent.cnf

# 예상 출력:
# sk="ffd96..."
# apiaddrv2="https://giipfaw.azurewebsites.net/api/giipApiSk2"
# lssn=71174
```

## 📊 테스트 방법

### 방법 1: 수동 테스트 스크립트 실행

```bash
cd /path/to/giipAgentLinux
bash test-normal-mode-api.sh
```

### 방법 2: normal_mode.sh 직접 실행

```bash
cd /path/to/giipAgentLinux
bash scripts/normal_mode.sh
```

### 방법 3: 메인 Agent 실행 (normal mode만)

```bash
cd /path/to/giipAgentLinux

# giipAgent.cnf에서 gateway_mode=0으로 설정
bash giipAgent3.sh
```

## 🎯 다음 단계

1. **로그 파일 확인** - 실제 에러 메시지 확인
2. **임시 파일 확인** - API 응답 내용 확인
3. **설정 파일 검증** - sk, apiaddrv2, lssn 값 확인
4. **에러 처리 개선** - 2>/dev/null 제거하여 디버깅 강화
5. **URL 인코딩 통일** - queue_get도 URL 인코딩 적용

## 📝 체크리스트

실제 환경에서 다음을 확인해주세요:

- [ ] 로그 파일에 `[KVS-Log] ✅ Saved:` 메시지가 있는가?
- [ ] 로그 파일에 `[KVS-Log] ⚠️  Failed to save:` 에러가 있는가?
- [ ] `/tmp/kvs_exec_*` 파일들이 생성되는가?
- [ ] API 응답 파일에 HTTP 200 OK가 있는가?
- [ ] giipAgent.cnf 파일이 올바른 위치(부모 디렉토리)에 있는가?
- [ ] sk, apiaddrv2 변수가 올바르게 설정되어 있는가?
- [ ] `[queue_get]` 로그에서 RstVal이 무엇인가? (200, 404, 또는 다른 값?)

---

**결론**: 코드 자체는 올바르게 작성되어 있으나, 실행 환경에서의 실제 로그를 확인해야 정확한 문제를 파악할 수 있습니다. 위의 체크리스트를 따라 로그를 검토해주세요.

---

## 📝 작업 이력

### 2025-12-31 13:40 - API 응답 검증 강화 완료

#### ✅ 완료된 수정 사항

**1. `lib/normal.sh` - 에러 메시지 표시 활성화**
- Line 33, 67, 110, 117에서 `2>/dev/null` 제거
- 목적: API 호출 실패 시 에러 메시지가 로그에 표시되도록 함
- 파일: [lib/normal.sh](../lib/normal.sh)

**2. `lib/cqe.sh` - URL 인코딩 추가**
- Line 48-61에 jq @uri 기반 URL 인코딩 추가
- 목적: 특수문자 포함 데이터 안전 전송
- 파일: [lib/cqe.sh](../lib/cqe.sh)

**3. `lib/kvs.sh` - API 응답(RstVal) 검증 추가** ⭐ 핵심
- **save_execution_log()** (Line 132-222): 
  - wget 성공만 체크하던 것을 RstVal까지 검증
  - RstVal ≠ 200이면 상세 에러 출력:
    ```bash
    [KVS-Log] ❌ API Error: ${event_type}
    [KVS-Log] 📊 RstVal: ${rst_val}
    [KVS-Log] 💬 RstMsg: ${rst_msg}
    [KVS-Log] 🔧 ProcName: ${proc_name}
    [KVS-Log] 📄 Full API Response: ${api_response}
    [KVS-Log] 📤 Request jsondata (first 300 chars): ...
    ```
  - 디버깅 파일 보존: `/tmp/kvs_exec_response_*`, `/tmp/kvs_exec_stderr_*`, `/tmp/kvs_exec_post_*`
  - 에러로그 DB에 자동 기록: `log_error()` 호출
  
- **kvs_put()** (Line 295-353):
  - 동일한 RstVal 검증 로직 추가
  - 실패 시 RstMsg, ProcName 출력
  - 디버깅 파일 보존

- 파일: [lib/kvs.sh](../lib/kvs.sh)

#### 📊 수집될 데이터 (다음 실행 시)

이제 다음 실행 시 **추측 없이** 다음 데이터가 수집됩니다:

**1. 로그 파일에 기록될 데이터**:
```bash
# 성공 케이스
[KVS-Log] ✅ Saved: startup (RstVal=200)
[KVS-Log] ✅ Saved: shutdown (RstVal=200)

# 실패 케이스 (실제 원인 파악 가능)
[KVS-Log] ❌ API Error: startup
[KVS-Log] 📊 RstVal: 401  # ← 실제 에러 코드
[KVS-Log] 💬 RstMsg: Unauthorized  # ← 실제 에러 메시지
[KVS-Log] 🔧 ProcName: pApiKVSPutbySk  # ← 실패한 SP 이름
[KVS-Log] 📄 Full API Response: {"RstVal":"401",...}  # ← 전체 응답
[KVS-Log] 📤 Request jsondata: {"kType":"lssn","kKey":"71174",...}  # ← 실제 전송 데이터
```

**2. 디버깅 파일에 저장될 데이터**:
```bash
/tmp/kvs_exec_response_[timestamp]  # API 응답 전체 (JSON)
/tmp/kvs_exec_stderr_[timestamp]    # HTTP 상태 코드, 헤더
/tmp/kvs_exec_post_[timestamp].txt  # POST 데이터 (URL 인코딩 후)
```

**3. 에러로그 DB에 기록될 데이터** (실패 시):
```sql
INSERT INTO ErrorLogs (
  elSource,      -- 'agent'
  elErrorType,   -- 'ApiError' 또는 'NetworkError'
  elErrorMessage, -- 'KVS API failed: startup (RstVal=401)'
  elStackTrace,  -- 'event_type=startup, RstVal=401, RstMsg=Unauthorized, ProcName=pApiKVSPutbySk, API_URL=..., jsondata_preview=...'
  elSeverity,    -- 'error'
  elRequestData  -- 전체 요청 데이터
)
```

#### 🎯 다음 단계 (실제 데이터 수집)

**Step 1: 서버에서 Agent 실행**
```bash
cd /home/giip/giipAgentLinux
bash giipAgent3.sh
```

**Step 2: 로그 수집**
```bash
# 실행 직후 로그 확인
tail -100 log/giipAgent2_$(date +%Y%m%d).log

# KVS 관련 로그만 추출
grep "\[KVS-" log/giipAgent2_$(date +%Y%m%d).log > /tmp/kvs_analysis.log

# 실제 데이터 확인
cat /tmp/kvs_analysis.log
```

**Step 3: 디버깅 파일 수집 (에러 발생 시)**
```bash
# 최근 API 응답
cat $(ls -t /tmp/kvs_exec_response_* 2>/dev/null | head -1) | jq .

# 최근 POST 데이터
cat $(ls -t /tmp/kvs_exec_post_* 2>/dev/null | head -1)

# HTTP 상태
cat $(ls -t /tmp/kvs_exec_stderr_* 2>/dev/null | head -1) | grep "HTTP/"
```

**Step 4: 에러로그 DB 조회 (에러 발생 시)**
```powershell
cd giipdb
pwsh .\scripts\errorlogproc\query-recent-errors.ps1

# ApiError만 조회
pwsh .\scripts\errorlogproc\query-errorlogs.ps1 -ErrorType "ApiError" -Hours 1
```

#### 📋 분석 체크리스트 (실제 데이터 기반)

**Case 1: 성공 (RstVal=200)**
- [ ] 로그에 `[KVS-Log] ✅ Saved: startup (RstVal=200)` 있음
- [ ] 로그에 `[KVS-Log] ✅ Saved: shutdown (RstVal=200)` 있음
- [ ] DB에서 확인: `SELECT TOP 1 * FROM tKVS WHERE kType='lssn' AND kKey='71174' AND kFactor='giipagent' ORDER BY kRegdt DESC`
- [ ] kValue에 최신 timestamp 있음
- → **문제 해결됨**

**Case 2: API 에러 (RstVal ≠ 200)**
- [ ] 로그에서 실제 RstVal 값 확인: _______
- [ ] 로그에서 실제 RstMsg 확인: _______
- [ ] 로그에서 실제 ProcName 확인: _______
- [ ] 로그에서 실제 Request jsondata 확인: _______
- [ ] `/tmp/kvs_exec_response_*` 파일 내용 확인
- [ ] 에러로그 DB에서 상세 정보 확인
- → **실제 데이터로 원인 분석**

**Case 3: 네트워크 에러 (wget 실패)**
- [ ] 로그에 `[KVS-Log] ❌ wget failed` 있음
- [ ] HTTP 상태 코드 확인: _______
- [ ] stderr 파일에서 네트워크 에러 확인
- → **네트워크 또는 API 엔드포인트 문제**

#### ⚠️ 절대 금지 (추측 금지)

다음 단계 전까지 **절대 하지 말 것**:
- ❌ 로그 보기 전에 원인 추측
- ❌ 실제 데이터 없이 코드 추가 수정
- ❌ run.ps1이나 SP 수정 (절대 금지!)

**먼저 할 것**:
- ✅ 실제 서버 실행
- ✅ 로그 수집
- ✅ 디버깅 파일 확인
- ✅ 에러로그 DB 확인
- ✅ **실제 데이터를 보고** 원인 파악

---

**최종 업데이트**: 2025-12-31 13:40  
**상태**: ⏳ 실제 서버 실행 및 데이터 수집 대기  
**다음 작업**: 로그 수집 후 실제 데이터 기반 분석

