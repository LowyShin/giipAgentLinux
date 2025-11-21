# LSChkdt 업데이트 안 됨 문제 진단

> **상황**: giipAgent3.sh를 gateway 서버에서 실행했는데도 LSChkdt가 업데이트되지 않음  
> **목적**: 문제의 원인을 찾기 위해 어디를 확인해야 하는지 단계별 안내

---

## 진단 순서

```
1️⃣  giipAgent3.sh가 실제로 리모트 서버 체크를 했는가?
    ↓ (예) → 2️⃣
    ↓ (아니오) → [원인 1] Agent가 리모트 서버 목록을 못 가져옴
    
2️⃣  SSH 테스트가 성공했는가?
    ↓ (예) → 3️⃣
    ↓ (아니오) → [원인 2] SSH 테스트 실패
    
3️⃣  RemoteServerSSHTest API를 호출했는가?
    ↓ (예) → 4️⃣
    ↓ (아니오) → [원인 3] API 호출 안 함
    
4️⃣  API 응답이 성공 (200)인가?
    ↓ (예) → 5️⃣
    ↓ (아니오) → [원인 4] API 실패 또는 에러
    
5️⃣  SQL Server의 pApiGatewayServerPutbyAK SP가 실행됐는가?
    ↓ (예) → 6️⃣
    ↓ (아니오) → [원인 5] SP 미실행
    
6️⃣  LSChkdt가 업데이트됐는가?
    ✅ YES → 완료
    ❌ NO → [원인 6] LSChkdt 컬럼 없음 또는 업데이트 로직 안 탐
```

---

## 단계별 확인 방법

### 1️⃣ giipAgent3.sh가 리모트 서버 체크를 했는가?

#### 확인 방법

**A) Agent 로그 파일 확인**

```bash
# Gateway 서버에서 실행
tail -f /var/log/giipagent/giipAgent3.log

# 찾을 것:
# [5.4] Gateway 서버 목록 조회 시작
# [5.5] 서버 목록 파일 확인 성공  
# [5.6] 서버 JSON 파싱 완료
```

**로깅 포인트:**
- [로깅 포인트 #5.4] Gateway 서버 목록 조회 시작
- [로깅 포인트 #5.5] 서버 목록 파일 확인 성공
- [로깅 포인트 #5.6] 서버 JSON 파싱 완료

**B) Agent 프로세스 확인**

```bash
# giipAgent3.sh가 현재 실행 중인가?
ps aux | grep giipAgent3

# 실행 중이라면:
# - 얼마나 오래 실행 중?
# - 어떤 옵션으로 실행?
# - 에러 메시지 있나?
```

**C) 리모트 서버 목록이 있는가?**

```bash
# giipAgentGateway_servers.csv 또는 데이터베이스에서 리모트 서버 목록 확인
cat /path/to/giipAgentGateway_servers.csv

# 또는 SQL Server에서:
SELECT LSsn, HostName, gateway_ssh_* FROM tLSvr WHERE gateway_id = @GatewayId
```

#### 결과 해석

| 상황 | 의미 | 다음 단계 |
|------|------|---------|
| 로그에 "Remote Server Test" 기록 있음 | Agent가 체크를 시도함 | 2️⃣로 진행 |
| 로그에 기록 없음 | Agent가 체크를 안 함 | [원인 1] 확인 |
| PS aux에서 안 보임 | giipAgent3.sh가 실행 안 중 | [원인 1] 확인 |
| 리모트 서버 목록 없음 | 설정 부족 | [원인 1] 확인 |

---

### 2️⃣ SSH 테스트가 성공했는가?

#### 확인 방법

**A) Agent 로그에서 SSH 테스트 결과 찾기**

```bash
# Agent 로그에서 SSH 테스트 결과 찾기
grep "\[5.7\]\|\[5.10\]" /var/log/giipagent/giipAgent3.log | tail -20

# 찾을 것:
# [5.7] SSH 테스트 시작
# [5.10] SSH 연결 성공 → ssh_status=success
# [5.10-ERROR] SSH 연결 실패 → ssh_status=fail
```

