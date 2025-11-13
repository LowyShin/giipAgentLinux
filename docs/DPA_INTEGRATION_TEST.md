# DPA (Database Performance Analysis) 시스템 문서

## 🚨 명명 규칙 (TABLE_COLUMN_NAMING_RULES.md 준수)

**DPA 데이터 저장 시 필드명**:
- `kType='database'`: Database 타입 DPA 데이터임을 명시
- `kKey=mdb_id`: tManagedDatabase의 Primary Key (mdb_id) 사용
  - ⚠️ 향후 `mdbSn`으로 변경 예정 (명명 규칙 준수)
- `kFactor='sqlnetinv'`: SQL Network Inventory (DPA 데이터)

**중요**: `kType='lssn'`이 아닌 `kType='database'`를 사용하여 데이터베이스별 DPA 관리

---

## ⚠️ 중요 사양

### KVS 저장 정책

**필수 규칙**:
1. **DPA 데이터는 항상 저장**: 느린 쿼리가 있든 없든 **매 실행마다** KVS에 저장
2. **kType**: `database` (tManagedDatabase 기준)
3. **kKey**: `mdb_id` (tManagedDatabase.mdb_id - 각 DB의 고유 번호)
4. **kFactor**: `sqlnetinv` (기존 독립 DPA 스크립트와 동일)
5. **느린 쿼리가 없을 경우**: 빈 배열 `[]`을 저장
6. **저장 시점**: DB 연결 성공 후 DPA 수집 직후

### 데이터 분리

- **kFactor="giipagent"**: Health Check + Performance 메트릭 (kType=lssn 사용)
- **kFactor="sqlnetinv"**: DPA 느린 쿼리 데이터 (kType=database 사용, 항상 저장)

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

### 2. DPA 느린 쿼리 데이터 (kFactor=sqlnetinv) - ✅ 수정 완료 (2025-11-13)

**⚠️ 중요**: **항상 저장됨** (느린 쿼리 유무와 관계없이 매 실행마다)

**저장 조건**: DB 연결 성공 시 (항상)

**🚨 KVS 저장 파라미터** (명명 규칙 준수):
- **kType**: `database` (tManagedDatabase 기준) ✅
- **kKey**: `mdb_id` 값 (예: `4`, `5`, `6` - tManagedDatabase.mdb_id) ✅
- **kFactor**: `sqlnetinv` ✅

**Shell Script 구현** (dpa-managed-databases.sh):
```bash
# 각 DB loop 내에서 즉시 KVSPut 호출
kType='database'
kKey=$mdb_id  # 예: 4, 5, 6
kFactor='sqlnetinv'

# API 호출
text="KVSPut database $mdb_id sqlnetinv"
jsondata='{
  "collected_at": "2025-11-13T20:30:00",
  "collector_host": "infraops01",
  "mdb_id": 4,
  "db_name": "p-cnsldb01m",
  "db_type": "MySQL",
  "db_host": "p-cnsldb01m:3306",
  "dpa_data": [...]
}'
```

**kValue** (느린 쿼리가 **있을 때**):
```json
{
  "collected_at": "2025-11-13 20:30:00",
  "collector_host": "infraops01.istyle.local",
  "mdb_id": 4,
  "db_name": "p-cnsldb01m",
  "db_type": "MySQL",
  "db_host": "p-cnsldb01m:3306",
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
  "mdb_id": 4,
  "db_name": "p-cnsldb01m",
  "db_type": "MySQL",
  "db_host": "p-cnsldb01m:3306",
  "dpa_data": []
}
```

**⚠️ 핵심**: 
1. 빈 배열 `[]`이라도 **반드시 저장**되어야 함
2. `kType='database'`, `kKey=mdb_id` 사용으로 각 DB별 독립적 관리
3. `lssn` 대신 `mdb_id`로 각 데이터베이스를 고유하게 식별
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
# 🚨 주의: kType='database', kKey=mdb_id 사용
pwsh .\mgmt\query-kvs.ps1 -KType database -KKey 4 -KFactor sqlnetinv -Top 1

# 3. 특정 DB의 DPA 히스토리 조회 (최근 10개)
pwsh .\mgmt\query-kvs.ps1 -KType database -KKey 4 -KFactor sqlnetinv -Top 10

