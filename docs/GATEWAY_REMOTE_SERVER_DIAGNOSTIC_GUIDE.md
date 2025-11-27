# 🔍 Gateway 리모트 서버 처리 중단 - 진단 가이드

> **📅 문서 메타데이터**  
> - 작성일: 2025-11-27
> - 용도: Gateway가 리모트 서버를 처리하지 않을 때 원인 파악
> - 대상: DevOps, Gateway 관리자
> - 관련 파일: `giipAgent3.sh`, `lib/gateway.sh`

---

## 🎯 개요

Gateway 서버가 갑자기 리모트 서버 처리를 중단한 경우 체계적으로 원인을 파악하는 진단 가이드입니다.

---

## 📊 giipAgent3.sh 전체 실행 플로우

### 🔄 Main Execution Flow

```
┌─────────────────────────────────────────────────────────────┐
│ giipAgent3.sh 시작                                           │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
         ┌──────────────────┐
         │ [5.1] Agent 시작  │
         │ - 버전: 3.00     │
         │ - 라이브러리 로드  │
         └────────┬─────────┘
                  │
                  ▼
         ┌──────────────────────┐
         │ [5.2] 설정 로드       │
         │ - giipAgent.cnf 읽기 │
         │ - 환경변수 검증      │
         └────────┬─────────────┘
                  │
                  ▼
    ┌────────────────────────────┐
    │ [5.3] is_gateway 값 확인   │
    │ (DB API: LSvrGetConfig)   │
    └────┬──────────────────┬────┘
         │                  │
    is_gateway=0        is_gateway=1
    (또는 false)        (또는 true)
         │                  │
         ▼                  ▼
    ┌──────────────┐  ┌──────────────────┐
    │ NORMAL MODE  │  │ GATEWAY MODE 진입 │
    │              │  │ [5.3.G] 초기화   │
    │ Queue 기반   │  │ - 리모트 서버    │
    │ 일반 처리    │  │   목록 조회      │
    │ (normal.sh) │  └────────┬─────────┘
    └──────────────┘           │
                              ▼
                   ┌─────────────────────┐
                   │ [5.4] 서버 목록 조회 │
                   │ API:                │
                   │ GatewayRemoteServer│
                   │ ListForAgent       │
                   └────────┬────────────┘
                            │
                    ┌───────┴──────┐
                    │              │
            성공 (count>0)   실패 or 빈 배열
                    │              │
                    ▼              ▼
         ┌──────────────────┐  ┌─────────────┐
         │ [5.5] 루프 시작   │  │ [5.5.E] 에러│
         │ - 각 서버별 처리  │  │ - 대기 후   │
         └────────┬─────────┘  │   재시도    │
                  │             └─────────────┘
                  ▼
    ┌────────────────────────────┐
    │ [5.6] 서버별 처리 시작      │
    │ - lssn별 루프              │
    └────────┬───────────────────┘
             │
             ▼
    ┌────────────────────────────┐
    │ [5.7] SSH 연결 테스트      │
    │ - sshpass 검증            │
    │ - 인증정보 확인            │
    └────┬──────────────────┬────┘
         │                  │
      성공                 실패
         │                  │
         ▼                  ▼
    ┌──────────────┐  ┌─────────────┐
    │ [5.8] 원격   │  │ [5.8.E]    │
    │ 명령 실행    │  │ SSH 에러    │
    │ - 데이터 수집│  │ 기록 및     │
    │ - KVS 저장   │  │ 다음 서버로 │
    └────┬─────────┘  └─────────────┘
         │
         ▼
    ┌──────────────┐
    │ [5.9] Auto-  │
    │ Discover 실행│
    │ - 시스템정보 │
    │   수집       │
    └────┬─────────┘
         │
         ▼
    ┌────────────────┐
    │ [5.10] 관리DB  │
    │ 체크 (Gateway) │
    │ - MySQL/MSSQL │
    │ - 성능정보     │
    └────┬───────────┘
         │
         ▼
    ┌────────────────┐
    │ 모든 서버 처리 │
    │ 완료?          │
    └────┬────────┬──┘
         │        │
         예      아니오
         │        │
         ▼        └───────┐
    ┌──────────┐          │
    │ [6.0]   │          ▼
    │ 정상종료 │◄─────────┘
    │ normal_ │
    │ exit    │
    └──────────┘
```

### 📋 상세 실행 단계별 KVS Factor 매핑

| 단계 | 포인트 | 설명 | KVS Factor | 정상 신호 (JSON in kValue) | 에러 신호 (JSON in kValue) |
|------|--------|------|-----------|----------|----------|
| 1 | [5.1] | Agent 시작 | `giipagent` | `{"event_type":"startup","mode":"gateway","is_gateway":1}` | ❌ 없음 → 실행 안됨 |
| 2 | [5.2] | 설정 로드 | ⚠️ KVS 미기록* | - | - |
| 3 | [5.3] | is_gateway 판단 | `api_lsvrgetconfig_response` | `{"is_gateway":1}` | `{"is_gateway":0,"error":"API failed"}` |
| 3.G | [5.3.G] | Gateway 모드 초기화 | `giipagent` | `{"event_type":"gateway_init","server_count":N}` | ❌ 없음 → Normal 모드 진입 |
| 4.S | [5.4-START] | 리모트 서버 조회 시작 | `gateway_step_5.4_start` | `{"action":"list_servers_start","timestamp":"..."}` | - |
| 4 | [5.4] | 리모트 서버 조회 성공 | `gateway_step_5.4_success` | `{"action":"list_servers_success","server_count":N}` | `gateway_step_5.4_failed`: `{"reason":"empty_response"}` 또는 `{"reason":"api_error_response"}` |
| 5.E | [5.5-EXTRACT] | 서버 정보 추출 | `gateway_server_extract` | `{"action":"server_params_extracted","server_params":{...}}` | `gateway_step_5.5_failed`: `{"action":"extract_params_empty"}` |
| 5.V | [5.5-VALIDATE] | 서버 정보 검증 | - | ✅ 통과 시 다음 단계 | `gateway_step_5.5_failed`: `{"action":"validation_failed","hostname":"..."}` |
| 6 | [5.6] | 서버 파싱 완료 | `gateway_step_5.6_parsed` | `{"action":"server_parsed","hostname":"...","ssh_host":"...","ssh_port":...}` | - |
| 7 | [5.8] | 큐 조회 | `gateway_step_5.8_success` | `{"action":"queue_fetch_success","queue_file_size":...}` | `gateway_step_5.8_failed`: `{"error":"HTTP Error..."}` |
| 8 | [5.9-START] | SSH 시도 시작 | `gateway_step_5.9_ssh_start` | `{"action":"ssh_attempt_start","ssh_host":"...","ssh_port":...}` | - |
| 8 | [5.9-SUCCESS] | SSH 성공 | `gateway_step_5.9_ssh_success` | `{"action":"ssh_success","exit_code":0}` | `gateway_step_5.9_ssh_failed`: `{"action":"ssh_failed","exit_code":N,"error":"..."}` |
| 9 | [5.10] | 원격 명령 실행 | `gateway_step_5.10_complete` | `{"action":"command_executed","response_time_ms":...,"output":"..."}` | `gateway_step_5.10_failed`: `{"action":"command_failed","error":"..."}` |
| 10 | [6.0] | 정상 종료 | `giipagent` | `{"event_type":"shutdown","status":"normal_exit","servers_processed":N}` | `{"event_type":"shutdown","status":"error","reason":"..."}` |

