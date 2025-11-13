# DPA 스크립트 Gateway 통합 분석 및 수정 계획

## 📋 현황 분석

### 1. 기존 DPA 스크립트 구조

#### 파일 목록
- **dpa-put-mysql.sh**: MySQL 성능 데이터 수집 (독립 실행)
- **dpa-put-mssql.sh**: MS SQL Server 성능 데이터 수집 (독립 실행)
- **dpa-managed-databases.sh**: 통합 스크립트 (Gateway 연동 의도)

#### 현재 문제점
1. ❌ **독립 실행 구조**: `dpa-put-mysql.sh`, `dpa-put-mssql.sh`가 giipAgent.cnf의 하드코딩된 접속 정보 사용
2. ❌ **API 미스매치**: `ManagedDatabaseListForAgent` API 호출하지만 실제로는 `GatewayManagedDatabaseListbySk` 사용해야 함
3. ❌ **중복 구현**: Health Check와 DPA 수집이 별도 스크립트로 분리됨
4. ⚠️ **미완성**: `dpa-managed-databases.sh`는 구조는 있지만 MySQL DPA 수집 로직 누락

### 2. Gateway 서버 현재 구조

**giipAgent3.sh** → **lib/check_managed_databases.sh**
- ✅ API 호출: `GatewayManagedDatabaseListbySk` (올바른 API)
- ✅ 접속 정보: tManagedDatabase에서 복호화된 정보 수신
- ✅ Health Check: 연결 테스트 + 응답 시간 측정
- ✅ Performance Metrics: MySQL 기본 성능 지표 (threads, queries, uptime)
- ❌ **DPA 데이터 없음**: 느린 쿼리, 세션 상세, 부하 분석 미수집

### 3. DPA 데이터 수집 항목 (기존 스크립트 기준)

#### MySQL
```sql
-- 현재 실행 중인 느린 쿼리 (50초 이상)
SELECT 
    host, user, state, time as cpu_time,
    command, info as query_text
FROM information_schema.processlist
WHERE command != 'Sleep'
  AND user != 'system user'
  AND time > 50
ORDER BY time DESC
LIMIT 100
```

#### MS SQL Server
```sql
-- CPU 시간 50초 이상 실행 중인 쿼리
SELECT 
    s.host_name, s.login_name, r.status, r.cpu_time,
    r.reads, r.writes, r.logical_reads,
    r.start_time, r.command, t.text as query_text
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE s.is_user_process = 1
  AND r.cpu_time > 50000  -- 밀리초
ORDER BY r.cpu_time DESC
FOR JSON PATH
```

### 4. KVS 업로드 형식

**기존 독립 스크립트**:
```
KVSPut lssn {lssn} sqlnetinv
```

**제안 Gateway 통합**:
```
KVSPut lssn {lssn} managed_db_dpa
```

**JSON 구조**:
```json
{
  "collected_at": "2025-11-13T20:30:00",
  "collector_host": "infraops01.istyle.local",
  "gateway_lssn": 71240,
  "databases": {
    "p-cnsldb01m": {
      "mdb_id": 4,
      "db_type": "MySQL",
      "db_host": "p-cnsldb01m",
      "slow_queries": [
        {
          "host_name": "app-server01",
          "login_name": "dbuser",
          "status": "executing",
          "cpu_time": 75,
          "command": "SELECT",
          "query_text": "SELECT * FROM large_table WHERE..."
        }
      ],
      "session_count": 2,
      "total_cpu_time": 150
    }
  }
}
```

---

## 🎯 수정 계획

### Phase 1: lib/check_managed_databases.sh 확장

#### 목표
기존 Health Check + Performance Metrics에 **DPA 느린 쿼리 수집** 추가

#### 수정 내용

1. **MySQL DPA 쿼리 추가**
   - 위치: `check_mysql_health()` 함수 직후
   - 함수명: `collect_mysql_dpa()`
   - 수집 조건: `time > 50` (50초 이상 실행 중인 쿼리)
   - 출력: JSON 배열 (쿼리 목록)

2. **MSSQL DPA 쿼리 추가**
   - 위치: `check_mssql_health()` 함수 직후
   - 함수명: `collect_mssql_dpa()` (이미 존재, 검증 필요)
   - 수집 조건: `cpu_time > 50000` (50초 = 50,000ms)
   - 출력: JSON 배열