# 4. 모든 Managed Database의 최신 DPA 데이터 확인
# database-management 페이지에서 mdb_id 확인 후 각각 조회
pwsh .\mgmt\query-kvs.ps1 -KType database -KKey 5 -KFactor sqlnetinv -Top 1
pwsh .\mgmt\query-kvs.ps1 -KType database -KKey 6 -KFactor sqlnetinv -Top 1
```

**확인 항목**:
1. ✅ `kType='database'`, `kKey=mdb_id` (예: 4, 5, 6)로 저장되는지 확인
2. ✅ `sqlnetinv` 데이터가 **매번 저장되는지 확인**
3. ✅ 느린 쿼리가 없을 때 `dpa_data: []` (빈 배열) 확인
4. ✅ 느린 쿼리가 있을 때 배열에 데이터 존재 확인
5. ✅ `collected_at` 타임스탬프가 매 실행마다 갱신되는지 확인
6. ✅ `mdb_id`, `db_name`, `db_type`, `db_host` 필드 존재 확인
7. ✅ Shell script 로그에 `✅ DPA data saved to KVS (kType=database, kKey=N, kFactor=sqlnetinv)` 메시지 확인

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

## SQL3D 페이지에서 DPA 데이터 조회 - ✅ 구현 완료 (2025-11-13)

### 페이지 접근

```
http://localhost:3000/en/sql3d
```

### 조회 파라미터 입력 (UI)

1. **kType**: `database` 선택 (드롭다운)
2. **kKey**: `4` 입력 (database-management 페이지의 `#4`, `#5` 등 mdb_id)
3. **kFactor**: `sqlnetinv` 입력
4. **PickDate**: 조회할 날짜/시간 선택 또는 입력
   - 예: `2025-11-13 20:30:00`
   - 최신 데이터: 빈 값 또는 현재 시간
5. **Draw 버튼** 클릭

### database-management 페이지에서 mdb_id 확인

```
http://localhost:3000/en/database-management
```

각 데이터베이스 카드 제목 옆에 `#4`, `#5`, `#6` 등 고유 번호가 표시됩니다.
이 번호가 SQL3D에서 사용할 kKey 값입니다.

### 데이터 구조 및 표시

**KVS에서 반환되는 데이터 구조**:
```json
{
  "collected_at": "2025-11-13T20:30:00",
  "collector_host": "infraops01",
  "mdb_id": 4,
  "db_name": "p-cnsldb01m",
  "db_type": "MySQL",
  "db_host": "p-cnsldb01m:3306",
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

**parseResponse() 함수** (수정 완료):
```typescript
// giipv3/src/app/[locale]/sql3d/page.tsx
const parseResponse = (txt: string) => {
  const records: any[] = parseGiipApiResponse(txt || '') || [];
  
  // kType='database' 응답 처리
  if (records.length > 0) {
    const first = records[0];
    
    // dpa_data 배열이 있는 경우
    if (first.dpa_data && Array.isArray(first.dpa_data)) {
      const sqlServer = first.db_name || first.db_host || 'Database';
      const hostGroups = {};
      
      // host_name별로 그룹화
      first.dpa_data.forEach(query => {
        const hostName = query.host_name || 'unknown';
        if (!hostGroups[hostName]) {
          hostGroups[hostName] = {
            name: hostName,
            sessions: 0,
            cpu_time: 0
          };
        }
        hostGroups[hostName].sessions += 1;
        hostGroups[hostName].cpu_time += (query.cpu_time || 0);
      });
      
      return {
        sqlServer,
        hosts: Object.values(hostGroups)
      };
    }
  }
  
  // 기존 kType='lssn' 로직도 유지
  // ...
};
```

**3D 그래프 표시**:
- **중앙 노드**: Database 이름 (db_name 또는 db_host)
- **주변 노드**: 각 `host_name` (접속 클라이언트 호스트)
- **연결선**: Database와 각 호스트 간 연결
- **색상**: CPU 시간에 따른 부하 표시 (높을수록 빨강)
- **크기**: 세션 수(느린 쿼리 수)에 따른 노드 크기

**노드 클릭 시 상세 정보**:
- 해당 호스트에서 실행 중인 느린 쿼리 목록
- 각 쿼리의 정보:
  - `login_name`: 접속 사용자
  - `status`: 쿼리 상태 (executing, runnable 등)
  - `cpu_time`: CPU 사용 시간 (초)
  - `reads`, `writes`, `logical_reads`: I/O 통계
  - `start_time`: 쿼리 시작 시각
  - `command`: SQL 명령 타입 (SELECT, UPDATE 등)
  - `query_text`: 실제 쿼리 텍스트 (최대 500자)

### URL 파라미터로 직접 접근

```
# 최신 데이터 조회
http://localhost:3000/en/sql3d?kType=database&kKey=4&kFactor=sqlnetinv