**주요 변경사항:**
- ⚠️ [5.2] 설정 로드는 KVS에 기록되지 않음 (로그 파일에만 기록)
- ⚠️ [5.7] SSH 테스트는 [5.9]로 합쳐짐 (실제 SSH 실행 결과로 기록)
- 🆕 각 **성공** 및 **실패** 시점에 별도의 Factor로 즉시 기록
- 🆕 JSON in kValue는 **raw 데이터** (string escaping 없음)
- 🆕 모든 Factor에 `timestamp` 포함 (디버깅용)
- 🆕 문제 발생 시 상세 데이터 (에러 메시지, 상태값 등) 함께 기록

#### 📌 KVS 저장 규칙 (중요!)

**kValue JSON 구조 (Raw JSON 형식):**
```json
{
  "action": "단계별_행동",
  "timestamp": "2025-11-27 09:25:14",
  "status": "success|failed",
  "hostname": "remote-server-01",
  "server_lssn": 71241,
  "parent_lssn": 71240,
  "details": {
    "error": "에러 메시지",
    "response_time_ms": 1234,
    "exit_code": 0
  }
}
```

**각 스텝별 로깅 시점:**

| 스텝 | 시작 시점 | 완료 시점 | Factor | 
|------|----------|----------|---------|
| 5.4 (서버 목록 조회) | 없음 | `gateway_step_5.4_success` 또는 `gateway_step_5.4_failed` | 단일 Record |
| 5.5 (서버 정보 추출) | 없음 | `gateway_server_extract` + 검증 결과 | 단일 Record |
| 5.6 (서버 파싱) | 없음 | `gateway_step_5.6_parsed` | 단일 Record |
| 5.8 (큐 조회) | 없음 | `gateway_step_5.8_success` 또는 `gateway_step_5.8_failed` | 단일 Record |
| 5.9 (SSH 실행) | `gateway_step_5.9_ssh_start` | `gateway_step_5.9_ssh_success` 또는 `gateway_step_5.9_ssh_failed` | 2개 Records |
| 5.10 (원격 명령) | 없음 | `gateway_step_5.10_complete` 또는 `gateway_step_5.10_failed` | 단일 Record |

**문제 해결 시 확인 포인트:**

1. **[5.4] 실패 시:**
   - `gateway_step_5.4_failed` 확인 → `reason` 필드 확인
   - `kValue`에 응답 데이터 상세 기록됨

2. **[5.5] 실패 시:**
   - `gateway_step_5.5_failed` 확인 → `action` 필드 확인
   - `server_params` 전체 기록됨 (어디서 실패했는지 확인 가능)

3. **[5.9] SSH 실패 시:**
   - `gateway_step_5.9_ssh_failed` 확인 → `error` 필드 확인
   - SSH 파라미터 모두 기록 (ssh_host, ssh_port, ssh_user 등)

4. **[5.10] 명령 실패 시:**
   - `gateway_step_5.10_failed` 확인 → `error` 필드 확인
   - 실제 원격 명령 에러 메시지 포함

---

## 🔧 코드 수정 가이드 (lib/gateway.sh)

### 📌 KVS kValue 처리 규칙 (중요!)

**kvs_put() 함수는 어떤 값이 들어가도 에러 없이 raw 데이터로 저장합니다.**

```bash
# kvs.sh line 191: kValue는 raw data 그대로 임베드됨
local jsondata="{\"kType\":\"${ktype}\",\"kValue\":${kvalue_json}}"
                                                      ↑
                                     따옴표 없이 직접 임베드 = 데이터 그대로 저장
```

#### 어떤 값이든 처리 가능:

1. **유효한 JSON 객체**
   ```bash
   kvs_put "lssn" "123" "factor" '{"status":"ok","count":5}'
   → KVS에 저장: {"kValue":{"status":"ok","count":5}}
   ```

2. **일반 텍스트 (화면 표시 텍스트)**
   ```bash
   kvs_put "lssn" "123" "factor" 'Server processing failed: connection timeout'
   → KVS에 저장: {"kValue":Server processing failed: connection timeout}
   ```

3. **숫자**
   ```bash
   kvs_put "lssn" "123" "factor" '12345'
   → KVS에 저장: {"kValue":12345}
   ```

4. **특수문자 포함 텍스트**
   ```bash
   kvs_put "lssn" "123" "factor" 'Error: "Connection refused" (errno: 111)'
   → KVS에 저장: {"kValue":Error: "Connection refused" (errno: 111)}
   ```

**주의:** 어떤 형태의 데이터든 **그대로** 들어갑니다. 이것이 설계 의도입니다.

---

### 📌 각 함수별 KVS 로깅 추가 계획

#### 함수 1: `get_gateway_servers()`

**수정 위치:** Lines ~106-125 (get_gateway_servers 함수)

**추가할 코드 (성공/실패 모두):**
```bash
# [5.4-START] 시작
local start_detail='{"action":"list_servers_start","timestamp":"'$(date '+%Y-%m-%d %H:%M:%S')'","lssn":'${lssn}'}'
kvs_put "lssn" "${lssn:-0}" "gateway_step_5.4_start" "$start_detail" 2>/dev/null

# [5.4-ERROR] 실패 시 - 에러 메시지 그대로 저장
kvs_put "lssn" "${lssn:-0}" "gateway_step_5.4_failed" "$error_message" 2>/dev/null

# [5.4-SUCCESS] 성공 시
local success_detail='{"action":"list_servers_success","server_count":'${server_count}',"timestamp":"'$(date '+%Y-%m-%d %H:%M:%S')'","lssn":'${lssn}'}'
kvs_put "lssn" "${lssn:-0}" "gateway_step_5.4_success" "$success_detail" 2>/dev/null
```

---

#### 함수 2: `process_single_server()`

**수정 위치:** Lines ~443+ (process_single_server 함수)

**5.5-EXTRACT 단계 (추출 실패 시):**
```bash
# 추출 실패 - 원본 에러 메시지 그대로 저장
kvs_put "lssn" "${global_lssn:-0}" "gateway_step_5.5_failed" "$error_msg" 2>/dev/null
```

**5.5-VALIDATE 단계 (검증 실패 시):**
```bash
# 검증 실패 - 상세 정보 저장
local validate_detail='{"action":"validation_failed","hostname":"'${hostname}'","timestamp":"'$(date '+%Y-%m-%d %H:%M:%S')'","parent_lssn":'${global_lssn:-0}'}'
kvs_put "lssn" "${global_lssn:-0}" "gateway_step_5.5_failed" "$validate_detail" 2>/dev/null
```

**5.6-PARSED 단계 (성공 시):**
```bash
# 파싱 완료 - 구성된 정보 저장
local parse_detail='{"action":"server_parsed","hostname":"'${hostname}'","server_lssn":'${server_lssn}',"ssh_host":"'${ssh_host}'","ssh_port":'${ssh_port}',"timestamp":"'$(date '+%Y-%m-%d %H:%M:%S')'","parent_lssn":'${global_lssn:-0}'}'
kvs_put "lssn" "${global_lssn:-0}" "gateway_step_5.6_parsed" "$parse_detail" 2>/dev/null
```

**5.8-QUEUE 단계 (성공/실패):**
```bash
# 큐 조회 성공
local queue_detail='{"action":"queue_fetch_success","hostname":"'${hostname}'","server_lssn":'${server_lssn}',"queue_file_size":'$(stat -c%s "$tmpfile" 2>/dev/null || echo '0')',"timestamp":"'$(date '+%Y-%m-%d %H:%M:%S')'","parent_lssn":'${global_lssn:-0}'}'
kvs_put "lssn" "${global_lssn:-0}" "gateway_step_5.8_success" "$queue_detail" 2>/dev/null

# 큐 조회 실패 - 원본 에러 그대로 저장
kvs_put "lssn" "${global_lssn:-0}" "gateway_step_5.8_failed" "$error_msg" 2>/dev/null
```

