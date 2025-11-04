# Gateway Database Query Feature

Gateway 서버에서 다양한 데이터베이스에 직접 쿼리를 실행하고 결과를 KVS에 저장하는 기능입니다.

## 개요

- **목적**: SSH 접속 없이 데이터베이스 쿼리만 실행하여 상태 수집
- **지원 데이터베이스**:
  - ✅ **MySQL** / **MariaDB** (CLI 클라이언트 자동 설치)
  - ✅ **PostgreSQL** (CLI 클라이언트 자동 설치)
  - ✅ **Microsoft SQL Server** (Python pyodbc 자동 설치)
  - ✅ **Oracle** (Python cx_Oracle 자동 설치, Instant Client 수동)
  - 🔜 **MongoDB**, **Redis** (향후 지원 예정)

- **클라이언트 방식**:
  - **MySQL/PostgreSQL**: 전통적인 CLI 클라이언트 (`mysql`, `psql`)
  - **MSSQL/Oracle**: Python 라이브러리 (`pyodbc`, `cx_Oracle`)
    - 장점: 패키지 매니저로 간단 설치, 에러 처리 용이
    - MSSQL: ODBC 드라이버 포함 자동 설치
    - Oracle: cx_Oracle 자동 설치, Instant Client는 수동

- **사용 사례**:
  - 데이터베이스 서버 상태 모니터링
  - 테이블 통계 수집
  - 슬로우 쿼리 로그 분석
  - 복제 상태 확인
  - 트랜잭션 락 모니터링
  - 인덱스 사용률 분석

## 아키텍처

```
Web UI (Query 등록)
    ↓
DB (tGatewayDBQuery - 쿼리 설정 저장, 암호화)
    ↓
SP (pApiGatewayDBQueryListbyAK)
    ↓
Azure Function (giipApiSk)
    ↓
Gateway Agent (giipAgent.sh)
    ↓
Database Client Layer
    ├── MySQL/MariaDB → mysql client (CLI)
    ├── PostgreSQL → psql client (CLI)
    ├── MSSQL → Python pyodbc (db_query_helper.py)
    └── Oracle → Python cx_Oracle (db_query_helper.py)
    ↓
Remote Database Servers
    ├── MySQL/MariaDB Server (port 3306)
    ├── PostgreSQL Server (port 5432)
    ├── MSSQL Server (port 1433)
    └── Oracle Database (port 1521)
    ↓
KVS (결과 저장, Key: {prefix}_{target_lssn})
```

## 데이터베이스 구조

### tGatewayDBQuery 테이블

| 컬럼명 | 타입 | 설명 |
|--------|------|------|
| gmq_sn | INT | 쿼리 설정 일련번호 |
| gateway_lssn | INT | Gateway 서버 LSSN |
| target_lssn | INT | 대상 서버 LSSN |
| **db_type** | NVARCHAR(50) | **데이터베이스 타입** (MySQL, MariaDB, MSSQL, PostgreSQL, Oracle) |
| db_host | NVARCHAR(200) | DB 서버 주소 |
| db_port | INT | DB 포트 (MySQL:3306, MSSQL:1433, PostgreSQL:5432, Oracle:1521) |
| db_user | NVARCHAR(100) | DB 사용자명 |
| db_password | VARBINARY(8000) | DB 비밀번호 (암호화) |
| db_database | NVARCHAR(100) | 기본 데이터베이스 |
| **db_instance** | NVARCHAR(200) | **DB Instance 또는 SID/Service Name** (Oracle, MSSQL) |
| **connection_string** | NVARCHAR(MAX) | **사용자 정의 연결 문자열** (선택사항) |
| query_name | NVARCHAR(200) | 쿼리 이름 |
| query_text | NVARCHAR(MAX) | 실행할 SQL 쿼리 |
| kvs_key_prefix | NVARCHAR(200) | KVS 키 접두사 |
| kvs_value_format | NVARCHAR(50) | 저장 형식 (JSON/CSV/RAW) |
| execution_interval | INT | 실행 주기 (초) |
| timeout_seconds | INT | 쿼리 타임아웃 (초) |
| is_enabled | BIT | 활성화 여부 |

## 사용 방법

### 1. 데이터베이스 쿼리 등록 (SQL)

#### MySQL/MariaDB 예제

