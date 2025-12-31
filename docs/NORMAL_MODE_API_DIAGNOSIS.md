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