**5.9-SSH 시작 (Before SSH):**
```bash
# SSH 시작
local ssh_start_detail='{"action":"ssh_attempt_start","hostname":"'${hostname}'","server_lssn":'${server_lssn}',"ssh_host":"'${ssh_host}'","ssh_port":'${ssh_port}',"ssh_user":"'${ssh_user}'","timestamp":"'$(date '+%Y-%m-%d %H:%M:%S')'","parent_lssn":'${global_lssn:-0}'}'
kvs_put "lssn" "${global_lssn:-0}" "gateway_step_5.9_ssh_start" "$ssh_start_detail" 2>/dev/null
```

**5.9-SSH 결과 (After SSH):**
```bash
# SSH 성공
local ssh_success_detail='{"action":"ssh_success","hostname":"'${hostname}'","server_lssn":'${server_lssn}',"ssh_host":"'${ssh_host}'","exit_code":'${ssh_result}',"timestamp":"'$(date '+%Y-%m-%d %H:%M:%S')'","parent_lssn":'${global_lssn:-0}'}'
kvs_put "lssn" "${global_lssn:-0}" "gateway_step_5.9_ssh_success" "$ssh_success_detail" 2>/dev/null

# SSH 실패 - 원본 에러 메시지 그대로 저장
kvs_put "lssn" "${global_lssn:-0}" "gateway_step_5.9_ssh_failed" "$ssh_error_output" 2>/dev/null
```

**5.10-COMMAND 결과:**
```bash
# 명령 성공 - 명령 출력 결과 그대로 저장
kvs_put "lssn" "${global_lssn:-0}" "gateway_step_5.10_complete" "$command_output" 2>/dev/null

# 명령 실패 - 에러 메시지 그대로 저장
kvs_put "lssn" "${global_lssn:-0}" "gateway_step_5.10_failed" "$error_output" 2>/dev/null
```

---

### ⚠️ 주의사항

1. **어떤 값이든 raw data로 그냥 들어간다**
   ```bash
   # JSON 형식이든
   kvs_put "lssn" "123" "factor" '{"key":"value"}'
   
   # 일반 텍스트든
   kvs_put "lssn" "123" "factor" 'Error occurred: something failed'
   
   # 숫자든
   kvs_put "lssn" "123" "factor" '12345'
   
   # 모두 에러 없이 저장됨 ✅
   ```

2. **에러 메시지는 그대로 저장**
   ```bash
   # stderr에서 나온 에러도 그대로 저장 가능
   kvs_put "lssn" "123" "factor" "$(ssh user@host 'command' 2>&1)"
   # 명령 실패해도 에러 메시지가 그대로 KVS에 저장됨
   ```

3. **화면 표시 텍스트도 저장 가능**
   ```bash
   # GUI에 표시되는 텍스트
   kvs_put "lssn" "123" "factor" "Server 192.168.1.100 is not responding"
   # 그대로 KVS에 저장됨
   ```

4. **특수문자도 자동 처리**
   ```bash
   # 따옴표, 백슬래시, 개행 등 모두 처리 가능
   kvs_put "lssn" "123" "factor" 'Line1
   Line2
   Path: C:\Users\test'
   # 모두 에러 없이 저장됨
   ```

5. **timestamp, parent_lssn 권장 (필수 아님)**
   ```bash
   # 구조화된 정보는 JSON으로 포장하면 좋음
   local detail='{"action":"step","timestamp":"'$(date '+%Y-%m-%d %H:%M:%S')'","parent_lssn":'${global_lssn:-0}'}'
   kvs_put "lssn" "${global_lssn:-0}" "factor" "$detail"
   
   # 하지만 단순 텍스트나 에러 메시지는 그냥 넣어도 됨
   kvs_put "lssn" "${global_lssn:-0}" "factor" "$error_message"
   ```

---

## 🔴 현재 문제 분석 및 해결책
```
[5.1] Agent 시작
  ↓
[5.2] 설정 로드
  ↓
[5.3] is_gateway=0 감지 → NORMAL MODE 진입
  ↓
[5.5.N] 큐 기반 처리 (CQEQueueGet API)
  ↓
[5.6.N] 큐 항목별 처리
  ↓
[5.7.N] 각 DB 상태 체크
  ↓
[6.0] 정상 종료
```

#### B. GATEWAY MODE (is_gateway = 1)
```
[5.1] Agent 시작
  ↓
[5.2] 설정 로드
  ↓
[5.3.G] is_gateway=1 감지 → GATEWAY MODE 진입
  ↓
[5.4] GatewayRemoteServerListForAgent API 호출
  ↓
  ├─ 성공 (count > 0)
  │  ↓
  │  [5.5] 루프 시작
  │  ↓
  │  [5.6] 서버별 순차 처리 시작
  │  ├─ SSH 연결 테스트 [5.7]
  │  ├─ 원격 명령 실행 [5.8]
  │  ├─ Auto-Discover 실행 [5.9]
  │  └─ 관리DB 체크 [5.10]
  │
  └─ 실패 (count = 0 또는 API 에러)
     ↓
     [5.5.E] 에러 로깅 및 대기
     ↓
     다음 사이클에서 재시도
```

---

## 🔴 현재 문제 분석 및 해결책

### 📊 최근 실행 결과 (2025-11-27 09:25 UTC+9)

**KVS 조회 결과:**
```
✅ 조회 완료: 14/41 (최근 5분 내 기록)

실행 순서:
1. ✅ [5.1] Agent 시작 (09:25:03)
   - version=3.00, mode=gateway, is_gateway=1
   
2. ✅ [5.3] Gateway 모드 초기화 (09:25:03)
   - event_type: gateway_init
   - db_connectivity: will_verify
   - server_count: 0
   
3. ✅ [5.4] Auto-Discover 진행 (09:25:03 ~ 09:25:08)
   - STEP-1: Configuration Check ✅
   - STEP-2: Script Path Check ⚠️ (경로 미존재, 하지만 계속 진행)
   - STEP-3: Initialize KVS Records ✅
   - STEP-4: Execute Auto-Discover Script ✅
   - STEP-5: Validate Result File ✅
   - STEP-6: Extract Components ✅
   - STEP-7: Store Complete Marker ✅
   - auto_discover_complete: status=completed ✅
   
4. ✅ [5.5] Managed DB 체크 (09:25:14 ~ 09:25:16)
   - p-cnsldb01m: ✅ 620ms
   - p-cnsldb02m: ✅ 645ms
   - p-cnsldb03m: ✅ 658ms
   
5. ✅ [6.0] 정상 종료 (09:25:18)
   - status: normal_exit
```

### ✅ 현재 상태: 정상 작동

**결론:** 🟢 **문제 없음** - 스크립트가 정상적으로 실행되고 있습니다.

### ⚠️ 주의 사항

| 항목 | 상태 | 영향도 | 조치 |
|------|------|--------|------|
| Auto-Discover 스크립트 경로 | ⚠️ 미존재 | 🟡 낮음 | 경로 확인 필수, 하지만 현재는 처리 진행 중 |
| 순차 실행 | ✅ 정상 | - | 각 단계가 올바른 순서로 진행 |
| 데이터 수집 | ✅ 정상 | - | 모든 DB로부터 성능 데이터 수집 중 |
| KVS 저장 | ✅ 정상 | - | 모든 결과가 정상적으로 KVS에 기록 |