```sql
-- 예제: MySQL 연결 스레드 수 모니터링
DECLARE @gateway_lssn INT = 71240  -- Gateway 서버 LSSN
DECLARE @target_lssn INT = 71241   -- 대상 서버 LSSN
DECLARE @csn INT = 71              -- 프로젝트 번호

INSERT INTO tGatewayDBQuery (
    gateway_lssn, target_lssn, csn,
    db_type, db_host, db_port, db_user, 
    db_password, db_database,
    query_name, query_text, query_type,
    kvs_key_prefix, kvs_value_format,
    execution_interval, timeout_seconds,
    is_enabled
) VALUES (
    @gateway_lssn, @target_lssn, @csn,
    'MySQL',                    -- DB 타입
    '192.168.1.100',           -- MySQL 서버 IP
    3306,                       -- MySQL 포트
    'monitor_user',             -- MySQL 사용자
    dbo.lwEncryptPassword('monitor_password'),  -- 암호화된 비밀번호
    'mysql',                    -- 데이터베이스
    'MySQL Thread Count',       -- 쿼리 이름
    'SHOW GLOBAL STATUS LIKE "Threads_connected"',  -- 쿼리
    'SHOW',                     -- 쿼리 타입
    'mysql_threads_',           -- KVS 키 접두사
    'JSON',                     -- 저장 형식
    300,                        -- 5분마다 실행
    30,                         -- 30초 타임아웃
    1                           -- 활성화
);
```

#### PostgreSQL 예제

```sql
-- 예제: PostgreSQL 활성 연결 수 모니터링
INSERT INTO tGatewayDBQuery (
    gateway_lssn, target_lssn, csn,
    db_type, db_host, db_port, db_user, 
    db_password, db_database,
    query_name, query_text,
    kvs_key_prefix, execution_interval
) VALUES (
    @gateway_lssn, @target_lssn, @csn,
    'PostgreSQL',               -- DB 타입
    '192.168.1.101',           -- PostgreSQL 서버 IP
    5432,                       -- PostgreSQL 포트
    'postgres',                 -- 사용자
    dbo.lwEncryptPassword('postgres_password'),
    'postgres',                 -- 데이터베이스
    'PostgreSQL Active Connections',
    'SELECT count(*) FROM pg_stat_activity WHERE state = ''active''',
    'pg_connections_',
    300
);
```

#### Microsoft SQL Server 예제

```sql
-- 예제: MSSQL 데이터베이스 크기 확인
INSERT INTO tGatewayDBQuery (
    gateway_lssn, target_lssn, csn,
    db_type, db_host, db_port, db_user, 
    db_password, db_database, db_instance,
    query_name, query_text,
    kvs_key_prefix, execution_interval
) VALUES (
    @gateway_lssn, @target_lssn, @csn,
    'MSSQL',                    -- DB 타입
    '192.168.1.102',           -- MSSQL 서버 IP
    1433,                       -- MSSQL 포트
    'sa',                       -- 사용자
    dbo.lwEncryptPassword('sa_password'),
    'master',                   -- 데이터베이스
    'SQLEXPRESS',               -- Instance 이름 (선택사항)
    'MSSQL Database Sizes',
    'SELECT name, size * 8 / 1024 AS size_mb FROM sys.master_files WHERE type = 0',
    'mssql_dbsize_',
    600
);
```

#### Oracle 예제

```sql
-- 예제: Oracle 테이블스페이스 사용률
INSERT INTO tGatewayDBQuery (
    gateway_lssn, target_lssn, csn,
    db_type, db_host, db_port, db_user, 
    db_password, db_instance,
    query_name, query_text,
    kvs_key_prefix, execution_interval
) VALUES (
    @gateway_lssn, @target_lssn, @csn,
    'Oracle',                   -- DB 타입
    '192.168.1.103',           -- Oracle 서버 IP
    1521,                       -- Oracle 포트
    'system',                   -- 사용자
    dbo.lwEncryptPassword('oracle_password'),
    'ORCL',                     -- SID 또는 Service Name
    'Oracle Tablespace Usage',
    'SELECT tablespace_name, round(sum(bytes)/1024/1024, 2) as used_mb FROM dba_segments GROUP BY tablespace_name',
    'oracle_tablespace_',
    600
);
```

### 2. Gateway Agent 설정

**giipAgent.cnf** 파일에서 Gateway 모드를 활성화합니다:

