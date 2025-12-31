# giipAgent3.sh API 응답 검증 강화 완료

**작업일**: 2025-12-31  
**목적**: Normal mode에서 API 전송 후 실제 성공 여부를 확인하기 위한 디버깅 강화

---

## 📋 작업 배경

**문제**: 
- Agent 로그에서 `[KVS-Log] ✅ Saved: startup` 출력
- 하지만 DB에 데이터 반영 안됨 (최종 업데이트 2025/12/16)
- wget exit_code만 체크해서 HTTP 성공 시 무조건 성공으로 판단

**원인**:
- wget이 성공(exit_code=0)해도 API가 실패할 수 있음
- API 응답의 **RstVal**을 확인하지 않아서 실패 원인 파악 불가

---

## ✅ 수정 내용

### 1. save_execution_log() 함수 개선

**파일**: `giipAgentLinux/lib/kvs.sh` (Line 132-222)

**Before**:
```bash
if [ $exit_code -eq 0 ]; then
    echo "[KVS-Log] ✅ Saved: ${event_type}"
    # wget 성공만 체크, API 응답 무시
fi
```

**After**:
```bash
# 1단계: wget 성공 확인
if [ $exit_code -ne 0 ]; then
    echo "[KVS-Log] ❌ wget failed: ${event_type}"
    # 네트워크 에러 상세 로그
    return $exit_code
fi

# 2단계: API 응답(RstVal) 검증
local rst_val=$(echo "$api_response" | jq -r '.RstVal')

if [ "$rst_val" = "200" ]; then
    echo "[KVS-Log] ✅ Saved: ${event_type} (RstVal=200)"
else
    # API 에러 상세 분석
    echo "[KVS-Log] ❌ API Error: ${event_type}"
    echo "[KVS-Log] 📊 RstVal: ${rst_val}"
    echo "[KVS-Log] 💬 RstMsg: ${rst_msg}"
    echo "[KVS-Log] 🔧 ProcName: ${proc_name}"
    echo "[KVS-Log] 📄 Full API Response: ${api_response}"
    
    # 디버깅 파일 보존
    echo "[KVS-Log] 🔍 Debug files saved:"
    echo "  Response: $response_file"
    echo "  Stderr: $stderr_file"
    echo "  Post data: $post_data_file"
    
    # 에러로그에 기록
    log_error "KVS API failed: ${event_type} (RstVal=${rst_val})" \
              "ApiError" \
              "event_type=${event_type}, RstVal=${rst_val}, RstMsg=${rst_msg}, ..."
    
    return 1
fi
```

### 2. kvs_put() 함수 개선

**파일**: `giipAgentLinux/lib/kvs.sh` (Line 295-353)

동일한 패턴으로 RstVal 검증 추가:
- wget 성공 후 API 응답 파싱
- RstVal=200 확인
- 실패 시 RstMsg, ProcName 출력
- 디버깅 파일 보존

---

## 🎯 기대 효과

### 1. 실패 원인 즉시 파악

**이전**:
```
[KVS-Log] ✅ Saved: startup
# 실제로는 실패했지만 모름
```

**이후**:
```
[KVS-Log] ❌ API Error: startup
[KVS-Log] 📊 RstVal: 401
[KVS-Log] 💬 RstMsg: Unauthorized
[KVS-Log] 🔧 ProcName: pApiKVSPutbySk
[KVS-Log] 📄 Full API Response: {"RstVal":"401","RstMsg":"Unauthorized",...}
```

### 2. 송신 측 문제 즉시 식별

API 실패 시 다음을 확인:
1. **RstVal**: 400, 401, 500 등으로 에러 유형 파악
2. **RstMsg**: 구체적인 실패 원인
3. **ProcName**: 어떤 SP가 실패했는지
4. **Request jsondata**: 송신 측 데이터 확인

→ **giipapi_rules.md 위반 여부 즉시 판단 가능**

### 3. 디버깅 파일 보존

에러 발생 시 다음 파일들이 보존됨:
- `/tmp/kvs_exec_response_[timestamp]` - API 응답 전체
- `/tmp/kvs_exec_stderr_[timestamp]` - wget stderr
- `/tmp/kvs_exec_post_[timestamp].txt` - POST 데이터

→ **상세 분석 가능**

### 4. 에러로그 DB 자동 기록

API 실패 시 `log_error()` 호출:
```bash
log_error "KVS API failed: startup (RstVal=401)" \
          "ApiError" \
          "event_type=startup, RstVal=401, RstMsg=Unauthorized, ProcName=pApiKVSPutbySk, ..."
```

→ **DB에 에러 자동 저장, 나중에 분석 가능**

---

## 🛡️ 규칙 준수 확인