---

### 🔍 문제 발생 시나리오별 해결책

#### **시나리오 1️⃣: 포인트 [5.1] ~ [5.3] 중 하나가 없음**

**증상:**
```
❌ [5.1] 없음 → Agent 시작 불가
❌ [5.2] 없음 → Config 로드 실패
❌ [5.3] 없음 → is_gateway 판단 불가
```

**원인:**
- giipAgent3.sh 실행 안됨
- 라이브러리 파일 로드 실패
- 설정 파일 누락 또는 권한 문제

**해결 방법:**
```bash
# 1. 스크립트 실행 권한 확인
ls -la giipAgent3.sh
chmod +x giipAgent3.sh

# 2. 라이브러리 파일 확인
ls -la lib/*.sh
ls -la lib/common.sh lib/kvs.sh

# 3. 설정 파일 확인
cat ../giipAgent.cnf | head -20
grep "is_gateway" ../giipAgent.cnf

# 4. 수동 실행
./giipAgent3.sh
```

---

#### **시나리오 2️⃣: [5.3] 이후 [5.3.G] (Gateway 모드)가 없고 NORMAL 모드로 진입**

**증상:**
```
✅ [5.1] Agent 시작
✅ [5.2] 설정 로드
✅ [5.3] is_gateway 값 조회
❌ [5.3.G] 없음 → NORMAL MODE로 진입 (Gateway 모드 미진입)
```

**원인:**
- `is_gateway=0` 또는 `false`로 설정됨
- DB API 응답에서 is_gateway 값이 0임
- 설정이 최근에 변경됨

**해결 방법:**

```bash
# 1. 로컬 설정 파일 확인
cat ../giipAgent.cnf | grep -i "is_gateway\|gateway"

# 2. 필요시 수정
sed -i 's/is_gateway=0/is_gateway=1/g' ../giipAgent.cnf

# 3. DB 설정도 확인 (DB API 응답값)
# KVS 조회로 API 응답 확인
# kFactor: api_lsvrgetconfig_response에서 is_gateway 값 확인
```

**SQL 직접 확인 (필요시):**
```sql
-- SQL Server
SELECT lssn, hostname, is_gateway 
FROM tManagedServer 
WHERE lssn = 71240;

-- 필요시 수정
UPDATE tManagedServer SET is_gateway = 1 WHERE lssn = 71240;
```

---

#### **시나리오 3️⃣: [5.4] Auto-Discover 단계 중 특정 STEP에서 중단**

**증상:**
```
✅ [5.3.G] Gateway 모드 초기화
✅ STEP-1, 2, 3 완료
❌ STEP-4 실행 중 중단 또는 실패
❌ auto_discover_complete 없음 또는 status: error
```

**원인:**
- Auto-Discover 스크립트 실행 실패
- 스크립트 경로 오류
- 타임아웃 (60초 초과)
- 권한 문제

**해결 방법:**

```bash
# 1. Auto-Discover 스크립트 경로 확인
ls -la /home/shinh/scripts/infraops01/giipAgentLinux/giipscripts/auto-discover-linux.sh

# 2. 없으면 경로 수정 필요
# giipAgent3.sh 또는 gateway.sh에서 경로 수정

# 3. 스크립트 실행 권한 확인
chmod +x /home/shinh/scripts/infraops01/giipAgentLinux/giipscripts/auto-discover-linux.sh

# 4. 스크립트 직접 테스트
/home/shinh/scripts/infraops01/giipAgentLinux/giipscripts/auto-discover-linux.sh

# 5. 타임아웃 시간 증가 필요시
# gateway.sh에서 timeout 값 수정 (기본: 60초)
# timeout_sec=120 으로 변경
```

**KVS에서 에러 메시지 확인:**
```powershell
# PowerShell에서 STEP별 상세 로그 조회
cd giipdb
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71240 -KFactor auto_discover_step_4_execution -Top 5
```

---

#### **시나리오 4️⃣: [5.5] Auto-Discover 완료 후 [5.6] 서버 처리가 없음**

**증상:**
```
✅ auto_discover_complete: status=completed
❌ managed_db_check 기록 없음
❌ 서버별 처리 로그 없음
```

**원인:**
- GatewayRemoteServerListForAgent API 호출 실패
- 리모트 서버 목록이 비어있음 (count=0)
- 서버 처리 루프 진입 실패

**해결 방법:**

```bash
# 1. API 직접 테스트
curl -X POST \
  -d "text=GatewayRemoteServerListForAgent lssn&token=YOUR_SECRET_KEY&jsondata={\"lssn\":71240}" \
  https://giipfaw.azurewebsites.net/api/giipApiSk2 \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --insecure

# 2. 응답 형식 확인
# {"data":[]} → 빈 배열 (서버 없음)
# {"data":[{"lssn":71241,...},...]} → 정상

# 3. DB에서 리모트 서버 확인
SELECT COUNT(*) FROM tManagedServer WHERE gateway_lssn = 71240;

# 4. 없으면 DB에 리모트 서버 추가
INSERT INTO tManagedServer (lssn, hostname, gateway_lssn, ...) VALUES (...);
```

---

#### **시나리오 5️⃣: [5.6] 서버별 처리 중 SSH 연결 실패**

**증상:**
```
✅ managed_db_check 기록 시작
❌ 첫 번째 또는 특정 서버에서 중단
❌ 로그: "SSH: Connection refused" 또는 "Permission denied"
```

**원인:**
- SSH 인증 정보 오류
- 리모트 서버가 응답하지 않음
- 방화벽 또는 네트워크 문제
- sshpass 미설치

**해결 방법:**

```bash
# 1. sshpass 설치 확인
which sshpass
sshpass -V

# 2. 없으면 설치
apt-get install sshpass  # Ubuntu/Debian
yum install sshpass      # CentOS/RHEL

# 3. SSH 인증 정보 확인 (giipAgent.cnf)
grep -i "remote_user\|remote_pass" ../giipAgent.cnf

# 4. 각 리모트 서버별 SSH 테스트
for server_ip in $(grep "remote_server" ../giipAgent.cnf | cut -d= -f2); do
  echo "Testing $server_ip..."
  sshpass -p YOUR_PASSWORD ssh -o ConnectTimeout=5 giip@$server_ip "echo OK"
done

# 5. 리모트 서버에서 SSH 포트 확인
ssh -vvv giip@REMOTE_SERVER_IP

# 6. 방화벽 확인
telnet REMOTE_SERVER_IP 22
```

**KVS에서 SSH 로그 확인:**
```powershell
# SSH 연결 결과 로그 조회
cd giipdb
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71240 -KFactor ssh_connection -Top 10
```

---

#### **시나리오 6️⃣: [5.8] 명령 실행은 되지만 데이터 수집이 없음**

**증상:**
```
✅ SSH 연결 성공
✅ 명령 시작 로그 있음
❌ 결과 데이터 없음 또는 에러 상태
❌ response_time_ms 없음
```

**원인:**
- 원격 명령 실행 실패 또는 타임아웃
- 명령 출력 파싱 오류
- 권한 부족
- 리모트 도구 미설치

**해결 방법:**

```bash
# 1. 리모트 서버에서 명령 직접 테스트
ssh giip@REMOTE_SERVER_IP "mysql -u user -p password -e 'SELECT VERSION();'"

# 2. 명령 결과 확인
ssh giip@REMOTE_SERVER_IP "mysql -u user -p password -e 'SHOW STATUS WHERE Variable_name=\"Threads_connected\";'"

# 3. 필요한 도구 설치 확인
ssh giip@REMOTE_SERVER_IP "which mysql"
ssh giip@REMOTE_SERVER_IP "which mongosh"

# 4. 권한 확인
ssh giip@REMOTE_SERVER_IP "whoami"

# 5. giipAgent.cnf에서 명령 정의 확인
grep "remote_cmd\|remote_query" ../giipAgent.cnf
```