```bash
# Gateway Mode 활성화
gateway_mode="1"

# DB 쿼리 리스트 파일 (자동 생성)
gateway_db_querylist="./giipAgentGateway_db_queries.csv"

# 자동 갱신 주기 (초)
gateway_sync_interval="300"
```

### 3. Agent 실행

Gateway 서버에서 Agent를 실행하면 자동으로:
1. 각 데이터베이스 클라이언트 설치 확인 (자동 설치 시도)
2. API에서 DB 쿼리 목록 가져오기
3. 주기적으로 쿼리 실행
4. 결과를 KVS에 자동 저장

```bash
cd ~/giipAgent
./giipAgent.sh
```

Agent 로그 예시:
```
[Gateway-DB] Checking database clients...
[Gateway-MySQL] mysql client is already installed
[Gateway-PostgreSQL] psql client is already installed
[Gateway-MSSQL] sqlcmd not found (install manually if needed)
[Gateway-Oracle] sqlplus not found (install manually if needed)
[Gateway-DB] Client availability:
[Gateway-DB]   MySQL/MariaDB: ✅
[Gateway-DB]   PostgreSQL: ✅
[Gateway-DB]   MSSQL: ⚠️  manual
[Gateway-DB]   Oracle: ⚠️  manual
```

### 4. 결과 확인 (KVS 조회)

저장된 결과는 KVS에서 조회할 수 있습니다:

```sql
-- KVS 조회
EXEC pApiKVSGetbyAK 
    @at = 'YOUR_ACCESS_TOKEN',
    @ktype = 'db_query_result',
    @kkey = 'mysql_threads_71241'  -- {kvs_key_prefix}{target_lssn}
```

## 쿼리 예제

### MySQL/MariaDB

#### 1. 연결 수 모니터링
```sql
db_type: 'MySQL'
query_text: 'SHOW GLOBAL STATUS LIKE "Threads_connected"'
kvs_key_prefix: 'mysql_threads_'
```

#### 2. InnoDB 버퍼 풀 사용량
```sql
query_text: 'SHOW GLOBAL STATUS WHERE Variable_name IN ("Innodb_buffer_pool_pages_data", "Innodb_buffer_pool_pages_total")'
kvs_key_prefix: 'mysql_innodb_'
```

#### 3. 테이블 행 수 통계
```sql
query_text: 'SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema = "mydb" ORDER BY table_rows DESC LIMIT 10'
kvs_key_prefix: 'mysql_table_stats_'
```

#### 4. 슬로우 쿼리 카운트
```sql
query_text: 'SHOW GLOBAL STATUS LIKE "Slow_queries"'
kvs_key_prefix: 'mysql_slow_queries_'
```

#### 5. 복제 상태 확인
```sql
query_text: 'SHOW SLAVE STATUS\G'
kvs_key_prefix: 'mysql_replication_'
```

### PostgreSQL

#### 1. 활성 연결 수
```sql
db_type: 'PostgreSQL'
query_text: 'SELECT count(*) FROM pg_stat_activity WHERE state = ''active'''
kvs_key_prefix: 'pg_connections_'
```

#### 2. 데이터베이스 크기
```sql
query_text: 'SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY pg_database_size(datname) DESC'
kvs_key_prefix: 'pg_dbsize_'
```

#### 3. 테이블 블로트 확인
```sql
query_text: 'SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||''.''||tablename)) FROM pg_tables ORDER BY pg_total_relation_size(schemaname||''.''||tablename) DESC LIMIT 10'
kvs_key_prefix: 'pg_bloat_'
```

#### 4. 복제 지연 확인
```sql
query_text: 'SELECT client_addr, state, sync_state, pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) AS lag_bytes FROM pg_stat_replication'
kvs_key_prefix: 'pg_replication_lag_'
```

#### 5. 락 대기 상황
```sql
query_text: 'SELECT pid, usename, pg_blocking_pids(pid), query FROM pg_stat_activity WHERE cardinality(pg_blocking_pids(pid)) > 0'
kvs_key_prefix: 'pg_locks_'
```

### Microsoft SQL Server

#### 1. 데이터베이스 크기
```sql
db_type: 'MSSQL'
db_instance: 'SQLEXPRESS'  -- Instance 이름 (선택사항)
query_text: 'SELECT name, size * 8 / 1024 AS size_mb FROM sys.master_files WHERE type = 0'
kvs_key_prefix: 'mssql_dbsize_'
```

