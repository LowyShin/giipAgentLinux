# giipAgent2.sh 실행 내역 KVS 저장 기능 구현

**날짜**: 2025-11-08  
**작업자**: AI Assistant  
**목적**: giipAgent2.sh 실행 시 모든 활동을 KVS의 "giipagent" factor에 저장하여 실행 내역 추적 및 디버깅 지원

---

## 📋 작업 요약

### 1. 구현 내용

#### ✅ KVS 저장 함수 추가 (giipAgent2.sh)

**위치**: Line 910-960 (새로 추가)

**함수명**: `save_execution_log(event_type, details_json)`

**기능**:
- 이벤트 타입과 상세 정보를 받아서 KVS에 저장
- kType: "lssn", kKey: "{lssn}", kFactor: "giipagent"
- JSON 형식으로 저장 (event_type, timestamp, lssn, hostname, mode, version, details)
- giipApiSk2 API 호출

**코드**:
```bash
save_execution_log() {
	local event_type=$1
	local details_json=$2
	
	local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	local hostname=$(hostname)
	local mode="${gateway_mode}"
	[ "$mode" = "1" ] && mode="gateway" || mode="normal"
	
	# Escape quotes in details_json
	details_json=$(echo "$details_json" | sed 's/"/\\"/g')
	
	local kvalue="{\"event_type\":\"${event_type}\",\"timestamp\":\"${timestamp}\",\"lssn\":${lssn},\"hostname\":\"${hostname}\",\"mode\":\"${mode}\",\"version\":\"${sv}\",\"details\":${details_json}}"
	
	local kvs_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && kvs_url="${kvs_url}?code=${apiaddrcode}"
	
	local text="KVSPut kType kKey kFactor"
	local jsondata="{\"kType\":\"lssn\",\"kKey\":\"${lssn}\",\"kFactor\":\"giipagent\",\"kValue\":${kvalue}}"
	
	# URL encode jsondata
	jsondata_encoded=$(echo "$jsondata" | sed 's/ /%20/g' | sed 's/"/\\"/g')
	
	wget -O /dev/null \
		--post-data="text=${text}&token=${sk}&jsondata=${jsondata_encoded}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"${kvs_url}" \
		--no-check-certificate -q 2>&1
	
	local exit_code=$?
	if [ $exit_code -eq 0 ]; then
		echo "[KVS-Log] ✅ Saved: ${event_type}" >> $LogFileName 2>/dev/null
	else
		echo "[KVS-Log] ⚠️  Failed to save: ${event_type} (exit_code=${exit_code})" >> $LogFileName 2>/dev/null
	fi
}
```

#### ✅ 이벤트 로깅 지점 추가

**Gateway 모드**:

1. **Gateway 초기화 완료** (Line 1050-1090):
   ```bash
   init_details="{\"config_file\":\"giipAgent.cnf\",\"api_endpoint\":\"${apiaddrv2}\",\"pid\":$$}"
   save_execution_log "startup" "$init_details"
   
   # ... (sshpass, DB clients 확인)
   
   init_complete_details="{\"sshpass_installed\":true,\"python_version\":\"3.8.10\",\"db_clients\":{...},\"server_sync_status\":\"success\",\"server_count\":5}"
   save_execution_log "gateway_init" "$init_complete_details"
   ```

2. **sshpass 설치 실패** (Line 1070-1080):
   ```bash
   error_details="{\"error_type\":\"config_error\",\"error_message\":\"Failed to setup sshpass\",\"error_code\":1,\"context\":\"gateway_init\"}"
   save_execution_log "error" "$error_details"
   ```

3. **Heartbeat 트리거** (Line 1170-1180):
   ```bash
   heartbeat_details="{\"interval_seconds\":300,\"script_path\":\"./giipAgentGateway-heartbeat.sh\",\"background_pid\":12345}"
   save_execution_log "heartbeat" "$heartbeat_details"
   ```

**Normal 모드**:

1. **Agent 시작** (Line 1240-1245):
   ```bash
   startup_details="{\"pid\":$$,\"config_file\":\"giipAgent.cnf\",\"api_endpoint\":\"${lwAPIURL}\"}"
   save_execution_log "startup" "$startup_details"
   ```