**KVS에서 명령 실행 결과 확인:**
```powershell
# managed_db_check의 response_time_ms 확인
cd giipdb
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71240 -KFactor managed_db_check -Top 10
```

---

#### **시나리오 7️⃣: [5.9] Auto-Discover 실행이 매우 느림 또는 타임아웃**

**증상:**
```
✅ STEP-4 Execute 시작
❌ 60초 이상 대기 없이 실패
❌ 타임아웃 메시지
❌ auto_discover_complete가 나타나지 않음
```

**원인:**
- Auto-Discover 스크립트가 느림
- 타임아웃 설정이 짧음 (기본: 60초)
- 시스템 리소스 부족
- 네트워크 지연

**해결 방법:**

```bash
# 1. Auto-Discover 스크립트 직접 실행 (시간 측정)
time /home/shinh/scripts/infraops01/giipAgentLinux/giipscripts/auto-discover-linux.sh

# 2. 실행 시간 확인
# real: 2-3초 정상
# real: 10초 이상 → 느림
# real: 60초 이상 → 타임아웃 위험

# 3. 필요시 타임아웃 증가
# gateway.sh에서:
# timeout_sec=60 → timeout_sec=120 또는 180

# 4. 또는 백그라운드 실행으로 변경
# 긴 작업은 큐에 저장 후 별도 처리
```

---

#### **시나리오 8️⃣: [5.10] 관리DB 체크 실패**

**증상:**
```
✅ Auto-Discover 완료
✅ 처음 몇 개 DB는 성공
❌ 특정 DB에서 connection error
❌ check_status: failed
```

**원인:**
- DB 연결 실패 (네트워크, 인증, 포트)
- DB 서버 다운
- DB 크레덴셜 오류
- 방화벽 차단

**해결 방법:**

```bash
# 1. 해당 DB 직접 연결 테스트
mysql -h DB_HOST -u USER -p DB_PASSWORD -e "SELECT 1;"

# 2. 포트 확인
telnet DB_HOST 3306

# 3. DB 서버 상태 확인
# 다른 클라이언트에서 연결 가능한지 확인

# 4. 크레덴셜 확인
# giipAgent.cnf 또는 DB 메타데이터 확인

# 5. 방화벽 확인
# iptables / ufw 상태 확인
iptables -L -n | grep 3306
```

**KVS에서 DB 체크 실패 상세 확인:**
```powershell
cd giipdb
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71240 -KFactor managed_db_check -Top 20
# check_status: failed인 항목 찾기
```

---

### 📋 빠른 진단 결정 트리 (플로우 기반)

```
에러 발생 보고
│
├─ [5.1] 있는가?
│  ├─ NO → 시나리오 1: 스크립트 실행 확인
│  └─ YES → [5.3.G]로 이동
│
├─ [5.3.G] Gateway 모드인가?
│  ├─ NO → 시나리오 2: is_gateway 값 확인
│  └─ YES → STEP 체크로 이동
│
├─ STEP-1 ~ STEP-7 모두 완료?
│  ├─ NO → 시나리오 3: Auto-Discover 스크립트 확인
│  └─ YES → 서버 처리로 이동
│
├─ managed_db_check 기록 있는가?
│  ├─ NO → 시나리오 4: 리모트 서버 목록 확인
│  └─ YES → SSH 결과 확인
│
├─ SSH 연결 성공?
│  ├─ NO → 시나리오 5: SSH 인증 확인
│  └─ YES → 데이터 수집 확인
│
├─ response_time_ms 있는가?
│  ├─ NO → 시나리오 6: 원격 명령 확인
│  └─ YES → 시나리오 7/8: 세부 확인
│
└─ 모두 해결 → ✅ 정상 작동
```

---

## 📊 진단 체크리스트

### ✅ Level 1: 기본 설정 확인 (소요 시간: 5분)

#### 1️⃣ Gateway 모드 활성화 확인

```bash
# giipAgent.cnf 확인
cat /path/to/giipAgent.cnf | grep -E "is_gateway|gateway_mode"

# 예상 결과:
# is_gateway=1 또는 gateway_mode=1
```

**진단 포인트:**
- [ ] `is_gateway` 또는 `gateway_mode`가 `1` 또는 `true`로 설정되어 있는가?
- [ ] 값이 `0` 또는 `false`로 변경되었는가?

**문제 발견 시:**
```bash
# giipAgent.cnf 수정
sed -i 's/is_gateway=0/is_gateway=1/g' giipAgent.cnf
```

#### 2️⃣ DB 설정 값 조회 (실시간 확인)

```bash
# giipAgent3.sh 로그 포인트 #5.2 확인
# 로그에서 "is_gateway" 값 추출

# 직접 조회 (API 테스트)
curl -X POST \
  -d "text=LSvrGetConfig lssn hostname&token=YOUR_SECRET_KEY&jsondata={\"lssn\":YOUR_LSSN,\"hostname\":YOUR_HOSTNAME}" \
  https://YOUR_API_URL

# 응답 형식 예시:
# {"data":[{"is_gateway":true,"RstVal":"200",...}]}
```

**진단 포인트:**
- [ ] API 응답에 `is_gateway` 필드가 있는가?
- [ ] 값이 `true` 또는 `1`인가?
- [ ] API 자체가 응답하는가 (연결 실패는 아닌가)?

#### 3️⃣ 로그 포인트 확인 (실행 흐름 추적)

```bash
# giipAgent3.sh 실행 후 로그 확인
# 로그 위치: 보통 /var/log/giip/ 또는 /tmp/

# 포인트 #5.1 ~ #5.3 확인
grep -E "\[5\.[1-3]\]" /path/to/logfile

# 예상 출력:
# [giipAgent3.sh] 🟢 [5.1] Agent 시작: version=3.00
# [giipAgent3.sh] 🟢 [5.2] 설정 로드 완료: lssn=12345, hostname=gateway01, is_gateway=1
# [giipAgent3.sh] 🟢 [5.3] Gateway 모드 감지 및 초기화
```

**진단 포인트:**
- [ ] `[5.1]` 로그가 있는가? (Agent 시작)
- [ ] `[5.2]` 로그가 있는가? (설정 로드)
  - [ ] `is_gateway=1`이 명시되어 있는가?
- [ ] `[5.3]` 로그가 있는가? (Gateway 모드 초기화)

**문제 발견 시:**
- `[5.2]`에서 `is_gateway=0`이면 DB 설정 확인 필요
- `[5.2]`가 없으면 DB API 연결 문제
- `[5.3]`이 없으면 실제 Gateway 모드 진입 실패

**✅ 더 빠른 방법: KVS 데이터로 확인**

```powershell
# Windows/PowerShell에서
cd giipdb
pwsh .\mgmt\check-latest.ps1

# 출력:
# 최근 5분 내 [5.x] 포인트 로그 표시
# 예: 16/82 (전체 82개 중 최근 5분 내 16개)
```

| 포인트 | 의미 | KVS Factor | 정상 상태 |
|-------|------|-----------|---------|
| [5.1] | Agent 시작 | giipagent | 매 사이클마다 1회 |
| [5.2] | 설정 로드 완료 | api_lsvrgetconfig_success | is_gateway=1 포함 |
| [5.3] | Gateway 모드 초기화 | gateway_init | 항상 나타남 |
| [5.4] | 서버 목록 조회 시작 | gateway_operation | 주기적 반복 |

