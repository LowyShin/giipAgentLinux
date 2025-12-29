# MySQL 서버 리스트 수집 흐름 (Database Check)

## 📋 개요
Gateway Mode에서 관리 대상 MySQL/MariaDB 서버 목록을 조회하고 상태를 수집하는 전체 흐름

---

## 🔄 전체 흐름도

```
giipAgent3.sh (Main)
  ↓
gateway_mode.sh
  ↓
gateway-check-db.sh
  ↓
check_managed_databases() ← lib/check_managed_databases.sh
  ↓
  ├─ 1. API 호출 (GatewayManagedDatabaseList)
  ├─ 2. JSON 파싱 (parse_managed_db_list.py)
  ├─ 3. DB 타입 추출 (extract_db_types.py)
  ├─ 4. DB 클라이언트 설치 확인
  ├─ 5. DPA 수집 (dpa_mysql.sh, dpa_mssql.sh 등)
  └─ 6. Health Check (net3d_db.sh, http_health_check.sh)
```

---

## 📡 1. API 호출

### 호출 위치
**파일**: `lib/check_managed_databases.sh`  
**함수**: `check_managed_databases()`  
**라인**: L24-29

### 호출 내용
```bash
local text="GatewayManagedDatabaseList lssn"
local jsondata="{\"lssn\":${lssn}}"

wget -O "$temp_file" --quiet \
    --post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
    --header="Content-Type: application/x-www-form-urlencoded" \
    "${apiaddrv2}?code=${apiaddrcode}" \
    --no-check-certificate
```

### API 파라미터
| 파라미터 | 값 | 설명 |
|---------|-----|------|
| `text` | `GatewayManagedDatabaseList lssn` | API 명령 |
| `token` | `${sk}` | SK 인증 토큰 (giipAgent.cnf) |
| `jsondata` | `{"lssn":71240}` | Gateway 서버의 LSSN |
| `code` | `${apiaddrcode}` | API 코드 (giipAgent.cnf) |

### API 엔드포인트
```
${apiaddrv2}?code=${apiaddrcode}
→ https://giipfaw.azurewebsites.net/api/giipApiSk2?code=...
```

### 예상 응답 (JSON)
```json
{
  "data": [
    {
      "mdb_id": 1,
      "db_type": "MySQL",
      "db_host": "p-cnsldb01m",
      "db_port": 3306,
      "db_name": "consult_db",
      "db_user": "consult",
      "db_pass": "encrypted_password",
      "lssn": 71221
    },
    {
      "mdb_id": 2,
      "db_type": "MariaDB",
      "db_host": "p-cnsldb02m",
      ...
    }
  ]
}
```

---

## 💾 2. 데이터 저장

### 임시 파일
**파일명**: `/tmp/managed_db_api_response_$$.json`  
**생성**: check_managed_databases() L20  
**내용**: API 응답 JSON (원본)  
**삭제**: L41에서 삭제 (파싱 후)  
**예시**: `/tmp/managed_db_api_response_12345.json`

### 변수 저장
**변수명**: `$db_list`  
**파일**: `lib/check_managed_databases.sh` L38  
**형식**: JSON Lines (각 DB 정보가 한 줄씩)
```
{"mdb_id":1,"db_type":"MySQL",...}
{"mdb_id":2,"db_type":"MariaDB",...}
```

---

## 📖 3. 데이터 읽기

### 3-1. JSON 파싱
**호출 위치**: `lib/check_managed_databases.sh` L38

```bash
local db_list=$(cat "$temp_file" | python3 "${SCRIPT_DIR}/parse_managed_db_list.py")
```

**스크립트**: `lib/parse_managed_db_list.py`  
**기능**: API 응답에서 `data` 배열 추출, 각 항목을 JSON Line으로 출력

**Python 코드**:
```python
import json, sys
data = json.load(sys.stdin)
if 'data' in data and isinstance(data['data'], list):
    for item in data['data']:
        print(json.dumps(item))
```