3. **PostgreSQL DPA 쿼리 추가** (향후)
   - 함수명: `collect_postgresql_dpa()`
   - 쿼리: `pg_stat_activity` WHERE `state = 'active'` AND `query_start < now() - interval '50 seconds'`

4. **KVS 업로드 통합**
   - 기존: `managed_db_check` (Health + Performance)
   - 추가: `managed_db_dpa` (느린 쿼리 데이터)
   - 또는 통합: `managed_db_check`에 `slow_queries` 필드 추가

#### 장점
- ✅ 단일 스크립트에서 모든 데이터 수집
- ✅ API 호출 1회 (효율적)
- ✅ 접속 정보 중앙 관리 (tManagedDatabase)
- ✅ 기존 Health Check 로직 재사용

#### 단점
- ⚠️ `check_managed_databases.sh` 스크립트 복잡도 증가
- ⚠️ 실행 시간 증가 (느린 쿼리 수집 추가)

---

### Phase 2: 독립 실행 모드 유지 (선택적)

#### 목표
기존 `dpa-put-mysql.sh`, `dpa-put-mssql.sh` 스크립트를 Gateway 정보 기반으로 실행 가능하도록 수정

#### 수정 내용

1. **API 호출 변경**
   - 현재: `ManagedDatabaseListForAgent` (존재하지 않음)
   - 수정: `GatewayManagedDatabaseListbySk` (giipAgent3.sh와 동일)

2. **파라미터 우선순위**
   ```bash
   # 1순위: 명령줄 인자
   bash dpa-put-mysql.sh -h host -u user -p pass
   
   # 2순위: tManagedDatabase API 조회
   bash dpa-put-mysql.sh --use-managed-db --mdb-id 4
   
   # 3순위: giipAgent.cnf 설정 파일
   bash dpa-put-mysql.sh
   ```

3. **Cron 독립 실행**
   ```bash
   # Gateway와 별도로 DPA만 5분마다 실행
   */5 * * * * /opt/giipAgentLinux/giipscripts/dpa-put-mysql.sh --use-managed-db --mdb-id 4
   ```

#### 장점
- ✅ 유연성: Gateway 없이도 독립 실행 가능
- ✅ 기존 사용자 혼란 방지
- ✅ 테스트 용이

#### 단점
- ⚠️ 유지보수 복잡도 증가 (2개 방식 병행)
- ⚠️ API 호출 중복 가능성

---

## 🚀 권장 수정 방안 (Phase 1 우선)

### 1단계: lib/check_managed_databases.sh에 DPA 수집 추가

**파일**: `giipAgentLinux/lib/check_managed_databases.sh`

**추가할 함수**:

```bash
# ============================================================
# MySQL DPA 데이터 수집 (느린 쿼리)
# ============================================================
collect_mysql_dpa() {
    local host="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    local database="$5"
    
    if ! command -v mysql &>/dev/null; then
        echo "[]"
        return
    fi
    
    # 50초 이상 실행 중인 쿼리 수집
    local query="
SELECT 
    COALESCE(pl.host, 'unknown') as host_name,
    COALESCE(pl.user, 'unknown') as login_name,
    COALESCE(pl.state, 'unknown') as status,
    COALESCE(pl.time, 0) as cpu_time,
    0 as reads,
    0 as writes,
    0 as logical_reads,
    NOW() as start_time,
    COALESCE(pl.command, 'unknown') as command,
    COALESCE(pl.info, '') as query_text
FROM information_schema.processlist pl
WHERE pl.command != 'Sleep'
  AND pl.user != 'system user'
  AND pl.time > 50
ORDER BY pl.time DESC
LIMIT 100;
"
    
    local result
    result=$(mysql -h"$host" -P"$port" -u"$user" -p"$password" \
        ${database:+-D"$database"} \
        -sN -e "$query" 2>&1 | grep -v "Warning")
    
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        # Tab-separated values를 JSON 배열로 변환
        echo "$result" | python3 -c '
import sys, json
queries = []
for line in sys.stdin:
    fields = line.strip().split("\t")
    if len(fields) >= 10:
        queries.append({
            "host_name": fields[0],
            "login_name": fields[1],
            "status": fields[2],
            "cpu_time": int(fields[3]),
            "reads": int(fields[4]),
            "writes": int(fields[5]),
            "logical_reads": int(fields[6]),
            "start_time": fields[7],
            "command": fields[8],
            "query_text": fields[9]
        })
print(json.dumps(queries))
'
    else
        echo "[]"
    fi
}
```