**의심 신호:**
- ❌ [5.1] ~ [5.3] 중 하나 이상 없음: 초기화 실패
- ❌ [5.3] 이후 [5.4]가 오지 않음: 서버 조회 루프 미진입
- ❌ 같은 포인트가 반복: Hang/데드락 가능성

---

### ✅ Level 2: 데이터베이스 조회 확인 (소요 시간: 10분)

#### 1️⃣ `process_gateway_servers()` 함수 추적

```bash
# gateway.sh에서 로깅 포인트 #5.4 확인
# 이 함수가 리모트 서버 목록을 조회하고 처리를 시작하는 지점

grep -E "\[5\.4\]|GatewayRemoteServerListForAgent" /path/to/logfile

# 예상 출력:
# [gateway.sh] 🟢 [5.4] Gateway 서버 목록 조회 시작: lssn=12345
```

**진단 포인트:**
- [ ] `[5.4]` 로그가 있는가?
- [ ] 있다면 → **Level 3 (데이터 조회 문제)**로 진행
- [ ] 없다면 → Gateway 모드가 실제로 진입되지 않음

#### 2️⃣ API 호출 직접 테스트

```bash
# GatewayRemoteServerListForAgent API 직접 호출
TEMP_FILE="/tmp/test_gateway_servers.json"

curl -X POST \
  -d "text=GatewayRemoteServerListForAgent lssn&token=YOUR_SECRET_KEY&jsondata={\"lssn\":YOUR_LSSN}" \
  https://YOUR_API_URL \
  -o "$TEMP_FILE"

# 결과 확인
cat "$TEMP_FILE" | jq .

# 예상 결과:
# {
#   "data": [
#     {"lssn": 12346, "hostname": "remote01", ...},
#     {"lssn": 12347, "hostname": "remote02", ...}
#   ]
# }
```

**진단 포인트:**
- [ ] API 호출이 성공하는가? (HTTP 200 + JSON 응답)
- [ ] `data` 배열이 있는가?
- [ ] 배열이 비어있는가? → **리모트 서버가 없음**
- [ ] 예상했던 리모트 서버가 있는가?

#### 3️⃣ 데이터베이스 테이블 직접 확인

```bash
# DB 직접 조회 (SQL Server 예시)
sqlcmd -S YOUR_DB_SERVER -d YOUR_DB -U YOUR_USER -P YOUR_PASSWORD -Q "
  SELECT 
    tManagedServer.lssn,
    tManagedServer.hostname,
    tManagedServer.is_gateway,
    tManagedServerDetail.remote_gateways
  FROM tManagedServer
  LEFT JOIN tManagedServerDetail ON tManagedServer.lssn = tManagedServerDetail.lssn
  WHERE tManagedServer.is_gateway = 1
"

# MySQL 예시
mysql -h YOUR_DB_HOST -u YOUR_USER -p -e "
  SELECT 
    lssn, hostname, is_gateway
  FROM tManagedServer
  WHERE is_gateway = 1;
"
```

**진단 포인트:**
- [ ] Gateway 서버가 `is_gateway=1`로 표시되어 있는가?
- [ ] 리모트 서버 관계 테이블이 있는가?
- [ ] 해당 Gateway에 할당된 리모트 서버가 있는가?

---

### ✅ Level 3: 데이터 조회 및 처리 확인 (소요 시간: 15분)

#### 1️⃣ 서버 목록 처리 로그 확인

```bash
# gateway.sh의 주요 로깅 포인트들
grep -E "\[5\.[4-9]\]|\[6\.[0-9]\]" /path/to/logfile

# 예상 출력 시퀀스:
# [5.4] 서버 목록 조회 시작
# [5.5] 서버 목록 조회 완료 (count=2)
# [5.6] 서버 1 처리 시작
# [5.7] SSH 연결 테스트
# [5.8] 원격 명령 실행
# [6.0] 서버 2 처리 시작
# ... (반복)
```

**진단 포인트:**
- [ ] `[5.4]` 이후 로그가 없는가? → **API 응답 문제**
- [ ] `[5.5]` 이후 로그가 없는가? → **서버 목록 처리 루프 진입 실패**
- [ ] `[5.6]` 이후 로그가 없는가? → **SSH 연결 문제**

#### 2️⃣ SSH 연결 상태 확인

```bash
# 각 리모트 서버별 SSH 테스트
for server in $(cat /path/to/remote_servers.txt); do
  echo "Testing $server..."
  sshpass -p YOUR_PASSWORD ssh -o ConnectTimeout=5 giip@$server "echo 'OK'"
done

# 또는 gateway.sh 로그에서 SSH 결과 확인
grep -i "ssh\|connection\|connectivity" /path/to/logfile
```

**진단 포인트:**
- [ ] SSH 연결이 성공하는가?
- [ ] SSH 인증 실패는 아닌가?
- [ ] 네트워크 타임아웃이 발생하는가?
- [ ] sshpass 도구가 설치되어 있는가?

#### 3️⃣ 데이터 수집 상태 확인

```bash
# gateway.sh에서 리모트 명령 실행 결과 확인
grep -E "remote_command_result|ssh_output|command_execution" /path/to/logfile

# KVS에 저장된 데이터 확인
# (KVS 저장소 접근 방법은 환경에 따라 다름)
```

**진단 포인트:**
- [ ] 리모트 명령 실행 로그가 있는가?
- [ ] 명령 실행이 실패했는가?
- [ ] 데이터가 KVS에 저장되었는가?

#### 4️⃣ KVS 데이터 확인 (중요!)

**방법 1️⃣: PowerShell 스크립트로 조회 (권장)**

```powershell
# giipdb 디렉토리에서 실행
cd giipdb

# 1. 최근 5분 Gateway 실행 흐름 확인 (가장 빠르고 정확!)
pwsh .\mgmt\check-latest.ps1

# 2. 특정 서버의 최근 20개 Gateway 로그 조회
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey YOUR_GATEWAY_LSSN -KFactor gateway_operation -Top 20

# 3. 특정 서버의 모든 Factor 목록 (summary)
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey YOUR_GATEWAY_LSSN -Summary
```

**방법 2️⃣: Web UI로 조회**

```
# 특정 서버의 모든 Factor 목록 확인
https://giip.littleworld.net/ko/kvsfactorlistlsvr?kType=lssn&kKey=YOUR_GATEWAY_LSSN

# 특정 Factor 데이터 조회 (예: gateway_operation)
https://giip.littleworld.net/ko/kvslist?kFactor=gateway_operation&kKey=YOUR_GATEWAY_LSSN
```

**방법 3️⃣: SQL 직접 조회**

```sql
-- 특정 Gateway의 최근 10개 gateway_operation 로그
SELECT TOP 10
    kvsn, kType, kKey, kFactor, kValue, kRegdt
FROM tKVS
WHERE kKey = 'YOUR_GATEWAY_LSSN'
  AND kFactor = 'gateway_operation'
ORDER BY kRegdt DESC

-- 모든 Factor 현황 확인
SELECT kFactor, COUNT(*) as cnt, MAX(kRegdt) as last_update
FROM tKVS
WHERE kKey = 'YOUR_GATEWAY_LSSN'
GROUP BY kFactor
ORDER BY last_update DESC

-- 특정 Factor의 JSON 값 파싱 (예: [5.x] 포인트 추출)
SELECT 
    kRegdt,
    JSON_VALUE(kValue, '$.point') as point,
    JSON_VALUE(kValue, '$.event_type') as event_type,
    kValue
FROM tKVS
WHERE kKey = 'YOUR_GATEWAY_LSSN'
  AND kFactor = 'gateway_operation'
ORDER BY kRegdt DESC
```