### 3-2. DB 타입 추출
**호출 위치**: `lib/check_managed_databases.sh` L52

```bash
local db_types=$(echo "$db_list" | python3 "${SCRIPT_DIR}/extract_db_types.py")
```

**스크립트**: `lib/extract_db_types.py`  
**기능**: `db_list`에서 `db_type` 필드만 중복 제거하여 추출  
**출력**: `MariaDB MySQL PostgreSQL` (공백으로 구분)

**Python 코드**:
```python
import json, sys
db_types = set()
for line in sys.stdin:
    if line.strip():
        data = json.loads(line)
        db_type = data.get('db_type', '')
        if db_type:
            db_types.add(db_type)
print(' '.join(sorted(db_types)))
```

### 3-3. DB 타입별 처리
**호출 위치**: `lib/check_managed_databases.sh` L56-97

```bash
for db_type in $db_types; do
    case "$db_type" in
        MySQL|MariaDB)
            # MySQL 클라이언트 확인/설치
            if ! command -v mysql > /dev/null; then
                check_mysql_client
            fi
            ;;
        PostgreSQL)
            # PostgreSQL 클라이언트 확인
            ;;
        MSSQL)
            # MSSQL 클라이언트 확인/설치
            ;;
    esac
done
```

### 3-4. 각 DB별 데이터 수집
**호출 위치**: `lib/check_managed_databases.sh` L100-200+

```bash
echo "$db_list" | while IFS= read -r db_json; do
    # 각 DB 정보 파싱
    mdb_id=$(echo "$db_json" | jq -r '.mdb_id')
    db_type=$(echo "$db_json" | jq -r '.db_type')
    db_host=$(echo "$db_json" | jq -r '.db_host')
    ...
    
    # DB 타입별 DPA 수집
    case "$db_type" in
        MySQL|MariaDB)
            collect_mysql_dpa "$db_host" "$db_port" "$db_user" "$db_pass" "$db_name"
            ;;
        MSSQL)
            collect_mssql_dpa ...
            ;;
    esac
    
    # Health Check
    perform_health_check "$db_host" "$db_port"
done
```

---

## 🗂️ 관련 파일

| 파일 | 역할 | 사용하는 구문 |
|------|------|------------|
| `scripts/gateway-check-db.sh` | Wrapper 스크립트 | L28: `check_managed_databases` 함수 호출 |
| `lib/check_managed_databases.sh` | 메인 로직 | L17-615: `check_managed_databases()` 함수 정의 |
| `lib/parse_managed_db_list.py` | JSON 파싱 | L38에서 호출: API 응답 → JSON Lines 변환 |
| `lib/extract_db_types.py` | DB 타입 추출 | L52에서 호출: JSON Lines → DB 타입 목록 |
| `lib/dpa_mysql.sh` | MySQL DPA 수집 | `collect_mysql_dpa()` 함수 |
| `lib/dpa_mssql.sh` | MSSQL DPA 수집 | `collect_mssql_dpa()` 함수 |
| `lib/dpa_postgresql.sh` | PostgreSQL DPA 수집 | `collect_postgresql_dpa()` 함수 |
| `lib/net3d_db.sh` | DB Health Check | 연결 상태 확인 |
| `lib/http_health_check.sh` | HTTP Health Check | HTTP 엔드포인트 상태 확인 |

---

## 🔍 데이터 흐름 상세

```
1. API 호출 (wget)
   ↓
   /tmp/tmp.XXXXXX (API 응답 JSON 전체)
   
2. parse_managed_db_list.py (cat → python3)
   ↓
   $db_list (JSON Lines, 메모리)
   {"mdb_id":1,"db_type":"MySQL",...}
   {"mdb_id":2,"db_type":"MariaDB",...}
   
3-a. extract_db_types.py (echo → python3)
     ↓
     $db_types (공백 구분 문자열)
     "MariaDB MySQL PostgreSQL"
     
3-b. while read loop (echo → while)
     ↓
     각 DB 정보를 한 줄씩 처리
     → jq로 필드 추출
     → DPA 수집 함수 호출
     → Health Check 함수 호출
```

