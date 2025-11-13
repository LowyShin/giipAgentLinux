# giipAgent2.sh 사양서

> ⚠️ **Legacy Documentation (v2.0)** - 이 문서는 giipAgent2.sh 사양입니다. 현재는 **giipAgent3.sh**를 사용합니다. 최신 문서는 [GIIPAGENT3_SPECIFICATION.md](GIIPAGENT3_SPECIFICATION.md)를 참고하세요.

**Last Updated**: 2025-11-08  
**Version**: 2.00  
**Author**: GIIP Development Team

---

## 📋 개요

giipAgent2.sh는 GIIP 시스템의 Linux Agent로, 두 가지 모드로 동작합니다:

- **Normal Mode** (gateway_mode=0): 로컬 서버에서 직접 명령 큐 실행
- **Gateway Mode** (gateway_mode=1): SSH를 통해 다중 원격 서버 관리 및 데이터베이스 쿼리 실행

---

## 🔧 실행 조건

### 1. 설정 파일 (giipAgent.cnf)

| 파라미터 | 필수 | 기본값 | 설명 |
|---------|------|--------|------|
| `sk` | ✅ | - | Secret Key (API 인증) |
| `lssn` | ✅ | 0 | Logical Server Serial Number (0=자동할당) |
| `giipagentdelay` | ❌ | 60 | 명령 큐 확인 간격 (초) |
| `gateway_mode` | ❌ | 0 | Gateway 모드 활성화 (0=Normal, 1=Gateway) |
| `gateway_heartbeat_interval` | ❌ | 300 | Heartbeat 간격 (초, Gateway 모드만) |
| `apiaddrv2` | ✅ | - | giipApiSk2 API 엔드포인트 |
| `apiaddrcode` | ❌ | - | Azure Function Code (선택) |

### 2. 실행 환경

**필수 패키지**:
- `bash` (쉘 스크립트 실행)
- `wget` (API 호출)
- `dos2unix` (스크립트 형식 변환)

**Gateway 모드 추가 요구사항**:
- `sshpass` (SSH 패스워드 인증)
- `python3` + `pip3` (데이터베이스 쿼리용)
- `jq` (JSON 파싱)

**데이터베이스 클라이언트** (Gateway 모드, 필요 시 자동 설치):
- `mysql` (MySQL/MariaDB)
- `psql` (PostgreSQL)
- `pyodbc` (MSSQL, Python 패키지)
- `cx_Oracle` (Oracle, Python 패키지 + Instant Client)

### 3. 실행 방법

**Cron 자동 실행**:
```bash
* * * * * cd /opt/giipAgentLinux; bash --login -c 'sh /opt/giipAgentLinux/giipAgent2.sh'
```

**수동 실행**:
```bash
cd /opt/giipAgentLinux
bash giipAgent2.sh
```

---

## 🔄 동작 흐름

### Normal Mode (gateway_mode=0)

```
시작
  ↓
설정 파일 로드 (giipAgent.cnf)
  ↓
프로세스 중복 체크 (최대 3개 허용)
  ↓
┌─────────────────────────────────┐
│ 메인 루프 (while cntgiip <= 3) │
└─────────────────────────────────┘
  ↓
API 호출: CQEQueueGet lssn hostname os op
  ↓
응답 확인
  ├─ RstVal=404 → "No queue" 로그 → 종료
  ├─ RstVal=200, ms_body 있음 → 스크립트 실행
  ├─ RstVal=200, ms_body 없음, mssn 있음 → Repository에서 스크립트 조회 → 실행
  └─ 기타 → 에러 로그 → 종료
  ↓
스크립트 실행
  ├─ expect 명령 포함 → expect 실행
  └─ 일반 → bash 실행
  ↓
임시 파일 삭제
  ↓
다음 큐 확인 또는 종료
```

### Gateway Mode (gateway_mode=1)

```
시작
  ↓
설정 파일 로드
  ↓
Gateway 모드 초기화
  ├─ sshpass 설치 확인/설치
  ├─ Python 환경 확인/설치
  ├─ 데이터베이스 클라이언트 확인/설치
  └─ 서버 리스트 동기화 (API → CSV)
  ↓
KVS 저장: Gateway 시작 상태 (gateway_status, startup)
  ↓
┌─────────────────────────────────────────┐
│ 메인 루프 (while cntgiip <= 3)        │
└─────────────────────────────────────────┘
  ↓
Heartbeat 체크 (300초마다)
  ├─ sync-gateway-servers.sh 백그라운드 실행
  └─ KVS 저장: Heartbeat 트리거 (gateway_heartbeat)
  ↓
데이터베이스 쿼리 처리 (process_db_queries)
  ├─ API에서 쿼리 리스트 조회 (GatewayDBQueryList)
  ├─ should_execute=1인 쿼리만 실행
  ├─ DB 타입별 실행 (MySQL/PostgreSQL/MSSQL/Oracle)
  └─ 결과 → KVS 저장 (kType=db_query_result)
  ↓
원격 서버 처리 (process_gateway_servers)
  ├─ CSV 파일에서 서버 리스트 읽기
  ├─ 각 서버별:
  │   ├─ API 호출: CQEQueueGet lssn hostname os op
  │   ├─ 큐 확인
  │   │   ├─ RstVal=404 → "No queue" 로그
  │   │   └─ RstVal=200 → 스크립트 실행
  │   └─ SSH로 원격 서버에 스크립트 복사 및 실행
  │       ├─ 패스워드 인증: sshpass 사용
  │       └─ 키 인증: ssh -i 사용
  └─ 결과 로그
  ↓
Sleep (giipagentdelay 초)
  ↓
프로세스 중복 체크 → 루프 계속 또는 종료
```