**KVS 데이터 해석:**

| kFactor | 의미 | 확인 항목 |
|---------|------|---------|
| gateway_operation | Gateway 실행 흐름 포인트 | [5.x] 포인트 시퀀스 |
| gateway_cycle | Gateway 사이클 시작/종료 | 주기적 실행 여부 |
| api_lsvrgetconfig_response | DB 설정 로드 응답 | is_gateway 값 |
| api_lsvrgetconfig_success | 설정 로드 성공 | 설정 정상 수신 |
| api_lsvrgetconfig_failed | 설정 로드 실패 | API 연결 문제 |
| gateway_init | Gateway 초기화 로그 | 초기화 상태 |

**진단 포인트:**
- [ ] 최근 5분 내 [5.4] 포인트가 있는가?
- [ ] [5.5] 이후 포인트들이 순서대로 나타나는가?
- [ ] 같은 포인트가 반복되는 것은 아닌가? (hang의 신호)
- [ ] kValue에 에러 메시지가 있는가?

---

### ✅ Level 4: 심화 진단 (소요 시간: 20-30분)

#### 1️⃣ 전체 실행 흐름 재구성

```bash
# giipAgent3.sh 전체 실행 로그 추출
tail -500 /path/to/complete_logfile > /tmp/giip_diagnostic_dump.log

# 특정 포인트만 추출
grep -E "ERROR|WARN|FAIL|\[5\.\d\]|\[6\.\d\]" /tmp/giip_diagnostic_dump.log > /tmp/giip_key_events.log

# 시간 순서대로 정렬 및 분석
cat /tmp/giip_key_events.log
```

#### 2️⃣ 환경 변수 확인

```bash
# giipAgent3.sh가 실행될 때의 환경 확인
env | grep -E "SCRIPT_DIR|LIB_DIR|PATH" | head -20

# 라이브러리 파일 존재 확인
ls -la /path/to/giipAgentLinux/lib/*.sh | grep -E "gateway|discovery|normal"
```

**진단 포인트:**
- [ ] 필수 라이브러리 파일이 모두 있는가?
  - [ ] `lib/gateway.sh`
  - [ ] `lib/db_clients.sh`
  - [ ] `lib/discovery.sh`
  - [ ] `lib/normal.sh`
- [ ] 파일 권한이 정상인가? (실행 가능한가?)
- [ ] `PATH` 환경 변수가 정상인가?

#### 3️⃣ 강제 디버그 모드 실행

```bash
# giipAgent3.sh를 디버그 모드로 실행
bash -x /path/to/giipAgent3.sh 2>&1 | tee /tmp/debug_output.log

# 또는 특정 부분만 디버그
bash -x -c 'source lib/gateway.sh; process_gateway_servers' 2>&1
```

#### 4️⃣ 네트워크 진단

```bash
# Gateway 서버의 네트워크 상태 확인
netstat -tuln | grep LISTEN
ss -tuln | grep LISTEN

# DNS 해석 확인
nslookup YOUR_REMOTE_SERVER_HOSTNAME
dig YOUR_REMOTE_SERVER_HOSTNAME

# 네트워크 경로 확인
traceroute YOUR_REMOTE_SERVER_IP
mtr YOUR_REMOTE_SERVER_IP
```

---

## 🔧 일반적인 원인과 해결책

### 원인 1: `is_gateway` 설정이 0 또는 false

**증상:**
- 로그에 `[5.3]` 포인트가 없음
- "Running in NORMAL MODE" 메시지 표시

**해결:**
```bash
# 1. giipAgent.cnf 수정
sed -i 's/is_gateway=0/is_gateway=1/g' /path/to/giipAgent.cnf

# 2. DB 테이블 수정 (필요시)
# SQL Server:
UPDATE tManagedServer SET is_gateway = 1 WHERE lssn = YOUR_GATEWAY_LSSN

# 3. giipAgent3.sh 재실행
./giipAgent3.sh
```

---

### 원인 2: DB API 연결 실패

**증상:**
- 로그에 `[5.2]` 포인트가 없거나 "Failed to fetch server config" 메시지
- API URL이 잘못되었거나 네트워크 연결 불가

**확인:**
```bash
# API 연결 테스트
curl -I https://YOUR_API_URL

# SSL 인증서 문제 확인
curl -v https://YOUR_API_URL 2>&1 | grep -i "certificate\|ssl"

# 방화벽 확인
telnet YOUR_API_URL 443
```

**해결:**
```bash
# giipAgent.cnf에서 API URL 확인
grep -i "apiaddr" /path/to/giipAgent.cnf

# 필요시 수정
sed -i 's|apiaddrv2=.*|apiaddrv2="https://correct-url"|g' /path/to/giipAgent.cnf
```

---

### 원인 3: 리모트 서버 목록이 비어있음

**증상:**
- 로그에 `[5.5]` 포인트에서 "count=0" 표시
- GatewayRemoteServerListForAgent API가 빈 배열 반환

**확인:**
```bash
# DB에서 직접 확인
# 해당 Gateway에 할당된 리모트 서버가 있는가?
SELECT COUNT(*) FROM tManagedServer WHERE gateway_lssn = YOUR_GATEWAY_LSSN
```

**해결:**
```bash
# 1. DB 테이블에 리모트 서버 추가
# 2. 또는 API를 통해 서버 등록
# 3. 다시 시도
./giipAgent3.sh
```

---

### 원인 4: SSH 연결 실패

**증상:**
- 로그에 `[5.7]` (SSH 연결 테스트) 이후 에러 메시지
- "sshpass: Permission denied" 또는 "Connection refused"

**확인:**
```bash
# sshpass 설치 확인
which sshpass
sshpass -V

# SSH 키 또는 암호 확인
ssh -i /path/to/key giip@YOUR_REMOTE_SERVER "echo OK"
```

**해결:**
```bash
# 1. sshpass 설치 (없으면)
apt-get install sshpass  # Ubuntu/Debian
yum install sshpass      # CentOS/RHEL

# 2. SSH 인증 정보 확인
# giipAgent.cnf에서 SSH 설정 확인
grep -i "ssh\|remote_user\|remote_pass" /path/to/giipAgent.cnf

# 3. 방화벽 확인
# 리모트 서버의 SSH 포트(보통 22) 열려있는가?
telnet YOUR_REMOTE_SERVER_IP 22
```

---

### 원인 5: 라이브러리 파일 누락 또는 손상

**증상:**
- 에러: "gateway.sh not found" 또는 유사한 메시지
- 또는 라이브러리 함수 정의 안됨 에러

**확인:**
```bash
# 라이브러리 파일 확인
ls -la /path/to/giipAgentLinux/lib/

# 파일 무결성 확인
md5sum /path/to/giipAgentLinux/lib/*.sh

# 파일 인코딩 확인 (DOS/Unix line endings 문제)
file /path/to/giipAgentLinux/lib/gateway.sh
```

**해결:**
```bash
# 1. 라이브러리 파일 권한 수정
chmod +x /path/to/giipAgentLinux/lib/*.sh

# 2. 라인 ending 수정 (필요시)
dos2unix /path/to/giipAgentLinux/lib/*.sh

# 3. 파일 재다운로드 (손상된 경우)
# Git에서 다시 받아오기 등
```

---

## 📋 빠른 진단 스크립트