#### 2. 활성 트랜잭션
```sql
query_text: 'SELECT transaction_id, session_id, transaction_begin_time, DATEDIFF(s, transaction_begin_time, GETDATE()) AS duration_sec FROM sys.dm_tran_active_transactions'
kvs_key_prefix: 'mssql_active_tx_'
```

#### 3. 대기 통계
```sql
query_text: 'SELECT TOP 10 wait_type, waiting_tasks_count, wait_time_ms, max_wait_time_ms FROM sys.dm_os_wait_stats ORDER BY wait_time_ms DESC'
kvs_key_prefix: 'mssql_wait_stats_'
```

#### 4. 인덱스 조각화
```sql
query_text: 'SELECT DB_NAME(database_id) AS dbname, object_name(object_id) AS tablename, index_id, avg_fragmentation_in_percent FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') WHERE avg_fragmentation_in_percent > 30'
kvs_key_prefix: 'mssql_index_frag_'
```

#### 5. 버퍼 풀 사용량
```sql
query_text: 'SELECT COUNT(*) * 8 / 1024 AS buffer_pool_mb FROM sys.dm_os_buffer_descriptors WHERE database_id = DB_ID()'
kvs_key_prefix: 'mssql_buffer_pool_'
```

### Oracle

#### 1. 테이블스페이스 사용률
```sql
db_type: 'Oracle'
db_instance: 'ORCL'  -- SID 또는 Service Name
query_text: 'SELECT tablespace_name, round(sum(bytes)/1024/1024, 2) as used_mb FROM dba_segments GROUP BY tablespace_name'
kvs_key_prefix: 'oracle_tablespace_'
```

#### 2. 세션 수
```sql
query_text: 'SELECT status, count(*) FROM v$session GROUP BY status'
kvs_key_prefix: 'oracle_sessions_'
```

#### 3. 대기 이벤트
```sql
query_text: 'SELECT event, total_waits, time_waited FROM v$system_event WHERE wait_class != ''Idle'' ORDER BY time_waited DESC FETCH FIRST 10 ROWS ONLY'
kvs_key_prefix: 'oracle_wait_events_'
```

#### 4. SGA 사용량
```sql
query_text: 'SELECT name, round(value/1024/1024, 2) as size_mb FROM v$sga'
kvs_key_prefix: 'oracle_sga_'
```

#### 5. 리두 로그 전환 빈도
```sql
query_text: 'SELECT to_char(first_time, ''YYYY-MM-DD HH24'') as hour, count(*) as switches FROM v$log_history WHERE first_time >= SYSDATE - 1 GROUP BY to_char(first_time, ''YYYY-MM-DD HH24'') ORDER BY 1'
kvs_key_prefix: 'oracle_redo_switches_'
```

## Agent 로그

Agent가 MySQL 쿼리를 실행할 때 다음과 같은 로그가 남습니다:

```
[20250104123456] [Gateway-MySQL] Fetching MySQL query list from GIIP API...
[20250104123456] [Gateway-MySQL] ✅ Fetched 3 MySQL queries from API
[20250104123456] [Gateway-MySQL] Processing MySQL queries...
[20250104123456] [Gateway-MySQL] ==== Query 1: MySQL Thread Count ====
[20250104123456] [Gateway-MySQL] Executing query for target_lssn=71241 on 192.168.1.100:3306
[20250104123456] [Gateway-MySQL] Query: SHOW GLOBAL STATUS LIKE "Threads_connected"
[20250104123456] [Gateway-MySQL] ✅ Query executed successfully
[20250104123456] [Gateway-MySQL] Saving to KVS: key=mysql_threads_71241
[20250104123456] [Gateway-MySQL] ✅ Saved to KVS successfully
[20250104123456] [Gateway-MySQL] =====================================
[20250104123456] [Gateway-MySQL] Summary: 3 queries processed
[20250104123456] [Gateway-MySQL]   Succeeded: 3
[20250104123456] [Gateway-MySQL]   Failed: 0
[20250104123456] [Gateway-MySQL] =====================================
```

## 보안 고려사항

1. **비밀번호 암호화**: 모든 DB 비밀번호는 VARBINARY로 암호화되어 DB에 저장
2. **파일 권한**: 쿼리 리스트 CSV 파일은 600 권한 (소유자만 읽기/쓰기)
3. **전송 암호화**: API 통신은 HTTPS 사용
4. **최소 권한**: DB 모니터링 전용 계정 사용 권장