# 특정 시점 데이터 조회
http://localhost:3000/en/sql3d?kType=database&kKey=4&kFactor=sqlnetinv&pickDate=2025-11-13%2020:30:00

# database-management에서 "View DPA" 버튼 클릭 시 (향후 구현)
http://localhost:3000/en/sql3d?kType=database&kKey=5&kFactor=sqlnetinv
```

### 테스트 시나리오

1. **Shell Script 실행** (infraops01 서버):
   ```bash
   cd /opt/giipAgentLinux
   sudo bash giipscripts/dpa-managed-databases.sh
   ```

2. **KVS 저장 확인**:
   ```powershell
   pwsh .\mgmt\query-kvs.ps1 -KType database -KKey 4 -KFactor sqlnetinv -Top 1
   ```

3. **SQL3D 페이지 접근**:
   - kType: `database`
   - kKey: `4`
   - kFactor: `sqlnetinv`
   - Draw 클릭

4. **3D 그래프 확인**:
   - 중앙에 Database 노드
   - 주변에 접속 호스트 노드들
   - 연결선 및 색상 표시

5. **호스트 노드 클릭**:
   - 우측 패널에 느린 쿼리 목록 표시
   - 쿼리 상세 정보 확인

---

## 전체 워크플로우 (End-to-End) - ✅ 구현 완료 (2025-11-13)

### 1. Shell Script 실행 (Gateway 서버)

```bash
# infraops01 서버 접속
ssh user@infraops01

# DPA 스크립트 실행
cd /opt/giipAgentLinux
sudo bash giipscripts/dpa-managed-databases.sh

# 로그 확인
tail -f /var/log/giip/dpa_managed_$(date +%Y%m%d).log
```

**예상 로그 출력**:
```
[2025-11-13 20:30:00] ==========================================
[2025-11-13 20:30:00] Managed Database Monitoring Started
[2025-11-13 20:30:00] Hostname: infraops01.istyle.local
[2025-11-13 20:30:00] ==========================================
[2025-11-13 20:30:01] ✓ Fetched 3 database(s)
[2025-11-13 20:30:02] Processing [1/3]: p-cnsldb01m (MySQL) @ p-cnsldb01m:3306
[2025-11-13 20:30:02]   Health: success (95 ms) - Connected
[2025-11-13 20:30:02]   Collecting DPA data...
[2025-11-13 20:30:03]   📊 Saving DPA data for p-cnsldb01m (mdb_id: 4) to KVS...
[2025-11-13 20:30:04]   ✅ DPA data saved to KVS (kType=database, kKey=4, kFactor=sqlnetinv)
[2025-11-13 20:30:04]   ⚠️  Found 3 slow queries
[2025-11-13 20:30:05] ✓ Health check results updated
[2025-11-13 20:30:05] ==========================================
[2025-11-13 20:30:05] Managed Database Monitoring Completed
[2025-11-13 20:30:05]   - Health checks: Updated in tManagedDatabase
[2025-11-13 20:30:05]   - DPA data: Saved per-database (kType=database, kFactor=sqlnetinv)
[2025-11-13 20:30:05] ==========================================
```

### 2. KVS 데이터 확인 (Windows)

```powershell
cd c:\Users\lowys\Downloads\projects\giipprj\giipdb

