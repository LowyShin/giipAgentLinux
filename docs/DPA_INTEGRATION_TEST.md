# DPA (Database Performance Analysis) 통합 완료

## ⚠️ 중요 사양

### KVS 저장 정책

**필수 규칙**:
1. **DPA 데이터는 항상 저장**: 느린 쿼리가 있든 없든 **매 실행마다** KVS에 저장
2. **kFactor**: `sqlnetinv` (기존 독립 DPA 스크립트와 동일)
3. **느린 쿼리가 없을 경우**: 빈 배열 `[]`을 저장
4. **저장 시점**: DB 연결 성공 후 DPA 수집 직후

### 데이터 분리

- **kFactor="giipagent"**: Health Check + Performance 메트릭
- **kFactor="sqlnetinv"**: DPA 느린 쿼리 데이터 (항상 저장)

---

## 변경 내용

### 1. 신규 파일 생성

#### `lib/dpa_mysql.sh`
- MySQL 느린 쿼리 수집 함수 (`collect_mysql_dpa`)
- 수집 조건: 실행 시간 50초 이상
- 반환: JSON 배열 (최대 100개 쿼리)

#### `lib/dpa_mssql.sh`
- MS SQL Server 느린 쿼리 수집 함수 (`collect_mssql_dpa`)
- 수집 조건: CPU 시간 50,000ms (50초) 이상
- 반환: JSON 배열

#### `lib/dpa_postgresql.sh`
- PostgreSQL 느린 쿼리 수집 함수 (`collect_postgresql_dpa`)
- 수집 조건: 실행 시간 50초 이상
- 반환: JSON 배열

### 2. 기존 파일 수정

#### `lib/check_managed_databases.sh`
- DPA 모듈 자동 로드 (source)
- 각 DB 타입별로 DPA 수집 추가:
  - MySQL: `collect_mysql_dpa()` 호출
  - MSSQL: `collect_mssql_dpa()` 호출
  - PostgreSQL: `collect_postgresql_dpa()` 호출
- KVS 업로드 JSON에 `slow_queries` 필드 추가
- 느린 쿼리 감지 시 로그 출력

#### `giipAgent3.sh`
- 변경 없음 (기존 `check_managed_databases()` 호출 유지)

---

## 데이터 구조

### 1. Health Check + Performance (kFactor=giipagent)

**저장 조건**: DB 연결 성공 시

**kType**: `lssn`
**kKey**: `{lssn}`
**kFactor**: `giipagent`

**kValue (managed_db_check)**:
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
    "slow_queries": 731,
    "uptime": 252000
  }
}
```

### 2. DPA 느린 쿼리 데이터 (kFactor=sqlnetinv)

**⚠️ 중요**: **항상 저장됨** (느린 쿼리 유무와 관계없이 매 실행마다)

**저장 조건**: DB 연결 성공 시 (항상)

**kType**: `lssn`
**kKey**: `{lssn}`
**kFactor**: `sqlnetinv`

**kValue** (느린 쿼리가 **있을 때**):
```json
{
  "collected_at": "2025-11-13 20:30:00",
  "collector_host": "infraops01.istyle.local",
  "lssn": 71240,
  "db_name": "p-cnsldb01m",
  "dpa_data": [
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
      "query_text": "SELECT * FROM large_table WHERE..."
    }
  ]
}
```

**kValue** (느린 쿼리가 **없을 때**):
```json
{
  "collected_at": "2025-11-13 20:30:00",
  "collector_host": "infraops01.istyle.local",
  "lssn": 71240,
  "db_name": "p-cnsldb01m",
  "dpa_data": []
}
```

**⚠️ 핵심**: 빈 배열 `[]`이라도 **반드시 저장**되어야 함
```

---

## 테스트 방법

### infraops01 서버에서 실행

```bash
cd /opt/giipAgentLinux
sudo bash giipAgent3.sh
```

### 예상 로그 출력

```
[Gateway] 🔍 Checking managed databases...
[Gateway] 📊 Found 1 managed database(s)
[Gateway] 📋 Required DB types: MySQL
[Gateway] 🔍 DEBUG: Analyzing DB list...
  - p-cnsldb01m: MySQL
[20251113203000] [Gateway] Checking DB: p-cnsldb01m (mdb_id:4, type:MySQL, host:p-cnsldb01m:3306)
[20251113203000] [Gateway]   ✅ MySQL connection OK
[20251113203001] [Gateway]   🔍 Collecting MySQL DPA data...
[DPA] Saving DPA data for p-cnsldb01m to KVS (kFactor=sqlnetinv)...
[DPA] ✅ Saved DPA data for p-cnsldb01m
[20251113203002] [Gateway]   ⚠️  Found 3 slow queries (>50s)
[20251113203002] [Gateway]   → Status: success - Connection successful (95ms)
```

**느린 쿼리가 없을 경우**:
```
[20251113203001] [Gateway]   🔍 Collecting MySQL DPA data...
[DPA] Saving DPA data for p-cnsldb01m to KVS (kFactor=sqlnetinv)...
[DPA] ✅ Saved DPA data for p-cnsldb01m
[20251113203002] [Gateway]   ✓ No slow queries detected
```

**⚠️ 중요**: 느린 쿼리가 없어도 `[DPA] ✅ Saved DPA data` 메시지가 출력되어야 함

### KVS 데이터 확인

```powershell
# Windows에서 실행
cd c:\Users\lowys\Downloads\projects\giipprj\giipdb

# 1. Health Check + Performance 확인 (kFactor=giipagent)
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71240 -KFactor giipagent -Top 1

# 2. DPA 느린 쿼리 데이터 확인 (kFactor=sqlnetinv) ⭐ 중요
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71240 -KFactor sqlnetinv -Top 1
```