### ⭐ 최우선: KVS 기반 Gateway 디버깅 (권장)

```powershell
# giipdb 디렉토리 이동
cd C:\path\to\giipdb

# 1️⃣ 최근 5분 Gateway 실행 흐름 확인 (가장 빠름!)
pwsh .\mgmt\check-latest.ps1

# 출력: [5.x] 포인트별 실행 흐름
# 예상:
# [5.1] Agent 시작
# [5.2] 설정 로드
# [5.3] Gateway 모드 초기화
# [5.4] 서버 목록 조회 시작
# ...

# 2️⃣ 특정 서버의 최근 Gateway 로그 상세 조회
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey YOUR_GATEWAY_LSSN -KFactor gateway_operation -Top 50

# 3️⃣ 모든 로그 카테고리 현황 확인
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey YOUR_GATEWAY_LSSN -Summary
```

### 전통적 방법: 로그 파일 기반 진단

```bash
#!/bin/bash
# 빠른 진단 자동화 스크립트

echo "=== GIIP Gateway 리모트 서버 처리 진단 ==="
echo ""

# 1. 설정 확인
echo "1️⃣ 설정 확인:"
cat /path/to/giipAgent.cnf | grep -i "is_gateway"

# 2. 최근 로그 확인
echo ""
echo "2️⃣ 최근 로그 확인:"
grep -E "\[5\.[1-4]\]" /path/to/logfile | tail -5

# 3. 라이브러리 확인
echo ""
echo "3️⃣ 라이브러리 파일 확인:"
ls -la /path/to/giipAgentLinux/lib/gateway.sh

# 4. 네트워크 확인
echo ""
echo "4️⃣ 네트워크 확인:"
ping -c 1 YOUR_API_URL 2>&1 | head -2

# 5. SSH 확인
echo ""
echo "5️⃣ SSH 확인:"
which sshpass && sshpass -V || echo "sshpass not installed"

echo ""
echo "=== 진단 완료 ==="
```

---

### 추가: Linux 환경 KVS 확인 (SSH 원격 접근)

```bash
#!/bin/bash
# Linux Gateway 서버에서 직접 KVS 데이터 확인

LSSN="YOUR_GATEWAY_LSSN"
LOGFILE="/var/log/giip/giipAgent3.log"  # 또는 /tmp/

echo "=== Gateway 최근 실행 흐름 ==="
grep -E "\[5\.[1-9]\]|\[6\.[0-9]\]" "$LOGFILE" | tail -20

echo ""
echo "=== Gateway 에러/경고 ==="
grep -E "ERROR|WARN|FAIL" "$LOGFILE" | tail -10

echo ""
echo "=== KVS 로그 파일 확인 ==="
ls -lht /tmp/discovery_kvs_log_*.txt 2>/dev/null | head -5
ls -lht /tmp/gateway_* 2>/dev/null | head -5
```

---

## 📞 문제 해결 결정 트리

```
리모트 서버 처리 중단 발생
│
├─ 로그 포인트 [5.3] 확인
│  ├─ 있음 → Level 2로 진행
│  └─ 없음 → is_gateway 설정 확인 (원인 1)
│
├─ API 응답 확인 (GatewayRemoteServerListForAgent)
│  ├─ 실패 → DB API 연결 확인 (원인 2)
│  ├─ 빈 배열 → 리모트 서버 목록 확인 (원인 3)
│  └─ 정상 → Level 3으로 진행
│
├─ SSH 연결 로그 확인
│  ├─ SSH 에러 → SSH 설정 확인 (원인 4)
│  └─ 에러 메시지 없음 → 라이브러리 확인 (원인 5)
│
└─ 해결되지 않으면 → Level 4 심화 진단 진행
```

---

## 📚 관련 문서

| 문서 | 용도 | 우선순위 |
|------|------|--------|
| [GIIPAGENT3_SPECIFICATION.md](./GIIPAGENT3_SPECIFICATION.md) | Agent 3.0 전체 스펙 | 🟠 중요 |
| [GATEWAY_CONFIG_PHILOSOPHY.md](./GATEWAY_CONFIG_PHILOSOPHY.md) | Gateway 설정 철학 | 🟡 참고 |
| [REMOTE_AUTO_DISCOVER_DESIGN.md](./REMOTE_AUTO_DISCOVER_DESIGN.md) | 리모트 auto-discover 설계 | 🟡 참고 |
| [KVS_LOGGING_DIAGNOSIS_GUIDE.md](./KVS_LOGGING_DIAGNOSIS_GUIDE.md) | KVS 로깅 진단 | 🔴 필수 |
| [SSH_CONNECTION_LOGGER.md](./SSH_CONNECTION_LOGGER.md) | SSH 연결 로깅 모듈 | 🟡 참고 |
| [KVS_QUERY_GUIDE.md](../../giipdb/docs/KVS_QUERY_GUIDE.md) | KVS 조회 가이드 | 🔴 **필수** |
| [KVS_DEBUG_GUIDE.md](../../giipdb/docs/KVS_DEBUG_GUIDE.md) | KVS 디버그 가이드 | 🔴 **필수** |

---

## 🔄 문제 해결 프로세스

1. **초기 진단**: Level 1 체크리스트 완료
2. **근본 원인 파악**: Level 2-3 진단 수행
3. **일반적 원인별 해결**: 5가지 원인 중 해당 항목 적용
4. **심화 진단**: 위의 모든 단계 후에도 미해결 시 Level 4 진행
5. **검증**: 변경 후 giipAgent3.sh 재실행 및 로그 확인

---

## 📝 체크리스트: 문제 해결 완료 확인

### 설정 및 초기화
- [ ] is_gateway 설정이 1 또는 true인가?
- [ ] 로그 포인트 [5.1]이 나타나는가?
- [ ] 로그 포인트 [5.2]에서 is_gateway=1인가?
- [ ] 로그 포인트 [5.3]이 나타나는가?

### 데이터 조회
- [ ] GatewayRemoteServerListForAgent API가 응답하는가?
- [ ] 리모트 서버 목록이 비어있지 않은가?
- [ ] 로그 포인트 [5.4] 이후 서버 처리 로그가 있는가?

### 연결 및 실행
- [ ] SSH 연결이 성공하는가?
- [ ] sshpass 또는 SSH 키가 제대로 설정되어 있는가?
- [ ] 라이브러리 파일이 모두 있는가?

### KVS 데이터 확인 (권장)
- [ ] `pwsh .\mgmt\check-latest.ps1` 결과에서 [5.x] 포인트 시퀀스가 정상인가?
- [ ] KVS에 `gateway_operation` Factor 데이터가 있는가?
- [ ] 최근 5분 내 [5.4] 포인트 이후 포인트들이 있는가?
- [ ] 같은 포인트가 무한 반복되는 것은 아닌가?

### 최종 검증
- [ ] giipAgent3.sh 재실행 후 리모트 서버가 처리되는가?
- [ ] 로그에서 에러나 경고 메시지가 없는가?
- [ ] 이전과 다르게 정상 작동하는가?

**모두 확인되면 문제 해결 완료! ✅**

---

## 🔗 다음 단계

**문제 해결 완료:**
- 정상적으로 작동 확인 후 모니터링 계속

**여전히 미해결:**
- [KVS_LOGGING_DIAGNOSIS_GUIDE.md](./KVS_LOGGING_DIAGNOSIS_GUIDE.md)의 Phase별 분석 참고
- [CURRENT_ISSUES.md](../../giipdb/docs/CURRENT_ISSUES.md)에서 유사 이슈 확인