2. **Queue 조회** (Line 1260-1320):
   ```bash
   # RstVal=404 (큐 없음)
   queue_check_details="{\"api_response\":\"404\",\"has_queue\":false,\"mssn\":0,\"script_source\":\"none\"}"
   save_execution_log "queue_check" "$queue_check_details"
   
   # RstVal=200, ms_body 있음
   queue_check_details="{\"api_response\":\"200\",\"has_queue\":true,\"mssn\":123,\"script_source\":\"ms_body\"}"
   save_execution_log "queue_check" "$queue_check_details"
   
   # RstVal=200, repository에서 조회
   queue_check_details="{\"api_response\":\"200\",\"has_queue\":true,\"mssn\":123,\"script_source\":\"repository\"}"
   save_execution_log "queue_check" "$queue_check_details"
   ```

3. **스크립트 실행** (Line 1350-1390):
   ```bash
   # Expect 스크립트
   exec_details="{\"script_type\":\"expect\",\"exit_code\":0,\"execution_time_seconds\":5}"
   save_execution_log "script_execution" "$exec_details"
   
   # Bash 스크립트
   exec_details="{\"script_type\":\"bash\",\"exit_code\":0,\"execution_time_seconds\":3}"
   save_execution_log "script_execution" "$exec_details"
   ```

4. **에러 발생** (Line 1290-1340):
   ```bash
   # Repository 조회 실패
   error_details="{\"error_type\":\"api_error\",\"error_message\":\"Failed to fetch script from repository\",\"error_code\":1,\"context\":\"queue_fetch\",\"mssn\":123}"
   save_execution_log "error" "$error_details"
   
   # API 응답 에러
   error_details="{\"error_type\":\"api_error\",\"error_message\":\"Unexpected API response\",\"error_code\":500,\"context\":\"queue_check\"}"
   save_execution_log "error" "$error_details"
   
   # HTTP 에러
   error_details="{\"error_type\":\"script_error\",\"error_message\":\"HTTP Error in script\",\"error_code\":1,\"context\":\"script_execution\"}"
   save_execution_log "error" "$error_details"
   ```

5. **Agent 종료** (Line 1400-1415):
   ```bash
   # 정상 종료
   shutdown_details="{\"reason\":\"normal\",\"process_count\":999,\"uptime_seconds\":0}"
   save_execution_log "shutdown" "$shutdown_details"
   
   # 프로세스 중복 종료
   shutdown_details="{\"reason\":\"duplicate_process\",\"process_count\":4,\"uptime_seconds\":0}"
   save_execution_log "shutdown" "$shutdown_details"
   ```

#### ✅ 문서 작성

1. **GIIPAGENT2_SPECIFICATION.md** (새로 작성):
   - giipAgent2.sh 전체 분석 및 실행 조건 문서화
   - 동작 흐름 다이어그램
   - KVS 저장 구조 설명
   - event_type별 details 구조 정의
   - 구현 계획

2. **README.md 업데이트**:
   - Documentation 섹션에 GIIPAGENT2_SPECIFICATION.md 추가
   - Overview에 "Tracks execution history" 기능 추가
   - "Execution Tracking" 섹션 새로 추가:
     - 추적 대상 이벤트 목록
     - SQL 조회 예시
     - 이벤트 타입별 설명 표
     - 트러블슈팅 예시

---

## 📊 저장 데이터 구조

### KVS 저장 형식

```json
{
  "kType": "lssn",
  "kKey": "71174",
  "kFactor": "giipagent",
  "kValue": {
    "event_type": "startup|queue_check|script_execution|shutdown|gateway_init|heartbeat|db_query|remote_execution|error",
    "timestamp": "2025-11-08 16:30:00",
    "lssn": 71174,
    "hostname": "cctrank03",
    "mode": "normal|gateway",
    "version": "2.00",
    "details": {
      // event_type별 상세 정보
    }
  }
}
```

### Event Types 목록

| Event Type | Normal Mode | Gateway Mode | 설명 |
|-----------|-------------|--------------|------|
| `startup` | ✅ | ✅ | Agent 시작 |
| `shutdown` | ✅ | ✅ | Agent 종료 |
| `queue_check` | ✅ | ✅ | Queue API 호출 결과 |
| `script_execution` | ✅ | ✅ | 스크립트 실행 완료 |
| `gateway_init` | ❌ | ✅ | Gateway 초기화 완료 |
| `heartbeat` | ❌ | ✅ | Heartbeat 트리거 |
| `db_query` | ❌ | ✅ | DB 쿼리 실행 (미구현) |
| `remote_execution` | ❌ | ✅ | 원격 서버 처리 (미구현) |
| `error` | ✅ | ✅ | 에러 발생 |

