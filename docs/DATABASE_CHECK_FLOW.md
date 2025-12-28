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
