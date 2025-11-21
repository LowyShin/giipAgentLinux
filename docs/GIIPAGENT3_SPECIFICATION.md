# giipAgent3.sh 사양서 (Architecture & Module Specification)

> **📅 문서 메타데이터**  
> - 최초 작성: 2025-11-11  
> - 최종 수정: 2025-11-11  
> - 작성자: AI Agent  
> - 목적: giipAgent3 모듈 구조 및 KVS 로깅 규칙 명세

---

## 📋 목차

1. [개요](#개요)
2. [모듈 구조](#모듈-구조)
3. [KVS 로깅 규칙](#kvs-로깅-규칙)
4. [버전 추적](#버전-추적)
5. [실행 흐름](#실행-흐름)

---

## 개요

**파일**: `giipAgentLinux/giipAgent3.sh`  
**버전**: 3.00  
**아키텍처**: Modular (lib/*.sh 라이브러리 분리)  
**모드**: Gateway / Normal

---

## 🎯 핵심 용어 정의 (Critical Terminology)

이 사양서에서 자주 혼동되는 **3가지 역할 구분**:

### 1️⃣ Gateway 서버 (Gateway Server)
**정의**: GIIP Agent가 **Gateway 모드로 실행되는 서버**

| 속성 | 값 |
|------|-----|
| **식별자** | `LSSN` (tLSvr 테이블) |
| **DB 표시** | `is_gateway = 1` |
| **역할** | 원격 서버 및 DB를 중앙에서 관리/제어 |
| **실행 모드** | `gateway_mode = 1` (giipAgent3.sh) |
| **소유 Gateway** | `gateway_lssn = NULL` (자신은 Gateway 관리 대상 아님) |
| **예시** | 71174 (gateway-server-01) |

**SQL**:
```sql
SELECT LSSN, LSHostname FROM tLSvr WHERE is_gateway = 1
```

---

### 2️⃣ 리모트 서버 (Remote Server)
**정의**: **Gateway 서버가 SSH를 통해 원격으로 작업을 수행하는 서버** (내부망, 원격지, giipAgent 미설치)

| 속성 | 값 |
|------|-----|
| **식별자** | `LSSN` (tLSvr 테이블) |
| **DB 표시** | `is_gateway = 0` |
| **gateway_lssn** | ✅ **NOT NULL** (어떤 Gateway가 이 서버를 관리하는지 기록) |
| **역할** | Gateway가 SSH를 통해 원격에서 작업을 수행하는 대상 |
| **Agent 설치** | ❌ **설치 안 함** (giipAgent3.sh 미배포) |
| **Agent 실행** | ❌ **실행 안 함** (Gateway에서 원격으로 명령 실행) |
| **gateway_mode** | 해당 없음 (giipAgent가 없음) |
| **SSH 정보** | `gateway_ssh_host`, `gateway_ssh_user`, `gateway_ssh_port` |
| **예시** | 71221 (remote-server-01), gateway_lssn=71174 |

**리모트 서버와 Gateway의 관계**:

```
Gateway 서버 (LSSN=71174, is_gateway=1)
└─ giipAgent3.sh (Gateway 모드로 실행)
   │
   └─ 리모트 서버 목록 조회 (gateway_lssn=71174)
      │
      └─ 각 리모트 서버에 대해:
         ├─ SSH 접근 테스트 (SSH 연결 가능한가?)
         ├─ SSH를 통해 원격 명령 실행 (필요시)
         ├─ 작업 결과를 RemoteServerSSHTest API로 리포팅
         └─ API가 tLSvr.LSChkdt 업데이트

리모트 서버 (LSSN=71221, is_gateway=0)
└─ giipAgent 없음 (설치 안 됨)
   └─ Gateway의 SSH 명령 수신/실행 대기
      └─ 결과를 Gateway에 반환
```

**왜 Gateway 경유인가?**:
- 리모트 서버에는 giipAgent를 설치할 수 없는 환경 (보안, 권한 등)
- 따라서 Gateway가 SSH를 통해 **원격에서 대신 작업 수행**
- Gateway = 중앙 제어점, 리모트 서버 = 작업 실행 대상

**SQL**:
```sql
SELECT LSSN, LSHostname, gateway_lssn 
FROM tLSvr 
WHERE is_gateway = 0 AND gateway_lssn IS NOT NULL
```

---

### 3️⃣ 리모트 데이터베이스 (Remote Database)
**정의**: **Gateway 서버를 통해 접근하는 외부 DB**

| 속성 | 값 |
|------|-----|
| **테이블** | `tManagedDatabase` (외부 DB 접속 정보) |
| **식별자** | `mdb_id` |
| **Gateway** | `gateway_lssn` ✅ **NOT NULL** (필수) |
| **Target Server** | `target_lssn` (선택사항, 모니터링 대상 서버) |
| **DB 종류** | MySQL, PostgreSQL, Oracle, MSSQL 등 |
| **예시** | mdb_id=5, gateway_lssn=71174, host=192.168.1.100, port=3306 |

**또는** tGatewayDBQuery 테이블:
```sql
SELECT * FROM tGatewayDBQuery 
WHERE gateway_lssn = @gateway_lssn
```

---

## 📊 세 가지 개념의 관계도

```
┌─────────────────────────────────────────────────────────┐
│  GIIP 포털 (Web UI)                                     │
│  - 서버 목록 (tLSvr)                                   │
│  - DB 관리 (tManagedDatabase)                           │
└──────────────────┬──────────────────────────────────────┘
                   │
       ┌───────────┴───────────┐
       ▼                       ▼
┌──────────────────────────────────┐ ┌──────────────────────────────────┐
│  [1️⃣ Gateway 서버]              │ │  [2️⃣ 리모트 서버]               │
│  is_gateway=1                    │ │  is_gateway=0                    │
│  LSSN=71174                      │ │  LSSN=71221                      │
│  gateway_lssn=NULL               │ │  gateway_lssn=71174              │
│                     │ │                     │
│ ┌───────────────┐   │ │  SSH Config:        │
│ │ giipAgent3.sh │   │ │  - gateway_ssh_host │
│ │ (Gateway Mode)│   │ │  - gateway_ssh_user │
│ └───────────────┘   │ │  - gateway_ssh_port │
└─────────────────────┘ └─────────────────────┘
          │                       △
          │ Gateway가 관리하는    │
          └───────────────────────┘
          
          │
          └─────────► [3️⃣ 리모트 데이터베이스]
                      tManagedDatabase
                      gateway_lssn=71174
                      - MySQL 192.168.1.100:3306
                      - PostgreSQL 192.168.1.101:5432
```

---

## 🔍 구분 팁 (Quick Reference)

| 구분 | is_gateway | gateway_lssn | 관리 대상 |
|------|-----------|--------------|---------|
| **Gateway 서버** | **1** | NULL | 리모트 서버들 관리 |
| **리모트 서버** | **0** | ✅ 값 있음 | Gateway에 의해 관리됨 |
| **리모트 DB** | - | ✅ 값 있음 | Gateway를 통한 접근 |

---

## 모듈 구조

### 메인 스크립트

**giipAgent3.sh**
- 역할: 진입점, 설정 로드, 모드 분기
- 위치: `giipAgentLinux/giipAgent3.sh`
- 라인 수: ~250 lines

### 라이브러리 모듈 (lib/*.sh)

#### 1. lib/common.sh
**필수 로드**: ✅ 모든 모드

**제공 기능**:
- `load_config()`: giipAgent.cnf 로드
- `log_message()`: 로그 파일 기록
- `error_handler()`: 에러 처리 및 종료
- `init_log_dir()`: 로그 디렉토리 초기화
- `detect_os()`: OS 감지 (CentOS, Ubuntu, macOS 등)
- `build_api_url()`: API URL 생성 (code 파라미터 처리)

**KVS 로깅**: ❌ 없음

**로드 시점**: giipAgent3.sh Line 26-32

```bash
if [ -f "${LIB_DIR}/common.sh" ]; then
	. "${LIB_DIR}/common.sh"
else
	echo "❌ Error: common.sh not found"
	exit 1
fi
```

---

#### 2. lib/gateway.sh
**필수 로드**: ⚠️ Gateway 모드만

**제공 기능**:
- `save_gateway_status()`: Gateway 상태를 tKVS에 저장 (kFactor=gateway_status)
- `sync_gateway_servers()`: Web UI에서 서버 목록 동기화
- `sync_db_queries()`: DB 체크 쿼리 동기화
- `execute_gateway_cycle()`: Gateway 사이클 실행
- `process_gateway_queue()`: Gateway 큐 처리
- `save_execution_log()`: 실행 이력을 tKVS에 저장 (kFactor=giipagent) ⭐

**KVS 로깅**: ✅ 있음
- `save_gateway_status()`: kFactor=gateway_status
- `save_execution_log()`: kFactor=giipagent

**로드 시점**: giipAgent3.sh Line 196 (Gateway 모드 진입 후)

```bash
if [ "${gateway_mode}" = "1" ]; then
	. "${LIB_DIR}/db_clients.sh"
	. "${LIB_DIR}/gateway.sh"
	# ...
fi
```

---

#### 3. lib/normal.sh
**필수 로드**: ⚠️ Normal 모드만

**제공 기능**:
- `run_normal_mode()`: Normal 모드 실행 (큐 조회 → 스크립트 실행)
- `fetch_queue()`: CQEQueueGet API 호출
- `parse_json_response()`: JSON 응답 파싱
- `execute_script()`: 스크립트 실행 (bash/expect)
- `save_execution_log()`: 실행 이력을 tKVS에 저장 (kFactor=giipagent) ⭐

**KVS 로깅**: ✅ 있음
- `save_execution_log()`: kFactor=giipagent

**로드 시점**: giipAgent3.sh Line 233 (Normal 모드 진입 후)

```bash
else
	. "${LIB_DIR}/normal.sh"
	run_normal_mode "$lssn" "$hn" "$os"
fi
```

---

#### 4. lib/db_clients.sh
**필수 로드**: ⚠️ Gateway 모드만

**제공 기능**:
- `check_db_clients()`: DB 클라이언트 설치 확인 (mysql, psql, sqlcmd, mongodb)
- `get_db_client_versions()`: 각 DB 클라이언트 버전 조회

**KVS 로깅**: ❌ 없음

**로드 시점**: giipAgent3.sh Line 196 (Gateway 모드)

---

## KVS 로깅 규칙

### 🚨 절대 규칙: startup 로깅은 1번만!

**문제**: 여러 모듈에서 각각 startup 로깅 → 중복 발생

**해결**: 각 모드별로 **1곳에서만** startup 로깅

### startup 로깅 위치

#### Gateway 모드
**파일**: `giipAgent3.sh`  
**위치**: Line 203  
**함수**: `save_execution_log "startup"`

```bash
if [ "${gateway_mode}" = "1" ]; then
	# ...
	init_details="{\"config_file\":\"giipAgent.cnf\",\"api_endpoint\":\"${apiaddrv2}\",\"pid\":$$,\"is_gateway\":1,\"git_commit\":\"${GIT_COMMIT}\",\"file_modified\":\"${FILE_MODIFIED}\",\"script_path\":\"${BASH_SOURCE[0]}\"}"
	save_execution_log "startup" "$init_details"
	# ...
fi
```

#### Normal 모드
**파일**: `lib/normal.sh`  
**위치**: Line 216  
**함수**: `save_execution_log "startup"`

```bash
run_normal_mode() {
	# ...
	local startup_details="{\"pid\":$$,\"config_file\":\"giipAgent.cnf\",\"api_endpoint\":\"${apiaddrv2}\",\"is_gateway\":0,\"mode\":\"normal\",\"git_commit\":\"${GIT_COMMIT}\",\"file_modified\":\"${FILE_MODIFIED}\",\"script_path\":\"${BASH_SOURCE[1]}\"}"
	save_execution_log "startup" "$startup_details"
	# ...
}
```

### KVS 이벤트 타입

| 이벤트 타입 | 파일 | 함수 | kFactor | 설명 |
|------------|------|------|---------|------|
| startup | gateway.sh / normal.sh | save_execution_log | giipagent | Agent 시작 (1번만!) |
| shutdown | gateway.sh / normal.sh | save_execution_log | giipagent | Agent 종료 |
| queue_check | normal.sh | save_execution_log | giipagent | 큐 조회 결과 |
| script_execution | normal.sh | save_execution_log | giipagent | 스크립트 실행 결과 |
| error | gateway.sh / normal.sh | save_execution_log | giipagent | 에러 발생 |
| gateway_init | gateway.sh | save_execution_log | giipagent | Gateway 초기화 완료 |
| gateway_cycle_start | gateway.sh | save_gateway_status | gateway_status | Gateway 사이클 시작 |
| gateway_cycle_end | gateway.sh | save_gateway_status | gateway_status | Gateway 사이클 종료 |

### save_execution_log vs save_gateway_status

**save_execution_log**:
- kFactor: `giipagent`
- 용도: Agent 실행 이력 (startup, shutdown, queue, script 등)
- 파일: `lib/gateway.sh`, `lib/normal.sh`

**save_gateway_status**:
- kFactor: `gateway_status`
- 용도: Gateway 상태 정보 (cycle, server status 등)
- 파일: `lib/gateway.sh`

---

## 버전 추적

### 환경변수 설정

**파일**: `giipAgent3.sh`  
**위치**: Line 103-119

```bash
# Get Git commit hash (if available)
export GIT_COMMIT="unknown"
if command -v git >/dev/null 2>&1 && [ -d "${SCRIPT_DIR}/.git" ]; then
	GIT_COMMIT=$(git -C "${SCRIPT_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")
fi

# Get file modification date
export FILE_MODIFIED=$(stat -c %y "${BASH_SOURCE[0]}" 2>/dev/null || stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "${BASH_SOURCE[0]}" 2>/dev/null || echo "unknown")
```

**export된 변수**:
- `GIT_COMMIT`: Git commit hash (짧은 버전)
- `FILE_MODIFIED`: giipAgent3.sh 파일 수정 날짜

**사용처**:
- Gateway 모드: giipAgent3.sh Line 203
- Normal 모드: lib/normal.sh Line 216

### startup JSON 구조

```json
{
  "pid": 12345,
  "config_file": "giipAgent.cnf",
  "api_endpoint": "https://giipfaw.azurewebsites.net/api/giipapisk",
  "is_gateway": 0,
  "mode": "normal",
  "git_commit": "a1b2c3d",
  "file_modified": "2025-11-11 09:30:00",
  "script_path": "/path/to/giipAgent3.sh"
}
```

---

## 실행 흐름

### Gateway 모드

```
giipAgent3.sh (메인)
  ↓
load_config() [common.sh]
  ↓
fetch DB config (is_gateway 조회)
  ↓
gateway_mode = 1 감지
  ↓
load: db_clients.sh, gateway.sh
  ↓
save_execution_log "startup" [gateway.sh] ⭐ 1번만!
  ↓
check_sshpass()
  ↓
sync_gateway_servers()
  ↓
save_execution_log "gateway_init" [gateway.sh]
  ↓
while loop (cntgiip <= 3)
  ↓
execute_gateway_cycle() [gateway.sh]
  ↓
log_message "Gateway mode terminated"
```

### Normal 모드

```
giipAgent3.sh (메인)
  ↓
load_config() [common.sh]
  ↓
fetch DB config (is_gateway 조회)
  ↓
gateway_mode = 0 감지
  ↓
load: normal.sh
  ↓
run_normal_mode() [normal.sh]
  ↓
save_execution_log "startup" [normal.sh] ⭐ 1번만!
  ↓
fetch_queue() [normal.sh]
  ↓
save_execution_log "queue_check" [normal.sh]
  ↓
execute_script() [normal.sh]
  ↓
save_execution_log "script_execution" [normal.sh]
  ↓
save_execution_log "shutdown" [normal.sh]
```

---

## 🚨 AI Agent 작업 규칙

### KVS 로깅 수정 시

```markdown
[ ] 1. 이 사양서 먼저 확인
[ ] 2. startup 로깅 위치 확인:
    - Gateway: giipAgent3.sh Line 203
    - Normal: lib/normal.sh Line 216
[ ] 3. 중복 로깅 방지:
    - startup은 각 모드별 1곳에서만!
    - 새 로깅 추가 시 기존 위치 확인
[ ] 4. 버전 정보 사용:
    - $GIT_COMMIT (환경변수)
    - $FILE_MODIFIED (환경변수)
[ ] 5. 사양서 업데이트:
    - 새 이벤트 타입 추가 시 테이블 업데이트
    - 새 함수 추가 시 모듈 구조 업데이트
```

### 모듈 수정 시

```markdown
[ ] 1. 모듈 역할 확인 (이 사양서)
[ ] 2. 해당 모듈만 수정
[ ] 3. 다른 모듈에 영향 없는지 확인
[ ] 4. KVS 로깅 중복 체크
[ ] 5. 사양서 업데이트
```

---

## 📊 파일 구조 요약

```
giipAgentLinux/
├── giipAgent3.sh           # 메인 진입점 (250 lines)
│   ├── Load common.sh      # 필수
│   ├── Fetch DB config     # is_gateway 조회
│   ├── Export GIT_COMMIT   # 버전 추적
│   ├── Export FILE_MODIFIED
│   └── Mode 분기
│       ├── Gateway → load gateway.sh, db_clients.sh
│       └── Normal → load normal.sh
│
└── lib/
    ├── common.sh           # 공통 함수 (모든 모드)
    │   ├── load_config()
    │   ├── log_message()
    │   ├── error_handler()
    │   └── detect_os()
    │
    ├── gateway.sh          # Gateway 모드 전용
    │   ├── save_execution_log() ⭐ kFactor=giipagent
    │   ├── save_gateway_status() ⭐ kFactor=gateway_status
    │   ├── sync_gateway_servers()
    │   └── execute_gateway_cycle()
    │
    ├── normal.sh           # Normal 모드 전용
    │   ├── run_normal_mode()
    │   ├── save_execution_log() ⭐ kFactor=giipagent
    │   ├── fetch_queue()
    │   └── execute_script()
    │
    └── db_clients.sh       # DB 클라이언트 (Gateway만)
        ├── check_db_clients()
        └── get_db_client_versions()
```

---

## 🎯 핵심 요약

1. **startup 로깅은 1번만**:
   - Gateway: giipAgent3.sh Line 203
   - Normal: lib/normal.sh Line 216

2. **버전 추적**:
   - GIT_COMMIT, FILE_MODIFIED 환경변수 사용
   - giipAgent3.sh Line 103-119에서 export

3. **모듈 로드**:
   - common.sh: 항상
   - gateway.sh, db_clients.sh: Gateway 모드
   - normal.sh: Normal 모드

4. **KVS 함수**:
   - save_execution_log: giipagent factor (실행 이력)
   - save_gateway_status: gateway_status factor (상태 정보)

5. **사양서 업데이트**:
   - 모듈 추가/수정 시 이 문서 업데이트 필수!

---

**✅ 이 사양서를 먼저 확인하면 소스 코드를 읽지 않고도 구조 파악 가능!**