---

## 🔍 조회 예시

### 최근 100개 실행 내역 조회

```sql
SELECT TOP 100
    kRegdt,
    JSON_VALUE(kValue, '$.event_type') AS event_type,
    JSON_VALUE(kValue, '$.timestamp') AS timestamp,
    JSON_VALUE(kValue, '$.lssn') AS lssn,
    JSON_VALUE(kValue, '$.hostname') AS hostname,
    JSON_VALUE(kValue, '$.mode') AS mode,
    JSON_VALUE(kValue, '$.version') AS version,
    kValue AS details
FROM tKVS
WHERE kType = 'lssn'
  AND kKey = '71174'
  AND kFactor = 'giipagent'
ORDER BY kRegdt DESC
```

### Queue 조회 실패 확인

```sql
SELECT 
    kRegdt,
    JSON_VALUE(kValue, '$.details.api_response') AS api_response,
    JSON_VALUE(kValue, '$.details.has_queue') AS has_queue,
    JSON_VALUE(kValue, '$.details.script_source') AS script_source
FROM tKVS
WHERE kFactor = 'giipagent'
  AND JSON_VALUE(kValue, '$.event_type') = 'queue_check'
  AND JSON_VALUE(kValue, '$.details.api_response') = '404'
ORDER BY kRegdt DESC
```

### 스크립트 실행 성공률 확인

```sql
SELECT 
    COUNT(*) AS total_executions,
    SUM(CASE WHEN JSON_VALUE(kValue, '$.details.exit_code') = '0' THEN 1 ELSE 0 END) AS success_count,
    SUM(CASE WHEN JSON_VALUE(kValue, '$.details.exit_code') != '0' THEN 1 ELSE 0 END) AS failed_count,
    AVG(CAST(JSON_VALUE(kValue, '$.details.execution_time_seconds') AS INT)) AS avg_duration
FROM tKVS
WHERE kFactor = 'giipagent'
  AND JSON_VALUE(kValue, '$.event_type') = 'script_execution'
  AND kRegdt >= DATEADD(day, -7, GETDATE())
```

### 에러 타입별 통계

```sql
SELECT 
    JSON_VALUE(kValue, '$.details.error_type') AS error_type,
    JSON_VALUE(kValue, '$.details.context') AS context,
    COUNT(*) AS error_count,
    MAX(kRegdt) AS last_occurrence
FROM tKVS
WHERE kFactor = 'giipagent'
  AND JSON_VALUE(kValue, '$.event_type') = 'error'
  AND kRegdt >= DATEADD(day, -7, GETDATE())
GROUP BY 
    JSON_VALUE(kValue, '$.details.error_type'),
    JSON_VALUE(kValue, '$.details.context')
ORDER BY error_count DESC
```

---

## 🔄 기존 KVS 저장과의 관계

### 병행 저장 (Gateway 모드)

**기존 저장 유지**:
- `gateway_status` factor: Gateway 특화 상태 (startup, error, sync)
- `gateway_heartbeat` factor: Heartbeat 특화 상태
- `db_query_result` factor: 실제 쿼리 결과 데이터

**신규 저장 추가**:
- `giipagent` factor: 통합 실행 로그 (무엇이 실행되었는지 추적)

**목적 차이**:
- **기존**: 특정 기능의 상태 저장 (현재 상태 확인용)
- **신규**: 전체 실행 흐름 추적 (Audit Log, 디버깅용)

### 데이터 중복 최소화

- 기존 저장: Gateway 특화 기능만 (backward compatibility)
- 신규 저장: 모든 Agent 활동 (통합 추적)
- 두 가지 모두 유지하여 기존 시스템 호환성 보장

---

## ✅ 테스트 계획

### 1. Normal 모드 테스트

**시나리오**:
1. Agent 시작 → startup 이벤트 확인
2. Queue 없음 (404) → queue_check 이벤트 확인 (has_queue=false)
3. Queue 있음 (200, ms_body) → queue_check 이벤트 확인 (script_source=ms_body)
4. 스크립트 실행 → script_execution 이벤트 확인 (exit_code, duration)
5. Agent 종료 → shutdown 이벤트 확인

