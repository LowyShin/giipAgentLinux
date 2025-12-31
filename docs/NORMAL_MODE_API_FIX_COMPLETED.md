# giipAgent3.sh Normal Mode API 전송 개선 작업 완료

**작성일**: 2025-12-31  
**작업 완료**: giipAgent3.sh normal mode API 전송 체크 및 개선

## 📋 작업 요약

giipAgent3.sh의 normal mode에서 API 전송이 제대로 되는지 체크하고, 발견된 문제점들을 수정했습니다.

## 🔍 진단 결과

### 1. API 호출 흐름 확인

Normal mode에서 다음 두 가지 API를 호출합니다:

#### **CQEQueueGet API**
- **파일**: `lib/cqe.sh`의 `queue_get()` 함수
- **용도**: 실행할 스크립트 큐 가져오기
- **호출 위치**: `lib/normal.sh` Line 94

#### **KVSPut API** (save_execution_log)  
- **파일**: `lib/kvs.sh`의 `save_execution_log()` 함수
- **용도**: Agent 실행 로그 저장 (startup, queue_check, error, shutdown)
- **호출 위치**: `lib/normal.sh` Line 87, 110, 117, 122

### 2. 발견된 문제점

#### 문제 1: 에러 메시지 숨김 (Critical)
**위치**: `lib/normal.sh`

여러 곳에서 `save_execution_log` 호출 시 `2>/dev/null`로 에러 메시지를 숨기고 있어서, API 호출 실패 원인을 파악하기 어려웠습니다.

```bash
# ❌ 문제 코드
save_execution_log "queue_check" "$queue_check_details" 2>/dev/null
save_execution_log "error" "$error_details" 2>/dev/null
save_execution_log "script_execution" "$exec_details" 2>/dev/null
```

#### 문제 2: URL 인코딩 누락 (Medium)
**위치**: `lib/cqe.sh`의 `queue_get()` 함수

`queue_get`에서는 URL 인코딩 없이 curl을 호출하고 있었습니다. 반면 `kvs.sh`는 jq @uri로 URL 인코딩을 하고 있어서 일관성이 없었고, 특수문자가 포함된 경우 API 호출이 실패할 수 있었습니다.

```bash
# ❌ 기존 코드 (URL 인코딩 없음)
curl -s -X POST "$api_url" \
    -d "text=${text}&token=${sk}&jsondata=${jsondata}" \
    ...
```

## ✅ 수정 사항

### 수정 1: 에러 메시지 표시 활성화

**파일**: `lib/normal.sh`  
**수정 라인**: 33, 67, 110, 117

`2>/dev/null`을 제거하여 API 호출 실패 시 에러 메시지가 표시되도록 수정했습니다.

```bash
# ✅ 수정 후
save_execution_log "queue_check" "$queue_check_details"
save_execution_log "error" "$error_details"
save_execution_log "script_execution" "$exec_details"
```

**효과**:
- API 호출 실패 시 즉시 원인 파악 가능
- 디버깅 시간 단축
- 운영 환경에서 문제 빠른 해결

### 수정 2: URL 인코딩 추가

**파일**: `lib/cqe.sh`의 `queue_get()` 함수  
**수정 라인**: 48-61

`kvs.sh`와 동일하게 jq @uri를 사용한 URL 인코딩을 추가했습니다.

```bash
# ✅ 수정 후
# URL encode parameters (same pattern as kvs.sh for consistency)
# This is required because curl -d does NOT automatically encode values
local encoded_text=$(printf '%s' "$text" | jq -sRr '@uri' 2>/dev/null || echo "$text")
local encoded_token=$(printf '%s' "$sk" | jq -sRr '@uri' 2>/dev/null || echo "$sk")
local encoded_jsondata=$(printf '%s' "$jsondata" | jq -sRr '@uri' 2>/dev/null || echo "$jsondata")

# Call CQEQueueGet API with URL-encoded parameters
curl -s -X POST "$api_url" \
    -d "text=${encoded_text}&token=${encoded_token}&jsondata=${encoded_jsondata}" \
    ...
```

**효과**:
- 특수문자 포함된 데이터도 안전하게 전송
- kvs.sh와 일관된 패턴 유지
- API 호출 안정성 향상

### 수정 3: 주석 오류 수정

**파일**: `lib/normal.sh`  
**수정 라인**: 9

주석에서 `queue_get`이 `lib/kvs.sh`에서 제공된다고 잘못 기재된 부분을 `lib/cqe.sh`로 수정했습니다.

