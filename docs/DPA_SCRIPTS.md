# Database Performance Agent Scripts (Linux)

Linux 환경에서 MySQL과 MS SQL Server의 성능 데이터를 수집하여 KVS에 업로드하는 스크립트입니다.

## 개요

Windows의 `dpa-put-mysql.ps1` 및 `dpa-put-mssql.ps1`과 동일한 기능을 Linux에서 제공합니다.

## 파일 목록

- **dpa-put-mysql.sh**: MySQL 성능 데이터 수집
- **dpa-put-mssql.sh**: MS SQL Server 성능 데이터 수집

## 기능

### 수집 데이터

1. **세션 정보**
   - 호스트명 (클라이언트)
   - 로그인 사용자
   - 세션 상태

2. **쿼리 부하**
   - CPU 시간 (50초 이상 쿼리만)
   - 물리/논리 읽기
   - 쓰기 횟수
   - 시작 시간

3. **쿼리 텍스트**
   - 실행 중인 쿼리 전체 내용

### JSON 출력 형식

```json
{
  "collected_at": "2025-10-29T14:30:00",
  "collector_host": "server01",
  "sql_server": "https://giipfaw.azurewebsites.net/api/giipApiSk2",
  "hosts": [
    {
      "host_name": "client01",
      "sessions": 2,
      "queries": [
        {
          "login_name": "dbuser",
          "status": "running",
          "cpu_time": 75000,
          "reads": 100,
          "writes": 10,
          "logical_reads": 500000,
          "start_time": "2025-10-29T14:25:00",
          "command": "SELECT",
          "query_text": "SELECT * FROM large_table WHERE..."
        }
      ]
    }
  ]
}
```

## 사전 요구사항

### MySQL 스크립트

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install mysql-client jq curl

# RHEL/CentOS
sudo yum install mysql jq curl
```

### MS SQL Server 스크립트

```bash
# Ubuntu 20.04
curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list | sudo tee /etc/apt/sources.list.d/msprod.list
sudo apt-get update
sudo apt-get install mssql-tools unixodbc-dev jq curl

# PATH 추가
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
source ~/.bashrc

# 연결 테스트
sqlcmd -S server.example.com -U username -P password -Q "SELECT @@VERSION"
```

## 설정 파일

### giipAgent.cnf 예시

```ini
# MySQL 설정
MySQLHost=mysql.example.com
MySQLPort=3306
MySQLUser=monitor_user
MySQLPassword=SecurePassword123
MySQLDatabase=performance

# MS SQL Server 설정
SqlConnectionString=Server=sqlserver.example.com;User Id=sa;Password=SecurePassword123;Database=master
# 또는 개별 설정
MSSQLHost=sqlserver.example.com
MSSQLPort=1433
MSSQLUser=sa
MSSQLPassword=SecurePassword123
MSSQLDatabase=master

# KVS 설정
Endpoint=https://giipfaw.azurewebsites.net/api/giipApiSk2
FunctionCode=your_function_code_here
UserToken=ffd96879858fe73fc31d923a74ae23b5
KType=lssn
KKey=12345
```

## 사용 방법

### 수동 실행

#### MySQL

```bash
# 설정 파일 사용
cd /home/giip/giipAgentLinux/giipscripts
bash dpa-put-mysql.sh

# 파라미터 직접 지정
bash dpa-put-mysql.sh -h mysql.example.com -u user -p password -d database

# 로그 확인
tail -f /var/log/giip/dpa_put_mysql_$(date +%Y%m%d).log
```

#### MS SQL Server

```bash
# 설정 파일 사용
cd /home/giip/giipAgentLinux/giipscripts
bash dpa-put-mssql.sh

# 파라미터 직접 지정
bash dpa-put-mssql.sh -h sqlserver.example.com -u sa -p password -d master

# 로그 확인
tail -f /var/log/giip/dpa_put_mssql_$(date +%Y%m%d).log
```

### Cron 자동 실행

#### MySQL (5분마다)

```bash
# Crontab 편집
crontab -e

# 추가
*/5 * * * * /home/giip/giipAgentLinux/giipscripts/dpa-put-mysql.sh >> /var/log/giip/dpa_put_mysql_cron.log 2>&1
```

#### MS SQL Server (5분마다)

```bash
# Crontab 편집
crontab -e