**확인 항목**:
1. ✅ `sqlnetinv` 데이터가 **매번 저장되는지 확인**
2. ✅ 느린 쿼리가 없을 때 `dpa_data: []` (빈 배열) 확인
3. ✅ 느린 쿼리가 있을 때 배열에 데이터 존재 확인
4. ✅ `collected_at` 타임스탬프가 매 실행마다 갱신되는지 확인

---

## 수집 쿼리 상세

### MySQL
```sql
SELECT 
    COALESCE(pl.host, 'unknown') as host_name,
    COALESCE(pl.user, 'unknown') as login_name,
    COALESCE(pl.state, 'unknown') as status,
    COALESCE(pl.time, 0) as cpu_time,
    0 as reads,
    0 as writes,
    0 as logical_reads,
    DATE_FORMAT(NOW() - INTERVAL pl.time SECOND, '%Y-%m-%d %H:%i:%s') as start_time,
    COALESCE(pl.command, 'unknown') as command,
    COALESCE(SUBSTRING(pl.info, 1, 500), '') as query_text
FROM information_schema.processlist pl
WHERE pl.command != 'Sleep'
  AND pl.user NOT IN ('system user', 'event_scheduler')
  AND pl.time >= 50
ORDER BY pl.time DESC
LIMIT 100;
```

### MS SQL Server
```sql
SELECT 
    ISNULL(s.host_name, 'unknown') as host_name,
    ISNULL(s.login_name, 'unknown') as login_name,
    ISNULL(r.status, 'unknown') as status,
    ISNULL(r.cpu_time / 1000, 0) as cpu_time,
    ISNULL(r.reads, 0) as reads,
    ISNULL(r.writes, 0) as writes,
    ISNULL(r.logical_reads, 0) as logical_reads,
    CONVERT(varchar, r.start_time, 120) as start_time,
    ISNULL(r.command, 'unknown') as command,
    ISNULL(SUBSTRING(t.text, 1, 500), '') as query_text
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE s.is_user_process = 1
  AND r.cpu_time >= 50000
ORDER BY r.cpu_time DESC;
```

### PostgreSQL
```sql
SELECT 
    COALESCE(client_addr::text, 'localhost') as host_name,
    COALESCE(usename, 'unknown') as login_name,
    COALESCE(state, 'unknown') as status,
    EXTRACT(EPOCH FROM (now() - query_start))::int as cpu_time,
    0 as reads,
    0 as writes,
    0 as logical_reads,
    to_char(query_start, 'YYYY-MM-DD HH24:MI:SS') as start_time,
    'QUERY' as command,
    COALESCE(SUBSTRING(query, 1, 500), '') as query_text
FROM pg_stat_activity
WHERE state = 'active'
  AND usename NOT IN ('postgres', 'rdsadmin')
  AND query_start < now() - interval '50 seconds'
  AND query NOT LIKE '%pg_stat_activity%'
ORDER BY query_start
LIMIT 100;
```

---

## 성능 영향

- **추가 실행 시간**: DB당 약 0.5~2초 (느린 쿼리가 많을 경우)
- **네트워크 부하**: 쿼리 텍스트 최대 500자로 제한
- **DB 부하**: SELECT 쿼리만 실행 (읽기 전용)
- **KVS 저장**: 매 실행마다 2개 kFactor에 저장 (giipagent + sqlnetinv)

---

## 저장 정책 상세

### 저장 타이밍

| 상황 | kFactor=giipagent | kFactor=sqlnetinv |
|------|-------------------|-------------------|
| DB 연결 성공 + 느린 쿼리 있음 | ✅ 저장 | ✅ 저장 (dpa_data=[...]) |
| DB 연결 성공 + 느린 쿼리 없음 | ✅ 저장 | ✅ 저장 (dpa_data=[]) |
| DB 연결 실패 | ✅ 저장 (에러 상태) | ❌ 저장 안 함 |

**핵심 규칙**: DB 연결만 성공하면 **sqlnetinv는 무조건 저장**

---

## 향후 개선 사항

1. **임계값 설정 가능화**
   - giipAgent.cnf에 `DPA_THRESHOLD_SECONDS=50` 추가

2. **수집 개수 제한**
   - giipAgent.cnf에 `DPA_MAX_QUERIES=100` 추가

3. **민감 정보 필터링**
   - 쿼리 텍스트에서 비밀번호 패턴 마스킹

4. **Redis/MongoDB DPA**
   - 현재는 health check만, 향후 slow operation 수집

---

## 파일 목록

```
giipAgentLinux/
├── lib/
│   ├── dpa_mysql.sh           # NEW
│   ├── dpa_mssql.sh           # NEW
│   ├── dpa_postgresql.sh      # NEW
│   └── check_managed_databases.sh  # MODIFIED
├── giipAgent3.sh              # 변경 없음
└── docs/
    └── DPA_INTEGRATION_TEST.md  # 이 파일
```

---

## 테스트 체크리스트

- [ ] giipAgent3.sh 실행 성공
- [ ] MySQL DPA 데이터 수집 확인
- [ ] KVS에 slow_queries 필드 존재 확인
- [ ] 느린 쿼리가 없을 때 빈 배열 `[]` 확인
- [ ] 느린 쿼리가 있을 때 배열에 데이터 존재 확인
- [ ] 로그 파일에 DPA 수집 메시지 확인
- [ ] database-management 페이지에서 데이터 표시 확인 (향후)

---

infraops01에서 테스트 진행하시고 결과 알려주세요!
