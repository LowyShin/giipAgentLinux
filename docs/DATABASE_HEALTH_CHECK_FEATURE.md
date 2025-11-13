# Database Management Health Check 기능 추가 완료

## 📋 개요

**Database Management** 페이지에서 등록한 데이터베이스들을 Gateway 서버가 자동으로 Health Check하고 결과를 KVS(giipagent factor)에 저장하는 기능 추가

---

## ✅ 구현 내용

### 1. 새로운 함수 추가

**파일:** `giipAgentLinux/lib/check_managed_databases.sh` (모듈화됨)

**호출 위치:** `giipAgentLinux/giipAgent3.sh` Line 224

**함수:** `check_managed_databases()`

**기능:**
1. **DB 목록 조회**: `pApiManagedDatabaseListForAgentbySk` SP 호출
2. **Health Check 수행**: DB 타입별로 연결 테스트
3. **결과 업로드**: `pApiManagedDatabaseHealthUpdatebySk` SP로 결과 전송
4. **KVS 로깅**: 모든 단계를 `giipagent` factor에 기록

---

### 2. 지원하는 데이터베이스

| DB 타입 | 클라이언트 | Health Check 방법 |
|---------|-----------|------------------|
| **MySQL / MariaDB** | `mysql` | `SELECT 1` 쿼리 실행 |
| **PostgreSQL** | `psql` | `SELECT 1` 쿼리 실행 |
| **MSSQL** | `sqlcmd` | `SELECT 1` 쿼리 실행 |
| **Redis** | `redis-cli` | `PING` 명령 실행 |
| **MongoDB** | `mongosh` / `mongo` | `db.adminCommand({ping:1})` 실행 |

**참고:** Oracle은 `cx_Oracle` Python 모듈 필요 (추후 추가 가능)

---

### 3. KVS 로깅 이벤트

**Factor:** `giipagent`

**Event Types:**

#### `db_health_check`
```json
{
  "action": "health_check_start"
}

{
  "action": "no_databases",
  "count": 0
}

{
  "action": "database_checked",
  "mdb_id": 1,
  "db_name": "production-mysql",
  "db_type": "mysql",
  "status": "success",
  "response_time_ms": 45
}

{
  "action": "health_check_completed",
  "total": 5,
  "checked": 5,
  "success": 4,
  "failed": 1
}
```

#### `db_health_error`
```json
{
  "action": "list_fetch_failed",
  "error": "API call failed"
}

{
  "action": "list_fetch_failed",
  "error": "RstVal=401"
}
```

---

### 4. Gateway 메인 루프 수정

**파일:** `giipAgentLinux/giipAgent3.sh`  
**Line:** ~224

**변경:**
```bash
# Gateway 모드 메인 루프
while true; do
    collect_gateway_server_status  # 1. 원격 서버 상태 수집
    process_gateway_servers        # 2. 원격 서버 큐 처리
    check_managed_databases        # 3. DB Health Check (신규!)
    sleep ${giipagentdelay}
done
```

---

### 5. SP 배포

#### pApiManagedDatabaseListForAgentbySk
```sql
-- Agent가 모니터링할 DB 목록 조회 (암호 복호화 포함)
EXEC pApiManagedDatabaseListForAgentbySk @sk='your_secret_key'

-- 결과
{
  "RstVal": 200,
  "Proc_MSG": "Success",
  "result": "success",
  "mdb_id": 1,
  "db_name": "production-mysql",
  "db_type": "mysql",
  "db_host": "192.168.1.100",
  "db_port": 3306,
  "db_user": "dbuser",
  "db_password": "decrypted_password",  -- 복호화됨!
  "db_database": "myapp_db",
  ...
}
```

#### pApiManagedDatabaseHealthUpdatebySk
```sql
-- Health Check 결과 일괄 업데이트
EXEC pApiManagedDatabaseHealthUpdatebySk 
    @sk='your_secret_key',
    @jsondata='[
        {"mdb_id":1,"status":"success","message":"Connected","response_time_ms":45},
        {"mdb_id":2,"status":"error","message":"Connection timeout","response_time_ms":5000}
    ]'

-- 결과
{
  "RstVal": 200,
  "Proc_MSG": "Health check results updated successfully",
  "result": "success",
  "updated_count": 2
}
```

**배포 완료:**
```powershell
cd giipdb
pwsh -File .\mgmt\execSQLFile.ps1 -sqlfile ".\SP\pApiManagedDatabaseListForAgentbySk.sql"
pwsh -File .\mgmt\execSQLFile.ps1 -sqlfile ".\SP\pApiManagedDatabaseHealthUpdatebySk.sql"
```

---

## 🔍 동작 흐름

```
1. Gateway Agent 시작
   ↓
2. Gateway 메인 루프 시작
   ↓
3. check_managed_databases() 호출 (매 사이클)
   ↓
4. pApiManagedDatabaseListForAgentbySk 호출
   ├─ CSN 기반 DB 목록 조회
   ├─ 암호 복호화 (lwDecryptPassword)
   └─ is_active=1인 DB만 반환
   ↓
5. 각 DB별 Health Check 수행
   ├─ MySQL: mysql -h... -e 'SELECT 1'
   ├─ PostgreSQL: psql -c 'SELECT 1'
   ├─ MSSQL: sqlcmd -Q 'SELECT 1'
   ├─ Redis: redis-cli PING
   └─ MongoDB: mongosh --eval 'db.adminCommand({ping:1})'
   ↓
6. 각 체크마다 KVS 로깅 (giipagent factor)
   ├─ Event: db_health_check
   ├─ Action: database_checked
   └─ Details: mdb_id, status, response_time_ms
   ↓
7. 결과를 JSON 배열로 수집
   [
     {"mdb_id":1,"status":"success","message":"OK","response_time_ms":45},
     {"mdb_id":2,"status":"error","message":"timeout","response_time_ms":5000}
   ]
   ↓
8. pApiManagedDatabaseHealthUpdatebySk 호출
   ├─ tManagedDatabase 테이블 업데이트
   ├─ last_check_dt = GETDATE()
   ├─ last_check_status = status
   └─ last_check_message = message
   ↓
9. KVS에 요약 로깅 (giipagent factor)
   ├─ Event: db_health_check
   ├─ Action: health_check_completed
   └─ Details: total, checked, success, failed
   ↓
10. 다음 사이클까지 대기 (giipagentdelay)
```