```bash
# ✅ 수정 후
# Note: queue_get() is provided by lib/cqe.sh for CQEQueueGet API calls
```

## 📊 검증 방법

### 방법 1: 로그 파일 확인

```bash
# 로그 위치
cd /path/to/giipAgentLinux
tail -f log/giipAgent2_$(date +%Y%m%d).log

# 성공 메시지 확인
grep "\[KVS-Log\] ✅ Saved:" log/giipAgent2_$(date +%Y%m%d).log

# 에러 메시지 확인
grep "\[KVS-Log\] ⚠️  Failed" log/giipAgent2_$(date +%Y%m%d).log
grep "\[queue_get\] ❌" log/giipAgent2_$(date +%Y%m%d).log
```

### 방법 2: API 응답 파일 확인

```bash
# 임시 파일 확인
ls -lh /tmp/kvs_exec_* /tmp/kvs_put_* /tmp/queue_response_*

# 최근 KVS 응답 확인
cat $(ls -t /tmp/kvs_exec_response_* 2>/dev/null | head -1) 2>/dev/null | jq .

# 최근 stderr 확인
cat $(ls -t /tmp/kvs_exec_stderr_* 2>/dev/null | head -1) 2>/dev/null | grep -i "http"
```

### 방법 3: 테스트 스크립트 실행

실제 Linux 서버에서:

```bash
cd /path/to/giipAgentLinux

# Normal mode 단독 실행
bash scripts/normal_mode.sh

# 또는 메인 Agent 실행 (gateway_mode=0 설정 필요)
bash giipAgent3.sh
```

## 🎯 기대 효과

### 1. 운영 안정성 향상
- API 호출 실패 시 즉시 원인 파악 가능
- 특수문자로 인한 API 호출 실패 방지

### 2. 디버깅 효율성 증대
- 에러 메시지가 명확하게 표시됨
- 문제 해결 시간 단축

### 3. 코드 일관성 개선
- kvs.sh와 cqe.sh 간 URL 인코딩 패턴 통일
- 주석 정확도 향상

## 📝 체크리스트

실제 환경에서 다음을 확인하세요:

### 필수 확인 사항
- [ ] 로그 파일에 `[KVS-Log] ✅ Saved: startup` 메시지 있음
- [ ] 로그 파일에 `[KVS-Log] ✅ Saved: shutdown` 메시지 있음
- [ ] 로그 파일에 `[queue_get] INFO: No queue available` (큐 없을 때 정상)
- [ ] `/tmp/kvs_exec_*` 파일들이 생성됨 (API 호출 증거)
- [ ] 에러 발생 시 명확한 에러 메시지 표시됨

### 설정 확인
- [ ] `giipAgent.cnf` 파일이 부모 디렉토리에 존재
- [ ] `sk` 변수가 올바르게 설정됨
- [ ] `apiaddrv2` 변수가 올바르게 설정됨 (giipApiSk2 URL)
- [ ] `lssn` 변수가 올바르게 설정됨

### API 응답 확인
- [ ] KVSPut API 호출 성공 (RstVal=200)
- [ ] CQEQueueGet API 호출 성공 (RstVal=200 또는 404)
- [ ] HTTP 401 에러가 없음 (인증 문제)

## 🚀 다음 단계

1. **실제 서버에서 테스트**
   - Normal mode 실행하여 로그 확인
   - API 호출 성공 여부 검증

2. **모니터링**
   - 로그 파일 지속 모니터링
   - API 호출 실패율 확인

3. **추가 개선 (필요 시)**
   - API 호출 재시도 로직 추가
   - 타임아웃 설정 최적화

---

## 📄 관련 파일

### 수정된 파일
- `lib/normal.sh` - 에러 메시지 표시 활성화, 주석 수정
- `lib/cqe.sh` - URL 인코딩 추가

### 새로 생성된 파일
- `docs/NORMAL_MODE_API_DIAGNOSIS.md` - 진단 보고서
- `test-normal-mode-api.sh` - 테스트 스크립트

### 관련 문서
- `docs/WORK_TEMPLATES_AGENT.md` - Agent 작업 템플릿
- `../../giipfaw/docs/giipapi_rules.md` - API 규칙
- `docs/GIIPAGENT3_SPECIFICATION.md` - Agent 3.0 사양서

---

**작업 완료일**: 2025-12-31  
**담당**: AI Agent  
**상태**: ✅ 완료 - 실제 서버 테스트 대기