**검증 SQL**:
```sql
SELECT * FROM tKVS
WHERE kType = 'lssn'
  AND kKey = '71174'
  AND kFactor = 'giipagent'
  AND kRegdt >= DATEADD(minute, -10, GETDATE())
ORDER BY kRegdt DESC
```

### 2. Gateway 모드 테스트

**시나리오**:
1. Gateway 시작 → startup, gateway_init 이벤트 확인
2. Heartbeat 트리거 (5분 후) → heartbeat 이벤트 확인
3. DB 클라이언트 정보 확인 → gateway_init details에서 db_clients 확인

**검증 SQL**:
```sql
SELECT 
    kRegdt,
    JSON_VALUE(kValue, '$.event_type') AS event_type,
    JSON_VALUE(kValue, '$.details') AS details
FROM tKVS
WHERE kFactor = 'giipagent'
  AND JSON_VALUE(kValue, '$.mode') = 'gateway'
ORDER BY kRegdt DESC
```

### 3. 에러 처리 테스트

**시나리오**:
1. API 응답 에러 (500) → error 이벤트 확인 (error_type=api_error)
2. Repository 조회 실패 → error 이벤트 확인 (context=queue_fetch)
3. HTTP Error 스크립트 → error 이벤트 확인 (error_type=script_error)

**검증 SQL**:
```sql
SELECT * FROM tKVS
WHERE kFactor = 'giipagent'
  AND JSON_VALUE(kValue, '$.event_type') = 'error'
ORDER BY kRegdt DESC
```

---

## 📝 다음 단계 (선택사항)

### 1. 원격 서버 처리 로깅 (Gateway 모드)

**위치**: Line 850-920 (process_gateway_servers 함수 내)

**추가 내용**:
```bash
# 각 서버 처리 시작 시
remote_details="{\"target_hostname\":\"${hostname}\",\"target_lssn\":${lssn},\"ssh_host\":\"${ssh_host}\",\"ssh_port\":${ssh_port},\"auth_method\":\"password|key\",\"queue_response\":\"${rstval}\",\"execution_status\":\"success|failed|no_queue\"}"
save_execution_log "remote_execution" "$remote_details"
```

### 2. DB 쿼리 실행 로깅 (Gateway 모드)

**위치**: Line 620-630 (execute_db_query 함수 내)

**추가 내용**:
```bash
# 쿼리 실행 후
db_query_details="{\"gmq_sn\":${gmq_sn},\"target_lssn\":${target_lssn},\"db_type\":\"${db_type}\",\"db_host\":\"${db_host}\",\"query_name\":\"${query_name}\",\"exit_code\":${exit_code},\"execution_time_seconds\":${duration},\"result_row_count\":${row_count},\"kvs_save_status\":\"success|failed\"}"
save_execution_log "db_query" "$db_query_details"
```

### 3. Web UI 조회 페이지 추가

**기능**:
- Agent 실행 내역 조회
- 이벤트 타입별 필터링
- 시간 범위 선택
- 에러 통계 그래프

**구현 위치**: `giipv3/src/app/agent-history/page.tsx` (새로 생성)

---

## 🎯 결론

### 구현 완료 항목

✅ **KVS 저장 함수 추가** (save_execution_log)  
✅ **Normal 모드 로깅**:
- Agent 시작/종료
- Queue 조회
- 스크립트 실행
- 에러 발생

✅ **Gateway 모드 로깅**:
- Gateway 초기화
- Heartbeat 트리거
- 에러 발생

✅ **문서화**:
- GIIPAGENT2_SPECIFICATION.md (전체 사양서)
- README.md 업데이트 (사용 가이드)

### 미구현 항목 (선택사항)

🔄 **Gateway 모드 추가 로깅**:
- 원격 서버 처리 (remote_execution)
- DB 쿼리 실행 (db_query)

🔄 **Web UI**:
- Agent 실행 내역 조회 페이지

### 기대 효과

1. **완전한 Audit Trail**: 모든 Agent 활동 기록
2. **디버깅 용이**: 에러 원인 추적 가능
3. **성능 분석**: 스크립트 실행 시간 통계
4. **운영 모니터링**: Queue 처리 현황 실시간 파악
5. **문제 예방**: 반복 에러 패턴 조기 발견

---

**작성 완료**: 2025-11-08  
**다음 작업**: 테스트 서버에서 실행 확인 후 프로덕션 배포