**로깅 포인트:**
- [로깅 포인트 #5.7] SSH 테스트 시작
- [로깅 포인트 #5.10] SSH 연결 결과 (성공 또는 실패)

**B) Agent가 직접 SSH 테스트**

```bash
# Gateway 서버에서 리모트 서버로 직접 SSH 테스트
ssh -v user@remote-server-ip "echo OK"

# 결과:
# - "echo OK" 출력 → SSH 정상
# - 타임아웃 → 네트워크 문제
# - 인증 에러 → 키 또는 비밀번호 문제
```

#### 결과 해석

| 상황 | 의미 | 다음 단계 |
|------|------|---------|
| 로그에 "success" 또는 "PASS" | SSH 테스트 성공 | 3️⃣로 진행 |
| 로그에 "FAIL" 또는 타임아웃 | SSH 테스트 실패 | [원인 2] 확인 |
| 직접 SSH 테스트도 실패 | 네트워크/인증 문제 | [원인 2] 확인 |

---

### 3️⃣ RemoteServerSSHTest API를 호출했는가?

#### 확인 방법

**A) Agent 로그에서 API 호출 기록**

```bash
# API 호출 기록 찾기
grep "\[5.10.1\]\|\[5.10.2\]\|\[5.10.3\]\|\[5.10.4\]" /var/log/giipagent/giipAgent3.log | tail -20

# 찾을 것:
# [5.10.1] RemoteServerSSHTest API 호출 시작
# [5.10.2] RemoteServerSSHTest API 호출 성공
# [5.10.3] RemoteServerSSHTest API 호출 실패
# [5.10.4] RemoteServerSSHTest 모듈 로드 실패
```

또는:

```bash
# 6번대 로깅 포인트 확인 (API 응답)
grep "\[6.1\]\|\[6.2\]\|\[6.3\]\|\[6.4\]" /var/log/giipagent/giipAgent3.log | tail -20

# 찾을 것:
# [6.1] SSH 테스트 결과 API 호출 시작
# [6.2] SSH 테스트 결과 API 호출 성공 (RstVal=200)
# [6.3] SSH 테스트 결과 API 호출 실패 (RstVal!=200 또는 응답 없음)
# [6.4] SSH 테스트 결과 KVS 저장
```