---

## 📊 KVS 저장 로직 (현재 구현)

### Gateway Mode

| kType | kKey | kFactor | 저장 시점 | 내용 |
|-------|------|---------|----------|------|
| `gateway_status` | `gateway_{lssn}_startup` | JSON | Gateway 시작 시 | 시작 상태, 버전, lssn, 타임스탬프, 모드, API |
| `gateway_status` | `gateway_{lssn}_error` | JSON | sshpass 설치 실패 시 | 에러 상태, 에러 메시지, 타임스탬프 |
| `gateway_status` | `gateway_{lssn}_sync` | JSON | 서버 동기화 후 | 동기화 상태, 서버 수, 타임스탬프 |
| `gateway_heartbeat` | `gateway_{lssn}_heartbeat_trigger` | JSON | Heartbeat 트리거 시 | 트리거 상태, 간격, 타임스탬프 |
| `gateway_heartbeat` | `gateway_{lssn}_heartbeat_status` | JSON | Heartbeat 시작 시 | 실행 상태, PID, 타임스탬프 |
| `gateway_heartbeat` | `gateway_{lssn}_heartbeat_error` | JSON | Heartbeat 스크립트 없음 시 | 에러 상태, 에러 메시지, 타임스탬프 |
| `db_query_result` | `{kvs_key_prefix}{target_lssn}` | JSON/RAW | DB 쿼리 실행 후 | 쿼리 결과 데이터 |

### Normal Mode

**현재 KVS 저장 없음** (Queue 실행 결과만 로그 파일에 기록)

---

## 📝 실행 내역 추적 요구사항

### 목표

giipAgent2.sh 실행 시 **무엇이 실행되었는지**를 KVS의 **"giipagent"** factor에 저장하여 추적 가능하도록 함.

### 저장 대상 이벤트

#### Normal Mode

1. **Agent 시작**: 스크립트 실행 시작
2. **Queue 조회**: API 호출 및 응답
3. **스크립트 실행**: Queue에서 받은 스크립트 실행
4. **실행 결과**: 성공/실패/에러
5. **Agent 종료**: 종료 사유 (정상/에러/프로세스 중복)

#### Gateway Mode

1. **Gateway 시작**: 초기화, 패키지 설치
2. **서버 동기화**: API에서 서버 리스트 조회
3. **Heartbeat**: 주기적 Heartbeat 트리거
4. **DB 쿼리 실행**: 각 쿼리 실행 및 결과
5. **원격 서버 처리**: 각 서버별 Queue 조회 및 실행
6. **에러 발생**: 모든 에러 이벤트

### KVS 저장 구조

**kType**: `lssn` (기존 규칙 유지)  
**kKey**: `{lssn}` (서버 식별자)  
**kFactor**: `giipagent` (통일된 factor)  
**kValue**: JSON 배열 또는 객체

```json
{
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
```

#### event_type별 details 구조

**startup** (Agent 시작):
```json
{
  "pid": 12345,
  "config_file": "/opt/giipAgentLinux/giipAgent.cnf",
  "api_endpoint": "https://giipfaw.azurewebsites.net/api/giipApiSk2"
}
```

**queue_check** (Queue 조회):
```json
{
  "api_response": "200|404",
  "has_queue": true|false,
  "mssn": 123,
  "script_source": "ms_body|repository|none"
}
```

**script_execution** (스크립트 실행):
```json
{
  "script_type": "bash|expect",
  "exit_code": 0,
  "execution_time_seconds": 5.2,
  "output_preview": "first 100 chars..."
}
```

**shutdown** (Agent 종료):
```json
{
  "reason": "normal|error|duplicate_process",
  "process_count": 3,
  "uptime_seconds": 300
}
```

**gateway_init** (Gateway 초기화):
```json
{
  "sshpass_installed": true|false,
  "python_version": "3.8.10",
  "db_clients": {
    "mysql": true,
    "postgresql": true,
    "mssql": false,
    "oracle": false
  },
  "server_sync_status": "success|failed",
  "server_count": 5
}
```

**heartbeat** (Heartbeat 트리거):
```json
{
  "interval_seconds": 300,
  "script_path": "/opt/giipAgentLinux/sync-gateway-servers.sh",
  "background_pid": 67890
}
```