**메인 로직 수정**:

```bash
# 기존 health check 후 DPA 수집 추가
case "$db_type" in
    MySQL|MariaDB)
        # ... 기존 Health Check ...
        
        if [ "$check_status" = "success" ]; then
            # Performance metrics (기존)
            # ... performance_json 수집 ...
            
            # DPA 느린 쿼리 수집 (NEW)
            local slow_queries_json
            slow_queries_json=$(collect_mysql_dpa "$db_host" "$db_port" "$db_user" "$db_password" "$db_database")
            
            local slow_query_count=$(echo "$slow_queries_json" | jq '. | length')
            if [ "$slow_query_count" -gt 0 ]; then
                echo "[${logdt}] [Gateway] ⚠️  Found $slow_query_count slow queries" >> $LogFileName
            fi
        fi
        ;;
esac
```

**KVS 업로드 수정**:

```bash
# 기존 managed_db_check에 slow_queries 필드 추가
local details_json
details_json=$(jq -n \
    --argjson mdb_id "$mdb_id" \
    --arg db_name "$db_name" \
    --arg db_type "$db_type" \
    --arg check_status "$check_status" \
    --arg check_message "$check_message" \
    --arg check_time "$(date '+%Y-%m-%d %H:%M:%S')" \
    --argjson response_time_ms "$response_time" \
    --argjson performance "$performance_json" \
    --argjson slow_queries "$slow_queries_json" \
    '{
        mdb_id: $mdb_id,
        db_name: $db_name,
        db_type: $db_type,
        check_status: $check_status,
        check_message: $check_message,
        check_time: $check_time,
        response_time_ms: $response_time_ms,
        performance: $performance,
        slow_queries: $slow_queries
    }')
```

---

### 2단계: MSSQL DPA 검증 및 PostgreSQL 추가

**MSSQL**:
- `dpa-managed-databases.sh`의 `collect_mssql_dpa()` 함수 복사
- `lib/check_managed_databases.sh`로 통합

**PostgreSQL**:
```bash
collect_postgresql_dpa() {
    local host="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    local database="$5"
    
    if ! command -v psql &>/dev/null; then
        echo "[]"
        return
    fi
    
    export PGPASSWORD="$password"
    local query="
SELECT 
    COALESCE(client_addr::text, 'localhost') as host_name,
    COALESCE(usename, 'unknown') as login_name,
    COALESCE(state, 'unknown') as status,
    EXTRACT(EPOCH FROM (now() - query_start))::int as cpu_time,
    0 as reads,
    0 as writes,
    0 as logical_reads,
    query_start::text as start_time,
    'QUERY' as command,
    COALESCE(query, '') as query_text
FROM pg_stat_activity
WHERE state = 'active'
  AND usename != 'postgres'
  AND query_start < now() - interval '50 seconds'
ORDER BY query_start
LIMIT 100;
"
    
    local result
    result=$(psql -h "$host" -p "$port" -U "$user" -d "$database" \
        -t -A -F $'\t' -c "$query" 2>&1)
    unset PGPASSWORD
    
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        echo "$result" | python3 -c '
import sys, json
queries = []
for line in sys.stdin:
    fields = line.strip().split("\t")
    if len(fields) >= 10:
        queries.append({
            "host_name": fields[0],
            "login_name": fields[1],
            "status": fields[2],
            "cpu_time": int(float(fields[3])),
            "reads": 0,
            "writes": 0,
            "logical_reads": 0,
            "start_time": fields[7],
            "command": fields[8],
            "query_text": fields[9]
        })
print(json.dumps(queries))
'
    else
        echo "[]"
    fi
}
```

---

### 3단계: 기존 독립 스크립트 Deprecated 표시

**dpa-put-mysql.sh**, **dpa-put-mssql.sh**:
```bash
#!/bin/bash
echo "=========================================="
echo "⚠️  DEPRECATED NOTICE"
echo "=========================================="
echo "This script is deprecated and will be removed in a future version."
echo ""
echo "Please use giipAgent3.sh with Gateway mode instead:"
echo "  cd /opt/giipAgentLinux"
echo "  sudo bash giipAgent3.sh"
echo ""
echo "DPA data is now automatically collected through managed database monitoring."
echo "=========================================="
echo ""
echo "To continue using this script (legacy mode), press Ctrl+C within 10 seconds..."
sleep 10

# ... 기존 코드 유지 ...
```

---

## 📊 예상 결과