**로깅 포인트:**
- [로깅 포인트 #5.10.1] RemoteServerSSHTest API 호출 시작 (gateway.sh에서)
- [로깅 포인트 #5.10.2] RemoteServerSSHTest API 호출 성공 (gateway.sh에서)
- [로깅 포인트 #5.10.3] RemoteServerSSHTest API 호출 실패 (gateway.sh에서)
- [로깅 포인트 #5.10.4] RemoteServerSSHTest 모듈 로드 실패 (gateway.sh에서)
- [로깅 포인트 #6.1] SSH 테스트 결과 API 호출 시작 (remote_ssh_test.sh에서)
- [로깅 포인트 #6.2] SSH 테스트 결과 API 호출 성공 (remote_ssh_test.sh에서)
- [로깅 포인트 #6.3] SSH 테스트 결과 API 호출 실패 (remote_ssh_test.sh에서)
- [로깅 포인트 #6.4] SSH 테스트 결과 KVS 저장 (remote_ssh_test.sh에서)

#### 결과 해석

| 상황 | 의미 | 다음 단계 |
|------|------|---------|
| 로그에 API 호출 기록 있음 | API가 호출됨 | 4️⃣로 진행 |
| 로그에 기록 없음 | API가 호출 안 됨 | [원인 3] 확인 |
| 직접 테스트에서 응답 200 | API 정상 작동 | 4️⃣로 진행 |
| 직접 테스트에서 500 에러 | API 실패 | [원인 4] 확인 |

---

### 4️⃣ API 응답이 성공 (200)인가?

#### 확인 방법

**A) Agent 로그에서 API 응답**

```bash
# API 응답 확인
grep "\[6.2\]\|\[6.3\]" /var/log/giipagent/giipAgent3.log | tail -20

# 찾을 것:
# [6.2] SSH 테스트 결과 API 호출 성공 → API가 200 응답
# [6.3] SSH 테스트 결과 API 호출 실패 → API가 200이 아님
```

**B) KVS에서 API 호출 기록 확인**

```bash
# KVS에서 API 호출 결과 확인
grep "remote_ssh_test_api" /var/log/giipagent/giipAgent3.log | tail -10

# 찾을 것:
# remote_ssh_test_api_success → API가 성공함
# remote_ssh_test_api_failed → API가 실패함
# remote_ssh_test_api_no_response → API 응답 없음
```

**로깅 포인트:**
- [로깅 포인트 #6.2] SSH 테스트 결과 API 호출 성공 (RstVal=200)
- [로깅 포인트 #6.3] SSH 테스트 결과 API 호출 실패 (RstVal!=200 또는 응답 없음)

#### 결과 해석

| 상황 | 의미 | 다음 단계 |
|------|------|---------|
| HTTP 200 응답 | API 성공 | 5️⃣로 진행 |
| HTTP 400 응답 | API 요청 오류 (param 오류) | [원인 4] 확인 |
| HTTP 500 응답 | API 서버 에러 | [원인 4] 확인 |
| 응답 없음 (타임아웃) | API 미응답 | [원인 4] 확인 |

---

### 5️⃣ SQL Server SP가 실행됐는가?

#### 확인 방법

**A) SQL Server 로그 확인**

```sql
-- SQL Server의 tLogSP 테이블에서 SP 실행 기록 확인
SELECT TOP 20 
  *
FROM tLogSP
WHERE spName = 'pApiGatewayServerPutbyAK'
ORDER BY logDateTime DESC

-- 찾을 것:
-- - logDateTime이 최근인지?
-- - spStatus가 'DONE' 또는 'SUCCESS'인지?
-- - spErrorMsg가 있는지?
```

**B) 직접 SP 실행 테스트**

```sql
-- SP가 존재하는지 확인
SELECT * FROM sys.procedures 
WHERE name = 'pApiGatewayServerPutbyAK'

-- SP 직접 실행 (테스트)
EXEC pApiGatewayServerPutbyAK
  @gatewayLssn = 71174,
  @remoteLssn = 71221,
  @sshStatus = 'success',
  @responseTime = 125

-- 결과 확인
SELECT TOP 1 * FROM tLSvr 
WHERE LSsn = 71221
ORDER BY LSChkdt DESC
```

**C) SQL Server 실시간 로그**

```bash
# SQL Server 실시간 로그 모니터링 (Linux)
tail -f /var/opt/mssql/log/errorlog

# Windows인 경우:
Get-EventLog -LogName Application -Source "MSSQL*" -Newest 50
```

#### 결과 해석

| 상황 | 의미 | 다음 단계 |
|------|-----|---------|
| tLogSP에 최근 기록 있음 | SP가 실행됨 | 6️⃣로 진행 |
| tLogSP에 기록 없음 | SP가 실행 안 됨 | [원인 5] 확인 |
| SP 직접 실행 성공 | SP 정상 작동 | 6️⃣로 진행 |
| SP 직접 실행 에러 | SP 논리 오류 | [원인 5] 확인 |

---

### 6️⃣ LSChkdt가 업데이트됐는가?

#### 확인 방법

**A) tLSvr 테이블에서 LSChkdt 확인**

```sql
-- LSChkdt 최근값 확인
SELECT 
  LSsn,
  HostName,
  LSChkdt,
  gateway_ssh_status,
  gateway_ssh_responseTime,
  gateway_ssh_error,
  ModifyDate
FROM tLSvr
WHERE LSsn = 71221
ORDER BY LSChkdt DESC

-- 결과 해석:
-- - LSChkdt가 현재 시간에 가깝다? → 업데이트됨
-- - LSChkdt가 예전 시간이다? → 업데이트 안 됨
-- - gateway_ssh_* 컬럼이 NULL? → 데이터 저장 안 됨
```

**B) KVS에서 최근 기록 확인**

```sql
-- KVS에서 SSH 테스트 기록 확인
SELECT TOP 50
  *
FROM tKVS
WHERE kKey = 'lssn_71221'
  AND kFactor = 'giipagent'
  AND kFactorDetail LIKE '%ssh%'
ORDER BY kDateTime DESC

-- 찾을 것:
-- - 최근 기록이 있는가?
-- - sshStatus 값은?
-- - responseTime 값은?
```

**C) 변경 이력 확인**

```sql
-- tLSvr 변경 이력 (ModifyDate 확인)
SELECT TOP 10
  LSsn,
  HostName,
  LSChkdt,
  ModifyDate,
  ModifyUser
FROM tLSvr
WHERE LSsn = 71221
ORDER BY ModifyDate DESC

-- 찾을 것:
-- - ModifyDate가 최근인가?
-- - ModifyUser가 'pApiGatewayServerPutbyAK'인가? (또는 API 사용자)
```

#### 결과 해석

| 상황 | 의미 | 다음 단계 |
|------|------|---------|
| LSChkdt가 현재 시간 | 업데이트 완료 ✅ | 진단 완료 |
| LSChkdt가 예전 시간 | 업데이트 안 됨 ❌ | [원인 분석] |
| gateway_ssh_* 컬럼이 NULL | 데이터가 저장 안 됨 | [원인 6] 확인 |
| KVS에 기록 없음 | API가 호출 안 됨 | [원인 3] 확인 |

---

## 원인별 확인 & 해결

### [원인 1] Agent가 리모트 서버 목록을 못 가져옴

#### 확인

```bash
# 1. giipAgent3.sh가 실행 중인가?
ps aux | grep giipAgent3

# 2. 리모트 서버 목록 파일이 있는가?
ls -la /path/to/giipAgentGateway_servers.csv

# 3. 로그에 에러 메시지가 있는가?
grep -i "error\|fail\|not found" /var/log/giipagent/giipAgent3.log
```

#### 해결

```bash
# 1. giipAgent3.sh 수동 실행
cd /path/to/giipAgent
bash ./giipAgent3.sh -gateway

# 2. 로그 모니터링
tail -f /var/log/giipagent/giipAgent3.log

# 3. 에러 메시지 확인 후 조치
# - 파일 권한 문제? → chmod 755 giipAgent3.sh
# - 경로 오류? → 절대 경로 확인
# - 리모트 서버 목록 없음? → CSV 파일 생성
```

---

### [원인 2] SSH 테스트 실패

#### 확인

```bash
# 1. Gateway에서 리모트 서버로 SSH 접근 가능?
ssh -v user@remote-server "echo OK"

# 2. SSH 포트 열려있나?
telnet remote-server 22
또는
nc -zv remote-server 22

# 3. 인증 정보 맞나?
# - 키 파일이 있는가?
# - 비밀번호가 맞는가?
# - 사용자 계정이 있는가?
```

#### 해결

```bash
# 1. SSH 키 설정
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_remote

# 2. 공개키를 리모트 서버에 복사
ssh-copy-id -i ~/.ssh/id_rsa_remote.pub user@remote-server

# 3. 직접 SSH 테스트
ssh -i ~/.ssh/id_rsa_remote user@remote-server "echo OK"

# 4. giipAgent3.sh 설정에서 SSH 키 경로 확인
# giipagentGateway.sh에서 SSH_KEY_PATH 확인
```

---

### [원인 3] API 호출 안 함

#### 확인

```bash
# 1. giipAgent3.sh에서 API 호출 부분이 있는가?
grep -n "RemoteServerSSHTest\|curl\|POST" /path/to/giipAgent3.sh

# 2. API 엔드포인트 주소가 맞는가?
grep -n "api.*url\|endpoint" /path/to/giipAgent3.sh

# 3. API 호출 코드가 실제로 실행되고 있는가?
# 로그에 API 호출 기록이 있나?
grep "POST\|curl\|RemoteServerSSHTest" /var/log/giipagent/giipAgent3.log
```

#### 해결

```bash
# 1. API 호출 로직이 없다면:
# - REMOTE_SERVER_SSH_TEST_DETAILED_SPEC.md의 "실행 흐름"을 참고해서
#   giipAgent3.sh와 lib/gateway.sh에 API 호출 코드 추가

# 2. API 호출 코드가 있으나 실행 안 됨이라면:
# - 조건문 확인 (if [ $sshStatus == "success" ])
# - 변수값 확인 (echo $apiUrl, echo $gatewayLssn)

# 3. API 엔드포인트 수정:
# 로컬: http://localhost:7071/api/RemoteServerSSHTest
# Azure: https://giipapi-sk2.azurewebsites.net/api/RemoteServerSSHTest
```

---

### [원인 4] API 실패 또는 에러

#### 확인

```bash
# 1. API 로그 확인
# Azure Portal에서 Logs 확인
# 또는 로컬 console.log 확인

# 2. API 요청 데이터 확인
# - gatewayLssn: 71174 (숫자)
# - remoteLssn: 71221 (숫자)
# - sshStatus: 'success' 또는 'fail' (문자열)
# - responseTime: 125 (숫자)

# 3. API 응답 에러 메시지
grep -i "error\|exception\|failed" /path/to/api/logs

# 4. DB 연결 확인
# API에서 SQL Server에 연결 가능한가?
# connection string이 맞는가?
```

#### 해결

```bash
# 1. API 요청 데이터 형식 확인
# JSON 형식이 맞는가?
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"gatewayLssn":71174,"remoteLssn":71221,"sshStatus":"success","responseTime":125}' \
  http://localhost:7071/api/RemoteServerSSHTest -v

# 2. API 로그에서 에러 원인 파악
# - "SP not found" → pApiGatewayServerPutbyAK SP가 없음 ([원인 5] 참고)
# - "Database connection failed" → DB 연결 문제
# - "Parameter validation failed" → 파라미터 오류

# 3. API 코드 수정 (if needed)
# REMOTE_SERVER_SSH_TEST_DETAILED_SPEC.md의 "API 코드" 참고
```

---

### [원인 5] SP 미실행

#### 확인

```sql
-- 1. SP가 존재하는가?
SELECT * FROM sys.procedures 
WHERE name = 'pApiGatewayServerPutbyAK'

-- 2. SP 권한은?
SELECT * FROM sys.database_principals
WHERE name = 'db_datareader'
  OR name = 'db_datawriter'

-- 3. tLogSP에 실행 기록이 있는가?
SELECT TOP 10 * FROM tLogSP
WHERE spName = 'pApiGatewayServerPutbyAK'
ORDER BY logDateTime DESC
```

#### 해결

```sql
-- 1. SP가 없다면 생성
-- REMOTE_SERVER_SSH_TEST_DETAILED_SPEC.md의 "SP 코드" 참고해서
-- 다음 SP를 생성:
-- - pApiGatewayServerPutbyAK (리모트 서버 업데이트)
-- - 또는 pApiRemoteServerSSHTestbyAK (테스트만)

-- 2. SP 권한 설정
GRANT EXECUTE ON pApiGatewayServerPutbyAK TO [api_user]

-- 3. SP 직접 실행해서 테스트
EXEC pApiGatewayServerPutbyAK
  @gatewayLssn = 71174,
  @remoteLssn = 71221,
  @sshStatus = 'success',
  @responseTime = 125

-- 결과 확인
SELECT * FROM tLSvr WHERE LSsn = 71221
```

---

### [원인 6] LSChkdt 컬럼 없음 또는 업데이트 로직 오류

#### 확인

```sql
-- 1. LSChkdt 컬럼이 있는가?
SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'tLSvr'
  AND COLUMN_NAME = 'LSChkdt'

-- 2. gateway_ssh_* 컬럼들이 있는가?
SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'tLSvr'
  AND COLUMN_NAME LIKE 'gateway_ssh%'

-- 3. 필요한 컬럼이 몇 개나 있는가?
SELECT COUNT(*) AS column_count FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'tLSvr'
  AND COLUMN_NAME LIKE 'gateway_ssh%'
  -- 필요: gateway_ssh_host, gateway_ssh_port, gateway_ssh_user, gateway_ssh_status, gateway_ssh_responseTime
```

#### 해결

```sql
-- 1. LSChkdt 컬럼 추가 (없는 경우)
ALTER TABLE tLSvr
ADD LSChkdt DATETIME DEFAULT GETUTCDATE()

-- 2. gateway_ssh_* 컬럼 추가 (없는 경우)
ALTER TABLE tLSvr
ADD gateway_ssh_host NVARCHAR(255) NULL,
    gateway_ssh_port INT NULL,
    gateway_ssh_user NVARCHAR(255) NULL,
    gateway_ssh_status NVARCHAR(50) NULL,
    gateway_ssh_responseTime INT NULL,
    gateway_ssh_error NVARCHAR(MAX) NULL

-- 3. SP 코드에서 UPDATE 로직 확인
-- REMOTE_SERVER_SSH_TEST_DETAILED_SPEC.md의 "SP 코드" 참고
-- UPDATE 문이 다음 컬럼들을 포함하는가?
--   - LSChkdt = GETUTCDATE()
--   - gateway_ssh_status = @sshStatus
--   - gateway_ssh_responseTime = @responseTime
--   - ModifyDate = GETUTCDATE()
```

---

## 최종 검증

진단이 완료되었다면, 다음을 확인하세요:

### 체크리스트

```
☐ 1. giipAgent3.sh가 리모트 서버 체크를 했는가?
     → 로그에서 확인
     
☐ 2. SSH 테스트가 성공했는가?
     → 로그와 직접 SSH 테스트로 확인
     
☐ 3. RemoteServerSSHTest API를 호출했는가?
     → 로그와 API 직접 호출로 확인
     
☐ 4. API 응답이 성공 (200)인가?
     → API 응답 코드 확인
     
☐ 5. pApiGatewayServerPutbyAK SP가 실행됐는가?
     → tLogSP에서 확인
     
☐ 6. LSChkdt가 업데이트됐는가?
     → tLSvr에서 LSChkdt 확인
     
☐ 모든 항목이 '✓'인가?
     → YES: 문제 해결됨 ✅
     → NO: 위의 원인별 해결책 참고
```

---

## 참고 문서

- **[REMOTE_SERVER_SSH_TEST_DETAILED_SPEC.md](./REMOTE_SERVER_SSH_TEST_DETAILED_SPEC.md)**: API/SP/DB 스펙
- **[REMOTE_SERVER_SSH_TEST_TROUBLESHOOTING.md](./REMOTE_SERVER_SSH_TEST_TROUBLESHOOTING.md)**: 트러블슈팅 가이드
- **[giipAgent3.sh](../giipAgent3.sh)**: Agent 스크립트
- **[lib/gateway.sh](../lib/gateway.sh)**: SSH 테스트 구현