# 추가
*/5 * * * * /home/giip/giipAgentLinux/giipscripts/dpa-put-mssql.sh >> /var/log/giip/dpa_put_mssql_cron.log 2>&1
```

#### 시스템 Cron 파일 사용

```bash
# MySQL
sudo tee /etc/cron.d/giip-mysql-monitor << 'EOF'
# MySQL Performance Monitor (5분마다)
*/5 * * * * giip /home/giip/giipAgentLinux/giipscripts/dpa-put-mysql.sh >> /var/log/giip/dpa_put_mysql_cron.log 2>&1
EOF

# MS SQL Server
sudo tee /etc/cron.d/giip-mssql-monitor << 'EOF'
# MS SQL Server Performance Monitor (5분마다)
*/5 * * * * giip /home/giip/giipAgentLinux/giipscripts/dpa-put-mssql.sh >> /var/log/giip/dpa_put_mssql_cron.log 2>&1
EOF

# 권한 설정
sudo chmod 644 /etc/cron.d/giip-mysql-monitor
sudo chmod 644 /etc/cron.d/giip-mssql-monitor
```

## 로그 확인

### 실시간 모니터링

```bash
# MySQL
tail -f /var/log/giip/dpa_put_mysql_$(date +%Y%m%d).log

# MS SQL Server
tail -f /var/log/giip/dpa_put_mssql_$(date +%Y%m%d).log

# Cron 로그
tail -f /var/log/giip/dpa_put_mysql_cron.log
tail -f /var/log/giip/dpa_put_mssql_cron.log
```

### 에러 검색

```bash
# 오늘 에러 확인
grep ERROR /var/log/giip/dpa_put_mysql_$(date +%Y%m%d).log
grep ERROR /var/log/giip/dpa_put_mssql_$(date +%Y%m%d).log

# 최근 50줄
tail -50 /var/log/giip/dpa_put_mysql_$(date +%Y%m%d).log
```

## 트러블슈팅

### MySQL 연결 실패

```bash
# 연결 테스트
mysql -h mysql.example.com -u user -p -e "SELECT 1"

# 방화벽 확인
telnet mysql.example.com 3306

# 권한 확인
mysql> GRANT SELECT ON performance_schema.* TO 'monitor_user'@'%';
mysql> FLUSH PRIVILEGES;
```

### MS SQL Server 연결 실패

```bash
# 연결 테스트
sqlcmd -S sqlserver.example.com -U sa -P password -Q "SELECT 1"

# 포트 확인
telnet sqlserver.example.com 1433

# TCP/IP 프로토콜 활성화 (SQL Server 설정)
# SQL Server Configuration Manager → SQL Server Network Configuration → Protocols for MSSQLSERVER → TCP/IP: Enabled
```

### jq 명령어 없음

```bash
# Ubuntu/Debian
sudo apt-get install jq

# RHEL/CentOS
sudo yum install jq

# 설치 확인
jq --version
```

### 로그 디렉토리 권한 오류

```bash
# 디렉토리 생성
sudo mkdir -p /var/log/giip

# 권한 설정
sudo chown giip:giip /var/log/giip
sudo chmod 755 /var/log/giip

# 확인
ls -ld /var/log/giip
```

### Cron이 실행되지 않음

```bash
# Cron 서비스 확인
sudo systemctl status cron

# Cron 로그 확인
grep CRON /var/log/syslog | tail -20

# 수동 실행 테스트
bash /home/giip/giipAgentLinux/giipscripts/dpa-put-mysql.sh

# 스크립트 권한 확인
chmod +x /home/giip/giipAgentLinux/giipscripts/dpa-put-mysql.sh
chmod +x /home/giip/giipAgentLinux/giipscripts/dpa-put-mssql.sh
```

## 성능 최적화

### 느린 쿼리 필터링

기본적으로 **CPU 시간 50초 이상** 쿼리만 수집합니다.

#### 임계값 변경 (MySQL)

```bash
# dpa-put-mysql.sh 편집
vi /home/giip/giipAgentLinux/giipscripts/dpa-put-mysql.sh

# 51번째 줄 수정
WHERE pl.command != 'Sleep'
  AND pl.user != 'system user'
  AND pl.time > 30  # 50에서 30으로 변경 (30초 이상)
```

#### 임계값 변경 (MS SQL Server)

```bash
# dpa-put-mssql.sh 편집
vi /home/giip/giipAgentLinux/giipscripts/dpa-put-mssql.sh

# 139번째 줄 수정
WHERE s.is_user_process = 1
  AND r.cpu_time > 30000  # 50000에서 30000으로 변경 (30초)