### 데이터베이스별 모니터링 계정 생성

#### MySQL/MariaDB
```sql
CREATE USER 'giip_monitor'@'gateway_server_ip' IDENTIFIED BY 'secure_password';
GRANT SELECT, SHOW DATABASES, REPLICATION CLIENT ON *.* TO 'giip_monitor'@'gateway_server_ip';
FLUSH PRIVILEGES;
```

#### PostgreSQL
```sql
CREATE USER giip_monitor WITH PASSWORD 'secure_password';
GRANT pg_read_all_stats TO giip_monitor;
GRANT CONNECT ON DATABASE postgres TO giip_monitor;
```

#### Microsoft SQL Server
```sql
CREATE LOGIN giip_monitor WITH PASSWORD = 'secure_password';
CREATE USER giip_monitor FOR LOGIN giip_monitor;
GRANT VIEW SERVER STATE TO giip_monitor;
GRANT VIEW DATABASE STATE TO giip_monitor;
```

#### Oracle
```sql
CREATE USER giip_monitor IDENTIFIED BY secure_password;
GRANT CREATE SESSION TO giip_monitor;
GRANT SELECT_CATALOG_ROLE TO giip_monitor;
GRANT SELECT ON v_$session TO giip_monitor;
GRANT SELECT ON v_$sga TO giip_monitor;
```

## 트러블슈팅

### 클라이언트 설치

Gateway Agent는 필요한 클라이언트를 자동으로 설치하려고 시도합니다.

#### Python 환경 (MSSQL/Oracle용)
```bash
# 자동 설치됨 (giipAgent.sh가 check_python_environment 호출)
# 수동 설치가 필요한 경우:
sudo apt-get install -y python3 python3-pip   # Ubuntu/Debian
sudo yum install -y python3 python3-pip       # CentOS/RHEL
```

#### MySQL 클라이언트
```bash
# 자동 설치됨 (giipAgent.sh가 check_mysql_client 호출)
# 수동 설치가 필요한 경우:
sudo apt-get install -y mysql-client   # Ubuntu/Debian
sudo yum install -y mysql              # CentOS/RHEL
```

#### PostgreSQL 클라이언트
```bash
# 자동 설치됨 (giipAgent.sh가 check_psql_client 호출)
# 수동 설치가 필요한 경우:
sudo apt-get install -y postgresql-client   # Ubuntu/Debian
sudo yum install -y postgresql              # CentOS/RHEL
```

#### MSSQL 클라이언트 (Python pyodbc)
```bash
# 자동 설치됨 (giipAgent.sh가 check_mssql_client 호출)
# - ODBC 드라이버 (msodbcsql17)
# - Python pyodbc 패키지

# 수동 설치가 필요한 경우:
# Ubuntu
curl -s https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
curl -s https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/prod.list | \
    sudo tee /etc/apt/sources.list.d/msprod.list
sudo apt-get update
sudo ACCEPT_EULA=Y apt-get install -y msodbcsql17 unixodbc-dev
pip3 install pyodbc

# CentOS/RHEL
sudo curl -s https://packages.microsoft.com/config/rhel/8/prod.repo | \
    sudo tee /etc/yum.repos.d/msprod.repo
sudo ACCEPT_EULA=Y yum install -y msodbcsql17 unixODBC-devel
pip3 install pyodbc
```

#### Oracle 클라이언트 (Python cx_Oracle + Instant Client)
```bash
# Python cx_Oracle는 자동 설치됨
pip3 install cx_Oracle

# Oracle Instant Client는 수동 설치 필요 (라이선스 제약)
# 1. https://www.oracle.com/database/technologies/instant-client/downloads.html 에서 다운로드
# 2. 압축 해제
unzip instantclient-basic-linux.x64-19.x.x.x.zip -d /opt/oracle

# 3. 환경 변수 설정
export LD_LIBRARY_PATH=/opt/oracle/instantclient_19_x:$LD_LIBRARY_PATH
export PATH=$PATH:/opt/oracle/instantclient_19_x
echo "export LD_LIBRARY_PATH=/opt/oracle/instantclient_19_x:$LD_LIBRARY_PATH" >> ~/.bashrc
echo "export PATH=$PATH:/opt/oracle/instantclient_19_x" >> ~/.bashrc
```