---

## 📝 주요 변수

| 변수 | 타입 | 저장 위치 | 내용 |
|------|------|----------|------|
| `$temp_file` | 파일 경로 | L20 | API 응답 JSON 임시 파일 |
| `$db_list` | 문자열 (JSON Lines) | L38 | 파싱된 DB 목록 (각 줄이 하나의 DB) |
| `$db_types` | 문자열 (공백 구분) | L52 | 필요한 DB 타입 목록 |
| `$db_count` | 숫자 | L48 | 총 DB 개수 |

---

**작성**: 2025-12-28 20:27  
**목적**: MySQL 서버 리스트 수집 흐름 명확화  
**사용자 요청**: "무엇을 호출해서 어떤 식으로 저장하고 그걸 어느 파일의 어떤 구문이 읽고 있는지"

---

## 📤 6. 체크 결과 저장 및 전송

### 6-1. 결과 수집
**호출 위치**: `lib/check_managed_databases.sh` L156

```bash
echo "$check_result" >> "$check_results_file"
```

**임시 파일**: `/tmp/db_check_results_$$.jsonl`  
**형식**: JSON Lines (각 DB 체크 결과가 한 줄씩)

**예시**:
```json
{"mdb_id":1,"status":"healthy","message":"Connection successful","response_time_ms":150,"performance_metrics":"{\"threads_connected\":50,...}","db_name":"p-cnsldb01m","db_type":"MySQL"}
{"mdb_id":2,"status":"healthy","message":"Connection successful","response_time_ms":200,"performance_metrics":"{\"threads_connected\":45,...}","db_name":"p-cnsldb02m","db_type":"MySQL"}
```

### 6-2. MdbStatsUpdate 형식 변환
**호출 위치**: `lib/check_managed_databases.sh` L166

```bash
local stats_json=$(cat "$check_results_file" | python3 "${SCRIPT_DIR}/convert_to_mdb_stats.py")
```

**스크립트**: `lib/convert_to_mdb_stats.py`  
**기능**: `perform_check_*` 결과를 `pApiMdbStatsUpdatebySK` 형식으로 변환

**입력**: JSON Lines (각 DB의 check_result)
**출력**: JSON 배열

**출력 형식**:
```json
[
  {
    "mdb_id": 1,
    "uptime": 123456,
    "threads": 50,
    "qps": 1000,
    "buffer_pool": 80.5,
    "cpu": 0,
    "memory": 2048
  },
  {
    "mdb_id": 2,
    "uptime": 123456,
    "threads": 45,
    "qps": 950,
    "buffer_pool": 75.0,
    "cpu": 0,
    "memory": 2048
  }
]
```

**매핑 규칙**:
- `performance_metrics.threads_connected` → `threads`
- `performance_metrics.total_questions` → `qps`
- `performance_metrics.uptime` → `uptime`
- `performance_metrics.buffer_cache_hit_ratio` → `buffer_pool`
- `performance_metrics.database_size_mb` → `memory`

### 6-3. API 전송
**호출 위치**: `lib/check_managed_databases.sh` L169-180

```bash
wget -O - --quiet \
  --post-data="text=MdbStatsUpdate jsondata&token=${sk}&jsondata=${stats_json}" \
  --header="Content-Type: application/x-www-form-urlencoded" \
  "${apiaddrv2}?code=${apiaddrcode}" \
  --no-check-certificate 2>&1
```

**API**: `MdbStatsUpdate jsondata`  
**SP**: `pApiMdbStatsUpdatebySK`  
**파라미터**:
- `@sk`: Secret Key (Gateway 인증)
- `@jsondata`: 변환된 stats JSON 배열