### KVS 데이터 구조 (통합 후)

**kFactor**: `managed_db_check`

**kValue**:
```json
{
  "event_type": "managed_db_check",
  "timestamp": "2025-11-13 20:30:00",
  "lssn": 71240,
  "hostname": "infraops01.istyle.local",
  "mode": "gateway",
  "version": "3.00",
  "details": {
    "mdb_id": 4,
    "db_name": "p-cnsldb01m",
    "db_type": "MySQL",
    "check_status": "success",
    "check_message": "Connection successful",
    "check_time": "2025-11-13 20:30:00",
    "response_time_ms": 95,
    "performance": {
      "threads_connected": 620,
      "threads_running": 4,
      "questions": 50123456,
      "slow_queries": 731,
      "uptime": 252000
    },
    "slow_queries": [
      {
        "host_name": "app-server01:45678",
        "login_name": "dbuser",
        "status": "executing",
        "cpu_time": 75,
        "reads": 0,
        "writes": 0,
        "logical_reads": 0,
        "start_time": "2025-11-13 20:28:45",
        "command": "SELECT",
        "query_text": "SELECT * FROM large_table WHERE created_at > '2025-01-01' ORDER BY id DESC"
      }
    ]
  }
}
```

---

## ✅ 작업 체크리스트

### Phase 1 (우선 구현)
- [ ] `collect_mysql_dpa()` 함수 추가
- [ ] `collect_mssql_dpa()` 함수 검증 및 추가
- [ ] 메인 로직에 DPA 수집 통합
- [ ] KVS 업로드 JSON에 `slow_queries` 필드 추가
- [ ] 테스트: MySQL DPA 데이터 수집 확인
- [ ] 테스트: MSSQL DPA 데이터 수집 확인
- [ ] 문서 업데이트: lib/check_managed_databases.sh 기능 설명

### Phase 2 (선택적)
- [ ] `collect_postgresql_dpa()` 함수 추가
- [ ] Redis/MongoDB DPA 수집 검토 (해당 시)
- [ ] 기존 독립 스크립트에 DEPRECATED 경고 추가
- [ ] DPA_SCRIPTS.md 문서 업데이트 (Gateway 통합 안내)

### Phase 3 (정리)
- [ ] 독립 스크립트 완전 제거 검토
- [ ] 성능 테스트: 대량 slow query 발생 시 영향 확인
- [ ] 로그 파일 크기 모니터링
- [ ] KVS 데이터 크기 검토 (대량 slow query 시)

---

## 🔍 추가 고려사항

### 1. 성능 임계값 설정
- 현재: 50초 이상 쿼리만 수집
- 제안: giipAgent.cnf에서 설정 가능하도록
  ```ini
  SlowQueryThresholdSeconds=50
  ```

### 2. 수집 개수 제한
- 현재: LIMIT 100
- 제안: 설정 파일에서 조정 가능
  ```ini
  MaxSlowQueries=100
  ```

### 3. 민감 정보 필터링
- 쿼리 텍스트에 비밀번호, 개인정보 포함 가능
- 제안: 정규식으로 필터링 또는 일부 마스킹
  ```bash
  query_text=$(echo "$query_text" | sed 's/password.*=.*[,;]/password=***/gi')
  ```

### 4. 데이터 보존 기간
- KVS에 저장되는 slow query 데이터 보존 기간 설정
- 제안: 7일 또는 30일 자동 정리

---

## 📝 다음 단계

1. **승인 대기**: 위 수정 계획 검토 및 승인
2. **Phase 1 구현**: `lib/check_managed_databases.sh`에 DPA 수집 추가
3. **테스트**: infraops01 서버에서 실행 및 KVS 데이터 확인
4. **검증**: database-management 페이지에서 slow query 데이터 표시 확인
5. **문서화**: 변경 내역 및 사용 가이드 업데이트

---

## 승인 요청

위 분석 및 수정 계획을 검토 후, 다음 중 선택해주세요:

**Option A (권장)**: Phase 1 우선 구현
- `lib/check_managed_databases.sh`에 DPA 수집 통합
- 단일 스크립트에서 Health + Performance + DPA 모두 수집

**Option B**: Phase 1 + Phase 2 동시 구현
- Gateway 통합 + 독립 스크립트 유지 (양쪽 지원)

**Option C**: 수정 계획 변경
- 다른 접근 방식 제안

승인되면 즉시 구현을 시작하겠습니다.