### Python Helper Script 확인
```bash
# 파일 존재 확인
ls -l ~/giip/giipscripts/db_query_helper.py

# 실행 권한 부여
chmod +x ~/giip/giipscripts/db_query_helper.py

# 테스트 실행
python3 ~/giip/giipscripts/db_query_helper.py --help
```

### pyodbc 모듈 테스트
```bash
python3 -c "import pyodbc; print('pyodbc OK')"
```

### cx_Oracle 모듈 테스트
```bash
python3 -c "import cx_Oracle; print('cx_Oracle OK')"
# Oracle Instant Client가 없으면 에러 발생:
# DPI-1047: Cannot locate a 64-bit Oracle Client library
```

### 연결 실패 문제

#### 1. 방화벽 확인
```bash
# Gateway 서버에서 포트 테스트
telnet <db_host> <db_port>
nc -zv <db_host> <db_port>
```

#### 2. DB 권한 확인
```sql
-- MySQL
SHOW GRANTS FOR 'monitor_user'@'gateway_ip';

-- PostgreSQL
\du giip_monitor

-- MSSQL
SELECT * FROM sys.server_principals WHERE name = 'giip_monitor';

-- Oracle
SELECT * FROM dba_sys_privs WHERE grantee = 'GIIP_MONITOR';
```

#### 3. 연결 설정 확인
- **MySQL**: bind-address 설정 확인 (`/etc/mysql/mysql.conf.d/mysqld.cnf`)
- **PostgreSQL**: pg_hba.conf 및 postgresql.conf의 listen_addresses 확인
- **MSSQL**: SQL Server Configuration Manager에서 TCP/IP 활성화 확인
- **Oracle**: listener.ora 및 tnsnames.ora 설정 확인

### 쿼리 타임아웃

`timeout_seconds` 값을 늘려주세요:

```sql
UPDATE tGatewayDBQuery
SET timeout_seconds = 60
WHERE gmq_sn = 1;
```

## 관련 파일

- **DB 테이블**: `giipdb/Tables/CREATE_tGatewayDBQuery.sql`
- **테이블 마이그레이션**: `giipdb/Tables/ALTER_tGatewayDBQuery_MultiDB.sql`
- **SP**: `giipdb/SP/pApiGatewayDBQueryListbyAK.sql`
- **Agent**: `giipAgentLinux/giipAgent.sh`
- **Python Helper**: `giipAgentLinux/giipscripts/db_query_helper.py` (MSSQL/Oracle용)
- **설정**: `giipAgentLinux/giipAgent.cnf`
- **문서**: `giipAgentLinux/docs/GATEWAY_DB_QUERY.md` (this file)

## 버전 이력

- **v1.80** (2025-11-04): 초기 구현 (MySQL 전용)
  - MySQL 쿼리 등록 및 실행 기능
  - KVS 자동 저장
  - MySQL 클라이언트 자동 설치
  
- **v1.81** (2025-11-04): 다중 데이터베이스 지원
  - **MySQL, MariaDB, MSSQL, PostgreSQL, Oracle 지원**
  - 각 DB별 클라이언트 자동 설치 (MySQL, PostgreSQL)
  - DB별 연결 문자열 처리
  - tGatewayMySQLQuery → tGatewayDBQuery 테이블 확장
  - db_type, db_instance, connection_string 컬럼 추가

- **v1.82** (2025-11-04): Python 기반 클라이언트 지원
  - **MSSQL: Python pyodbc 사용** (CLI sqlcmd 대체)
  - **Oracle: Python cx_Oracle 사용** (CLI sqlplus 대체)
  - `db_query_helper.py` 헬퍼 스크립트 추가
  - 장점:
    - 패키지 매니저로 간단 설치 (`pip3 install`)
    - 에러 처리 및 결과 파싱 용이
    - MSSQL ODBC 드라이버 자동 설치
  - Python3 및 pip3 자동 설치 지원

## Web UI 통합 (선택사항)

향후 Web UI에서 데이터베이스 쿼리를 등록/관리할 수 있는 페이지를 추가할 예정입니다.

예상 기능:
- 다양한 DB 타입별 쿼리 등록/수정/삭제
- 쿼리 실행 이력 조회
- 실시간 결과 미리보기
- DB별 쿼리 템플릿 라이브러리
- 연결 테스트 기능