**db_query** (DB 쿼리 실행):
```json
{
  "gmq_sn": 101,
  "target_lssn": 71028,
  "db_type": "MySQL",
  "db_host": "192.168.1.10",
  "query_name": "disk_check",
  "exit_code": 0,
  "execution_time_seconds": 1.5,
  "result_row_count": 10,
  "kvs_save_status": "success|failed"
}
```

**remote_execution** (원격 서버 처리):
```json
{
  "target_hostname": "server01",
  "target_lssn": 71028,
  "ssh_host": "192.168.1.10",
  "ssh_port": 22,
  "auth_method": "password|key",
  "queue_response": "200|404",
  "execution_status": "success|failed|no_queue",
  "error_message": "..."
}
```

**error** (에러 발생):
```json
{
  "error_type": "api_error|ssh_error|db_error|script_error|config_error",
  "error_message": "sshpass installation failed",
  "error_code": 1,
  "context": "gateway_init"
}
```

---

## 🔨 구현 계획

### 1. KVS 저장 함수 추가

```bash
# Function: Save execution log to KVS
save_execution_log() {
    local event_type=$1
    local details_json=$2
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local hostname=$(hostname)
    local mode="${gateway_mode}"
    [ "$mode" = "1" ] && mode="gateway" || mode="normal"
    
    local kvalue=$(cat <<EOF
{
  "event_type": "${event_type}",
  "timestamp": "${timestamp}",
  "lssn": ${lssn},
  "hostname": "${hostname}",
  "mode": "${mode}",
  "version": "${sv}",
  "details": ${details_json}
}
EOF
)
    
    local kvs_url="${apiaddrv2}"
    [ -n "$apiaddrcode" ] && kvs_url="${kvs_url}?code=${apiaddrcode}"
    
    local text="KVSPut kType kKey kFactor"
    local jsondata=$(cat <<EOF
{
  "kType": "lssn",
  "kKey": "${lssn}",
  "kFactor": "giipagent",
  "kValue": ${kvalue}
}
EOF
)
    
    wget -O /dev/null \
        --post-data="text=${text}&token=${sk}&jsondata=$(echo ${jsondata} | sed 's/ /%20/g')" \
        --header="Content-Type: application/x-www-form-urlencoded" \
        "${kvs_url}" \
        --no-check-certificate -q 2>&1
    
    if [ $? -eq 0 ]; then
        echo "[KVS-Log] ✅ Saved execution log: ${event_type}" >> $LogFileName
    else
        echo "[KVS-Log] ⚠️  Failed to save execution log: ${event_type}" >> $LogFileName
    fi
}
```

### 2. 이벤트 로깅 지점

#### Normal Mode

- Line 975-990: Agent 시작 → `save_execution_log "startup" "{...}"`
- Line 1180-1220: Queue 조회 → `save_execution_log "queue_check" "{...}"`
- Line 1230-1240: 스크립트 실행 → `save_execution_log "script_execution" "{...}"`
- Line 1245-1255: Agent 종료 → `save_execution_log "shutdown" "{...}"`

#### Gateway Mode

- Line 995-1010: Gateway 초기화 → `save_execution_log "gateway_init" "{...}"`
- Line 1080-1110: Heartbeat 트리거 → `save_execution_log "heartbeat" "{...}"`
- Line 620-630: DB 쿼리 실행 → `save_execution_log "db_query" "{...}"`
- Line 850-920: 원격 서버 처리 → `save_execution_log "remote_execution" "{...}"`
- 모든 에러 발생 지점 → `save_execution_log "error" "{...}"`

### 3. 기존 KVS 저장과의 관계

**기존 저장 유지** (Gateway 모드):
- `gateway_status` factor: Gateway 특화 상태 (startup, error, sync)
- `gateway_heartbeat` factor: Heartbeat 특화 상태
- `db_query_result` factor: 실제 쿼리 결과 데이터

**새로 추가** (모든 모드):
- `giipagent` factor: 통합 실행 로그 (무엇이 실행되었는지 추적)

**목적 차이**:
- 기존: 특정 기능의 상태 저장
- 신규: 전체 실행 흐름 추적 (Audit Log)

---

## 📚 참고 문서

- [STANDARD_WORK_PROMPT.md](../../STANDARD_WORK_PROMPT.md) - 작업 표준 문서
- [giipapi_rules.md](../../docs/giipapi_rules.md) - GIIP API 규칙 (text/jsondata 분리)
- [README.md](../README.md) - Agent 설치 및 사용 가이드
- [GATEWAY_SETUP_GUIDE.md](GATEWAY_SETUP_GUIDE.md) - Gateway 설정 가이드

---

## 🔄 변경 이력

| 날짜 | 버전 | 변경 내용 |
|------|------|-----------|
| 2025-11-08 | 1.0 | 초기 작성, giipAgent2.sh 전체 분석 및 실행 흐름 문서화 |
| 2025-11-08 | 1.1 | "giipagent" factor 저장 요구사항 추가 |

---

**작성자**: AI Assistant  
**검토자**: (미정)  
**승인자**: (미정)