### ✅ 절대 금지 사항 준수

- ❌ run.ps1 수정 없음
- ❌ 공통 모듈 수정 없음
- ❌ SP 정의 변경 없음

### ✅ 올바른 순서로 작업

1. **송신 측(Agent) 코드만 수정** ✅
2. **디버깅 정보 추가** ✅
3. **API 규격 자체는 변경 안함** ✅
4. **실패 원인 파악 후 송신 측 데이터 검증** (다음 단계)

---

## 📊 테스트 방법

### 1. Normal mode 실행

```bash
cd /home/giip/giipAgentLinux
bash giipAgent3.sh
```

### 2. 로그 확인

```bash
# 성공 케이스
grep "\[KVS-Log\] ✅ Saved.*RstVal=200" log/giipAgent2_$(date +%Y%m%d).log

# 실패 케이스
grep "\[KVS-Log\] ❌" log/giipAgent2_$(date +%Y%m%d).log
grep "RstVal:" log/giipAgent2_$(date +%Y%m%d).log
grep "RstMsg:" log/giipAgent2_$(date +%Y%m%d).log
grep "ProcName:" log/giipAgent2_$(date +%Y%m%d).log
```

### 3. 디버깅 파일 확인

```bash
# 최근 API 응답 확인
cat $(ls -t /tmp/kvs_exec_response_* 2>/dev/null | head -1) | jq .

# 최근 POST 데이터 확인
cat $(ls -t /tmp/kvs_exec_post_* 2>/dev/null | head -1)
```

### 4. 에러로그 DB 확인

```powershell
# giipdb에서 최근 에러 조회
cd giipdb
pwsh .\scripts\errorlogproc\query-recent-errors.ps1

# ApiError 타입 에러만
pwsh .\scripts\errorlogproc\query-errorlogs.ps1 -ErrorType "ApiError"
```

---

## 🔍 다음 단계 (실패 발견 시)

### 1. 로그 분석

```bash
# 예시 에러:
[KVS-Log] ❌ API Error: startup
[KVS-Log] 📊 RstVal: 401
[KVS-Log] 💬 RstMsg: Unauthorized
[KVS-Log] 🔧 ProcName: pApiKVSPutbySk
[KVS-Log] 📄 Full API Response: ...
[KVS-Log] 📤 Request jsondata (first 300 chars): {"kType":"lssn","kKey":"71174",...}
```

### 2. 원인 파악

**RstVal 기준**:
- `401`: 인증 실패 → token 파라미터 확인
- `400`: 파라미터 오류 → text/jsondata 규격 확인
- `500`: SP 에러 → ProcName 확인, SP 로그 확인

### 3. giipapi_rules.md 검증

```bash
# 올바른 패턴인지 확인
text="KVSPut kType kKey kFactor"  # ← 파라미터 이름만
jsondata='{"kType":"lssn","kKey":"71174",...}'  # ← 실제 값
token="${sk}"  # ← 인증 키
```

### 4. 송신 측 코드 수정 (규약 위반 발견 시)

**절대 수정하지 않음**:
- ❌ run.ps1
- ❌ SP (pApiKVSPutbySk 등)

**수정 대상**:
- ✅ `lib/kvs.sh`의 API 호출 부분만
- ✅ text/jsondata 생성 로직

---

## 📝 체크리스트

### 실행 후 확인 사항

- [ ] `[KVS-Log] ✅ Saved: startup (RstVal=200)` 로그 있음
- [ ] `[KVS-Log] ✅ Saved: shutdown (RstVal=200)` 로그 있음
- [ ] DB에 giipagent kFactor 데이터가 업데이트됨
- [ ] 최종 업데이트 시각이 현재 시각으로 변경됨

### 실패 시 확인 사항

- [ ] RstVal 값 확인 (401, 400, 500?)
- [ ] RstMsg 내용 확인
- [ ] ProcName 확인
- [ ] Request jsondata 확인
- [ ] giipapi_rules.md와 비교
- [ ] 송신 측 데이터 수정 (run.ps1/SP는 절대 수정 안함!)

---

## 🔗 관련 문서

- [WORK_TEMPLATES_ERRORLOG.md](../../giipdb/docs/WORK_TEMPLATES_ERRORLOG.md) - 에러 처리 워크플로우
- [giipapi_rules.md](../../giipfaw/docs/giipapi_rules.md) - API 호출 규약
- [NORMAL_MODE_API_FIX_COMPLETED.md](./NORMAL_MODE_API_FIX_COMPLETED.md) - 이전 작업

---

**작업 완료**: 2025-12-31  
**상태**: ✅ 완료 - 실제 서버 테스트 대기  
**다음 작업**: 로그 확인 후 실패 원인 분석