```

### 로그 로테이션

```bash
# Logrotate 설정
sudo tee /etc/logrotate.d/giip << 'EOF'
/var/log/giip/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0644 giip giip
}
EOF

# 테스트
sudo logrotate -d /etc/logrotate.d/giip
```

## 보안 고려사항

### 1. 설정 파일 권한

```bash
# giipAgent.cnf 권한 (비밀번호 포함)
chmod 600 /home/giip/giipAgentLinux/giipAgent.cnf
chown giip:giip /home/giip/giipAgentLinux/giipAgent.cnf
```

### 2. 데이터베이스 사용자 권한 최소화

#### MySQL

```sql
-- 읽기 전용 모니터링 계정
CREATE USER 'monitor_user'@'%' IDENTIFIED BY 'SecurePassword123';
GRANT SELECT ON performance_schema.* TO 'monitor_user'@'%';
GRANT SELECT ON information_schema.* TO 'monitor_user'@'%';
GRANT PROCESS ON *.* TO 'monitor_user'@'%';
FLUSH PRIVILEGES;
```

#### MS SQL Server

```sql
-- 읽기 전용 모니터링 계정
CREATE LOGIN monitor_user WITH PASSWORD = 'SecurePassword123';
CREATE USER monitor_user FOR LOGIN monitor_user;

-- DMV 조회 권한
GRANT VIEW SERVER STATE TO monitor_user;
GRANT VIEW DATABASE STATE TO monitor_user;
```

### 3. 로그에서 민감정보 제거

```bash
# 로그 파일에서 비밀번호 제거
sed -i 's/Password=[^;]*/Password=***/g' /var/log/giip/dpa_put_mysql_*.log
sed -i 's/-p[^ ]*/-p***/g' /var/log/giip/dpa_put_mssql_*.log
```

## 데이터 흐름

```
[1] 스크립트 실행 (Cron, 5분마다)
    ↓
[2] giipAgent.cnf 읽기
    ↓
[3] DB 연결 및 쿼리 실행
    ↓
[4] JSON 생성 (호스트별 그룹화)
    ↓
[5] KVS API 호출 (POST)
    ↓
[6] tKVS 테이블 저장
    ↓
[7] pApiKVSAdvPutAutobySk (Daily Job)
    ↓
[8] tKVSAdvice 생성 (느린 쿼리 감지)
    ↓
[9] execgiipadv.sh (AI 분석)
    ↓
[10] Web UI (사용자에게 조언 표시)
```

## 테스트

### 전체 흐름 테스트

```bash
# 1. 수동 실행
cd /home/giip/giipAgentLinux/giipscripts
bash dpa-put-mysql.sh

# 2. 로그 확인
tail -30 /var/log/giip/dpa_put_mysql_$(date +%Y%m%d).log

# 3. tKVS 확인 (DB)
SELECT TOP 1 * FROM tKVS 
WHERE kFactor = 'sqlnetinv' 
ORDER BY kRegdt DESC

# 4. JSON 검증
SELECT TOP 1 kValue FROM tKVS 
WHERE kFactor = 'sqlnetinv' 
ORDER BY kRegdt DESC
-- JSON 파싱 확인

# 5. tKVSAdvice 확인 (Daily Job 후)
SELECT TOP 10 * FROM tKVSAdvice 
WHERE kafactor = 'sqlnetinv' 
ORDER BY kaRegdt DESC
```

## 관련 문서

- [SQLNETINV_DATA_FLOW.md](../../giipAgentAdmLinux/docs/SQLNETINV_DATA_FLOW.md) - 전체 데이터 흐름
- [dpa-put-mysql.ps1](../../giipAgentWin/giipscripts/dpa-put-mysql.ps1) - Windows 버전
- [dpa-put-mssql.ps1](../../giipAgentWin/giipscripts/dpa-put-mssql.ps1) - Windows 버전

## 버전 히스토리

### v1.0.0 (2025-10-29)
- ✨ MySQL 데이터 수집 스크립트 추가
- ✨ MS SQL Server 데이터 수집 스크립트 추가
- ✨ JSON 생성 및 KVS 업로드 기능
- ✨ 상세 로깅 및 에러 처리

## 라이선스

GIIP Project - Internal Use Only

---

**마지막 업데이트**: 2025-10-29  
**버전**: 1.0.0  
**관리자**: GIIP Team