---

## 🧪 테스트 시나리오

### 시나리오 1: MySQL 데이터베이스 등록 및 체크

1. **Database Management 페이지에서 DB 등록**
   ```
   DB 이름: production-mysql
   DB 유형: mysql
   호스트: 192.168.1.100
   포트: 3306
   사용자: dbuser
   비밀번호: ********
   데이터베이스: myapp_db
   활성 상태: ✅
   ```

2. **Gateway Agent 실행 대기**
   - Agent가 매 사이클마다 자동으로 체크
   - 기본 주기: 60초 (giipagentdelay)

3. **KVS 로그 확인**
   ```bash
   # KVS에서 giipagent factor 조회
   # Event: db_health_check
   # Action: database_checked
   # Details: {"mdb_id":1,"db_name":"production-mysql","status":"success","response_time_ms":45}
   ```

4. **DB에서 결과 확인**
   ```sql
   SELECT 
       db_name,
       last_check_dt,
       last_check_status,
       last_check_message
   FROM tManagedDatabase
   WHERE mdb_id = 1

   -- 예상 결과:
   -- db_name: production-mysql
   -- last_check_dt: 2025-11-10 15:30:45
   -- last_check_status: success
   -- last_check_message: Connection successful
   ```

---

### 시나리오 2: DB 연결 실패 시

1. **네트워크 차단 또는 잘못된 인증 정보**

2. **Health Check 결과**
   ```json
   {
     "action": "database_checked",
     "mdb_id": 2,
     "db_name": "test-postgres",
     "db_type": "postgresql",
     "status": "error",
     "response_time_ms": 5000
   }
   ```

3. **DB 업데이트**
   ```sql
   -- tManagedDatabase
   last_check_status = 'error'
   last_check_message = 'ERROR:  password authentication failed for user "dbuser"'
   ```

4. **KVS 로그**
   ```json
   {
     "event_type": "db_health_check",
     "action": "database_checked",
     "details": {
       "mdb_id": 2,
       "status": "error",
       "response_time_ms": 5000
     }
   }
   ```

---

### 시나리오 3: DB 클라이언트 미설치

1. **PostgreSQL DB 등록했으나 `psql` 미설치**

2. **Health Check 결과**
   ```json
   {
     "status": "error",
     "message": "psql client not installed"
   }
   ```

3. **자동 설치 안내**
   - Gateway Agent는 DB 클라이언트를 자동 설치하지 않음
   - 로그에 설치 필요 메시지 출력
   - 수동 설치 필요:
     ```bash
     # Debian/Ubuntu
     sudo apt-get install postgresql-client
     
     # CentOS/RHEL
     sudo yum install postgresql
     ```

---

## 📊 KVS 데이터 구조

### Factor: giipagent

**Key 패턴:** `{timestamp}_{event_type}_{lssn}`

**Value 구조:**
```json
{
  "event_type": "db_health_check",
  "timestamp": "2025-11-10 15:30:45",
  "lssn": 71174,
  "hostname": "gateway-server-01",
  "mode": "gateway",
  "version": "2.00",
  "details": {
    "action": "database_checked",
    "mdb_id": 1,
    "db_name": "production-mysql",
    "db_type": "mysql",
    "status": "success",
    "response_time_ms": 45
  }
}
```

---

## 🚀 배포 체크리스트

- [x] `check_managed_databases()` 함수 추가
- [x] Gateway 메인 루프에 호출 추가
- [x] `pApiManagedDatabaseListForAgentbySk` SP 배포
- [x] `pApiManagedDatabaseHealthUpdatebySk` SP 배포
- [x] KVS 로깅 추가 (giipagent factor)
- [x] 0개 DB일 때도 로깅 (no_databases 이벤트)
- [ ] 실제 DB 등록 후 테스트
- [ ] 연결 실패 시나리오 테스트
- [ ] 클라이언트 미설치 시나리오 테스트

---

## 📝 다음 단계

1. **Database Management 페이지에서 테스트 DB 등록**
   - MySQL, PostgreSQL, Redis 등

2. **Gateway Agent 로그 모니터링**
   ```bash
   tail -f /giipAgent/giipAgent.log | grep "DB-Health"
   ```

3. **KVS 데이터 확인**
   - Factor: `giipagent`
   - Event: `db_health_check`

4. **tManagedDatabase 테이블 확인**
   ```sql
   SELECT 
       db_name,
       db_type,
       last_check_dt,
       last_check_status,
       last_check_message
   FROM tManagedDatabase
   WHERE is_active = 1
   ORDER BY last_check_dt DESC
   ```

---

**작성일:** 2025-11-10  
**버전:** 1.0  
**관련 문서:** 
- [database-management.ko.md](../giipv3/public/help/database-management.ko.md)
## 관련 문서

- [GATEWAY_QUICK_REFERENCE.md](../../giipdb/docs/GATEWAY_QUICK_REFERENCE.md)