**처리**:
1. `tManagedDatabaseStats` - 성능 히스토리 저장
2. `tManagedDatabase` - 현재 상태 업데이트 (last_check_dt, last_check_status, performance_metrics)
3. `tKVS` - Time Travel용 상태 로그 저장
4. `tNet3dTimeline` - Critical 상태 이벤트 저장

### 6-4. DB 연결 정보 저장
**호출 위치**: `lib/db_check_mysql.sh` L53-56 (각 perform_check_* 함수에서)

```bash
local net3d_json=$(collect_net3d_mysql "$db_host" "$db_port" "$db_user" "$db_password" "$db_database")
if [ -n "$net3d_json" ] && [ "$net3d_json" != "[]" ]; then
    kvs_put "database" "$mdb_id" "db_connections" "$net3d_json"
fi
```

**API**: `KVSPut kType kKey kFactor kValue`  
**SP**: `pApiKVSPutbySk`

**파라미터**:
- `kType`: `database`
- `kKey`: `mdb_id` (예: `1`)
- `kFactor`: `db_connections`
- `kValue`: Net3D 연결 정보 JSON 배열

**저장 위치**: `tKVS` 테이블

**kValue 형식**:
```json
[
  {
    "client_net_address": "192.168.1.100",
    "program_name": "java",
    "conn_count": 5,
    "cpu_load": 1250,
    "last_sql": "SELECT * FROM users WHERE ..."
  }
]
```

---

## 📋 7. NN 버그 우회 방법

**문제**: run.ps1이 `text=MdbStatsUpdate jsondata`를 받으면 `NN'[{...}]'` 생성

**해결**: Agent에서 `text=MdbStatsUpdate 0` 전송

**파일**: 
- `check_managed_databases.sh` L175
- `DbMonitor.ps1` L224

**상세**: [NN_BUG_WORKAROUND.md](./NN_BUG_WORKAROUND.md)

---

## 📋 7. 임시 파일 정리

**파일들**:
- `/tmp/managed_db_api_response_$$.json` - API 응답
- `/tmp/db_check_results_$$.jsonl` - 체크 결과

**정리 시점**: 
- 스크립트 시작 시 `lib/cleanup.sh` 실행
- 이전 실행의 임시 파일들 삭제

**정리 함수**: `cleanup_old_temp_files` (L78-82)

---

## 🔄 8. 전체 흐름 요약

```
1. API 호출 (GatewayManagedDatabaseList)
   └─> /tmp/managed_db_api_response_$$.json

2. JSON 파싱
   └─> db_list (JSON Lines)

3. DB 타입별 Client 설치 체크

4. 각 DB 순회하며 체크
   ├─> perform_check_mysql()
   ├─> perform_check_postgresql()
   ├─> perform_check_mssql()
   ├─> collect_net3d_*() → kvs_put (개별)
   └─> 결과 → /tmp/db_check_results_$$.jsonl

5. 배치 전송
   ├─> convert_to_mdb_stats.py
   └─> MdbStatsUpdate API → tManagedDatabase 업데이트

6. Network-topology 페이지에 표시
   ├─> tManagedDatabase (성능, 상태)
   └─> tKVS (db_connections)
```

---

## 📌 참고 사항

### Windows Agent 호환성
- **giipAgentWin**도 동일한 SP 사용 (`pApiMdbStatsUpdatebySK`)
- 데이터 형식 완전 호환
- Linux/Windows Agent 결과가 동일한 테이블에 저장됨

### Time Travel 지원
- `tKVS`에 status_log 저장
- `kRegdt` (UTC) 기준으로 과거 상태 조회 가능
- Network-topology에서 Time Travel 기능 사용 가능

### 모니터링
- Critical 상태 시 `tNet3dTimeline`에 이벤트 자동 생성
- CPU 80% 이상 또는 Threads 50개 이상 시 자동 감지