# 특정 DB의 최신 DPA 데이터 조회
pwsh .\mgmt\query-kvs.ps1 -KType database -KKey 4 -KFactor sqlnetinv -Top 1
```

**예상 출력**:
```json
{
  "collected_at": "2025-11-13T20:30:00",
  "collector_host": "infraops01.istyle.local",
  "mdb_id": 4,
  "db_name": "p-cnsldb01m",
  "db_type": "MySQL",
  "db_host": "p-cnsldb01m:3306",
  "dpa_data": [
    {
      "host_name": "app-server01:45678",
      "login_name": "dbuser",
      "status": "executing",
      "cpu_time": 75,
      "query_text": "SELECT * FROM large_table..."
    }
  ]
}
```

### 3. SQL3D 페이지에서 조회 및 3D 표시

#### 방법 A: Select Database 버튼 사용 (추천)

1. **SQL3D 페이지 접근**:
   ```
   http://localhost:3000/en/sql3d
   ```

2. **"📊 Select Database" 버튼 클릭**

3. **Managed Database 목록에서 선택**:
   - 리스트에서 원하는 DB 클릭
   - 자동으로 kType=database, kKey=mdb_id, kFactor=sqlnetinv 설정됨

4. **자동으로 3D 그래프 표시**

#### 방법 B: 수동 파라미터 입력

1. **SQL3D 페이지 접근**

2. **파라미터 입력**:
   - kType: `database`
   - kKey: `4` (database-management 페이지의 #4)
   - kFactor: `sqlnetinv`

3. **Draw 버튼 클릭**

4. **3D 그래프 확인**:
   - 중앙: Database 노드 (db_name)
   - 주변: 각 host_name 노드들
   - 크기: 느린 쿼리 수 (sessions)
   - 색상: CPU 시간 (cpu_time)

5. **호스트 노드 클릭**:
   - 우측 패널에 해당 호스트의 느린 쿼리 목록 표시
   - 쿼리 상세 정보 확인

### 4. database-management 페이지에서 mdb_id 확인

```
http://localhost:3000/en/database-management
```

- 각 DB 카드 제목 옆에 `#4`, `#5`, `#6` 등 고유 번호 표시
- 이 번호가 SQL3D의 kKey 값

---

## 구현 완료 체크리스트

### ✅ Shell Script (dpa-managed-databases.sh)
- [x] kType='database', kKey=mdb_id 사용
- [x] 각 DB별 개별 KVSPut 호출
- [x] mdb_id, db_name, db_type, db_host 필드 포함
- [x] dpa_data 배열 (빈 배열 포함) 항상 저장
- [x] Health Check 업데이트 유지
- [x] 로그 메시지 명확화

### ✅ SQL3D 페이지 (page.tsx)
- [x] parseResponse 함수에 kType='database' 처리 추가
- [x] dpa_data 배열을 host_name별로 그룹화
- [x] sessions, cpu_time 집계
- [x] 기존 kType='lssn' 방식과 병행 지원
- [x] "Select Database" 버튼 추가
- [x] Database 선택 모달 구현
- [x] ManagedDatabaseList API 호출
- [x] 선택 시 자동 kType, kKey, kFactor 설정

### ✅ database-management 페이지
- [x] mdb_id 표시 (#4, #5 등)
- [x] DatabaseCard 컴포넌트에 ID 배지 추가

### ✅ 문서화 (DPA_INTEGRATION_TEST.md)
- [x] kType='database' 저장 구조 문서화
- [x] Shell script 구현 방법
- [x] KVS 조회 방법
- [x] SQL3D 사용 방법
- [x] 전체 워크플로우
- [x] 테스트 시나리오

### ✅ 표준 프롬프트 통합
- [x] STANDARD_WORK_PROMPT.md에 DPA 문서 링크
- [x] giipAgentLinux/README.md에 DPA 섹션 추가
- [x] DEVELOPMENT_RULES_INDEX.md에 DPA 참조 추가

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

5. **database-management 페이지에서 SQL3D 직접 연동**
   - 각 DB 카드에 "View DPA in 3D" 버튼 추가
   - 클릭 시 해당 mdb_id로 SQL3D 페이지 자동 열기

6. **MySQL/PostgreSQL DPA 수집 추가**
   - 현재는 MSSQL만 지원
   - MySQL, PostgreSQL collect 함수 활성화 필요

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
