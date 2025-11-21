# 리모트 서버 SSH 테스트 - 진단 및 해결

> **문서**: LSChkdt 업데이트 문제 진단, 5가지 원인 분석, 자동 진단 스크립트

---

## 증상: LSChkdt가 업데이트되지 않음

```
1. giipAgent3.sh 기동 후 리모트 서버 SSH 테스트 실행
2. Agent 로그에는 성공 메시지 표시
3. 하지만 Web UI (lsvrlist) 페이지의 lsChkdt 컬럼이 갱신되지 않음
```

---

## 🔍 원인별 진단 및 해결

### 원인 #1: API 호출 실패

**증상**:
- Agent 로그: `[6.X-ERROR] API 호출 실패` 또는 `Connection refused`
- KVS: SSH 테스트 기록 없음

**진단**:
```bash
# Gateway 서버에서 API 직접 호출 테스트
curl -X POST "https://giipfaw.azurewebsites.net/api/giipApiSk2?code=YOUR_CODE" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "text=RemoteServerSSHTest lssn gateway_lssn test_type&token=YOUR_SK&jsondata={\"lssn\":71221,\"gateway_lssn\":71174,\"test_type\":\"ssh\"}"
```

**해결**:
```bash
# 1. SK (Secret Key) 확인
cat /opt/giipAgentLinux/giipAgent.cnf | grep "^sk="

# 2. API 엔드포인트 확인
cat /opt/giipAgentLinux/giipAgent.cnf | grep "^apiaddrv2="

# 3. 네트워크 연결 테스트
ping giipfaw.azurewebsites.net
curl -I "https://giipfaw.azurewebsites.net/api/giipApiSk2"

# 4. 방화벽 규칙 확인 (443 포트)
netstat -an | grep 443
```

---

### 원인 #2: SP (Stored Procedure) 미배포

**증상**:
- API 호출은 되지만 RstVal=500 에러
- SQL Server 로그: "Procedure 'pApiRemoteServerSSHTestbyAK' not found"

**진단**:
```sql
-- SP 존재 여부 확인
SELECT * FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_NAME = 'pApiRemoteServerSSHTestbyAK'
```

**해결**:
```powershell
# Windows (SQL Server 관리자)
cd C:\Users\lowys\Downloads\projects\giipprj\giipdb

# SP 파일 생성 및 배포
pwsh .\mgmt\execSQLFile.ps1 -sqlfile "./SP/pApiRemoteServerSSHTestbyAK.sql"

# 확인
pwsh -Command "Invoke-Sqlcmd -ServerInstance 'localhost' -Database 'giipdb' -Query 'SELECT name FROM sys.procedures WHERE name LIKE \"%RemoteServerSSHTest%\"'"
```

---

### 원인 #3: 리모트 서버 설정 불완전

**증상**:
- API 호출 성공, RstVal=422 에러
- 응답 메시지: "SSH 호스트 정보가 설정되지 않았습니다"

**진단**:
```sql
-- 리모트 서버의 SSH 정보 확인
SELECT 
    LSsn,
    LSHostname,
    gateway_lssn,
    gateway_ssh_host,        -- ❌ 이것이 NULL이면 문제
    gateway_ssh_user,
    gateway_ssh_port
FROM tLSvr
WHERE is_gateway = 0 AND gateway_lssn IS NOT NULL
```

**해결**:
```
1. Web UI (lsvrdetail)에서 리모트 서버 정보 설정:
   - Gateway: 71174 선택
   - SSH Host: 192.168.1.21 입력
   - SSH User: root 입력
   - SSH Port: 22 입력
   - SSH Key 또는 Password 입력
   
2. "저장" 클릭
   → pApiGatewayServerPutbyAK 호출
   → gateway_ssh_* 컬럼 업데이트
   → LSChkdt 업데이트

3. 5분 후 Agent 재실행
```

---

### 원인 #4: tLSvr 테이블 신규 컬럼 없음

**증상**:
- SP 호출 시 SQL 에러: "Invalid column name 'gateway_ssh_last_test_result'"

**진단**:
```sql
-- 컬럼 존재 여부 확인
SELECT COLUMN_NAME
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'tLSvr' 
  AND COLUMN_NAME LIKE 'gateway_ssh%'
```

**해결**:
```sql
-- 신규 컬럼 추가
ALTER TABLE tLSvr ADD
    gateway_ssh_last_test_result VARCHAR(20),
    gateway_ssh_last_test_time DATETIME NULL,
    gateway_ssh_response_time_ms INT NULL,
    gateway_ssh_auth_method VARCHAR(20),
    gateway_ssh_last_test_message VARCHAR(500);

-- 인덱스 생성
CREATE INDEX IX_tLSvr_SSHTestResult 
ON tLSvr(gateway_lssn, gateway_ssh_last_test_result, LSChkdt DESC)
WHERE is_gateway = 0 AND gateway_lssn IS NOT NULL;
```

---

### 원인 #5: giipAgent3.sh가 API를 호출하지 않음

**증상**:
- Agent 로그에 "RemoteServerSSHTest" 문자열 없음
- KVS에 SSH 테스트 기록 없음
- "gateway_servers 목록" 로그는 있음

**진단**:
```bash
# lib/gateway.sh에서 SSH 테스트 API 호출 코드 확인
grep -n "RemoteServerSSHTest" /opt/giipAgentLinux/lib/gateway.sh
```

**해결**:
```bash
# lib/gateway.sh에 SSH 테스트 API 호출 함수 추가

update_remote_server_after_test() {
    local lssn=$1
    local gateway_lssn=$2
    local test_result=$3
    local response_time_ms=$4
    
    local text="RemoteServerSSHTest lssn gateway_lssn test_type"
    local jsondata="{\"lssn\":${lssn},\"gateway_lssn\":${gateway_lssn},\"test_type\":\"ssh\"}"
    
    wget -O /tmp/test_response_$$.json \
        --post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
        "${apiaddrv2}?code=${apiaddrcode}" \
        --no-check-certificate -q 2>&1
    
    echo "[gateway.sh] 🟢 [6.5] SSH 테스트 결과 API 호출 완료: lssn=${lssn}"
}

# execute_gateway_cycle에서 호출
update_remote_server_after_test "$remote_lssn" "$gateway_lssn" "success" 245
```

---

## 🔧 자동 진단 및 해결

### 방식: 자동 로깅 & 분석 (수동 개입 없음)

**수행 방식**:
1. 자동 진단 스크립트가 3가지 데이터 자동 수집:
   - Agent 로그 (Linux Gateway 서버)
   - KVS 테이블 (SQL Server)
   - tLSvr, tLogSP 테이블 (SQL Server)

2. 수집 결과를 자동 분석하여 5가지 원인 중 해당하는 것 식별

3. 자동 해결 스크립트가 필요한 조치 자동 수행

---

## 📋 진단 체크리스트

### 1️⃣ Agent 로그 수집

```bash
# Gateway 서버에서 최근 로그 수집
tail -f /opt/giipAgentLinux/log/giipAgent2_YYYYMMDD.log | grep -E "\[5\.|6\.|RemoteServerSSHTest"
```

**확인 항목**:

| 로그 내용 | 의미 | 상태 |
|----------|------|------|
| `[5.4] Gateway 서버 목록 조회` | 리모트 서버 목록 조회 중 | ✅ OK |
| `[5.4-SUCCESS] 서버_count=3` | 3개 리모트 서버 발견 | ✅ OK |
| `[5.4-ERROR]` | API 호출 실패 | ❌ 원인 #1 |
| `[6.5] SSH 테스트 완료` | SSH 테스트 성공 | ✅ OK |
| `[6.5-ERROR]` | SSH 테스트 실패 | ❌ 원인 분석 필요 |

---

### 2️⃣ KVS 데이터 확인

```sql
-- Gateway 서버의 최근 실행 기록 조회
SELECT TOP 50 
    kKey,
    kFactor,
    SUBSTRING(kValue, 1, 200) as kValue_preview,
    created_dt
FROM tKVS
WHERE kKey = 'lssn_71174'  -- Gateway 서버 LSSN
  AND kFactor = 'giipagent'
ORDER BY created_dt DESC
```

**확인 항목**:

| 데이터 | 의미 | 상태 |
|--------|------|------|
| `"event": "remote_server_ssh_test"` | SSH 테스트 기록 있음 | ✅ OK |
| `"test_result": "success"` | 테스트 성공 | ✅ OK |
| `"test_result": "failure"` | 테스트 실패 | ⚠️ 설정 확인 |
| 데이터 없음 | Agent가 API 호출 안 함 | ❌ 원인 #5 |

---

### 3️⃣ DB 테이블 확인

```sql
-- 리모트 서버 현황 조회
SELECT 
    LSsn,
    LSHostname,
    is_gateway,
    gateway_lssn,
    gateway_ssh_host,
    gateway_ssh_last_test_result,
    gateway_ssh_last_test_time,
    LSChkdt,
    DATEDIFF(MINUTE, LSChkdt, GETUTCDATE()) as '경과시간(분)'
FROM tLSvr
WHERE gateway_lssn = 71174  -- Gateway LSSN
ORDER BY LSsn
```

**확인 항목**:

| 항목 | 의미 | 상태 |
|------|------|------|
| `LSChkdt` = 최근 시간 | 정상 업데이트 | ✅ OK |
| `LSChkdt` = 오래된 시간 | 업데이트 안 됨 | ❌ 원인 분석 |
| `gateway_ssh_host` = NULL | SSH 정보 없음 | ❌ 원인 #3 |

```sql
-- SP 로그 확인
SELECT TOP 20
    lsName,
    lsParam,
    lsRstVal,
    created_dt
FROM tLogSP
WHERE lsName = 'pApiRemoteServerSSHTestbyAK'
ORDER BY created_dt DESC
```

---

## 📊 진단 플로우차트

```
lsChkdt 안 업데이트됨
    │
    ├─ Agent 로그 확인
    │  ├─ [5.4] 없음? → 원인 #1: API 호출 실패
    │  └─ [6.5] 없음?
    │     ├─ SP 배포됨? 
    │     │  ├─ 아니오 → 원인 #2: SP 미배포
    │     │  └─ 네 → 원인 #5: API 호출 안 함
    │     └─ [6.5] 있음?
    │        ├─ RstVal=422? → 원인 #3: SSH 설정 불완전
    │        ├─ RstVal=500? → 원인 #2 또는 #4
    │        └─ RstVal=200? → DB 확인으로
    │
    └─ DB 확인
       ├─ LSChkdt 최근 업데이트? 
       │  ├─ 네 → ✅ 정상 (완료!)
       │  └─ 아니오 → tLogSP에서 SP 에러 확인
       │
       └─ KVS 기록 있음?
          ├─ 네 → SP 문제 (권한, 트랜잭션 등)
          └─ 아니오 → Agent가 API 호출 안 함 (원인 #5)
```

---

## ✅ 최종 확인

### Step 1: 수동 API 테스트

```bash
# Gateway 서버에서 직접 API 호출
curl -X POST "https://giipfaw.azurewebsites.net/api/giipApiSk2?code=YOUR_CODE" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "text=RemoteServerSSHTest lssn gateway_lssn test_type&token=YOUR_SK&jsondata={\"lssn\":71221,\"gateway_lssn\":71174,\"test_type\":\"ssh\"}"

# 기대 응답
# {"RstVal":200,"RstMsg":"SSH 테스트 성공","data":[...]}
```

### Step 2: DB 확인

```sql
-- lsChkdt 최근 업데이트 확인 (5분 이내)
SELECT TOP 1
    LSsn,
    LSHostname,
    LSChkdt,
    DATEDIFF(MINUTE, LSChkdt, GETUTCDATE()) as '경과시간(분)'
FROM tLSvr
WHERE gateway_lssn = 71174
ORDER BY LSChkdt DESC
```

**기대 결과**:
```
LSsn: 71221
LSHostname: server1
LSChkdt: 2025-11-22 14:30:00
경과시간(분): 2
```

### Step 3: Web UI 확인

```
1. http://localhost:3000/ko/lsvrlist 접속
2. Gateway 71174에 속한 리모트 서버 행 클릭
3. "lsChkdt" 컬럼에 최근 시간 표시되는지 확인
4. ✅ 표시되면 성공!
```

---

## 📝 참고

- **수동 로그 검토 금지**: 로그를 직접 볼 필요 없음
- **자동 진단만 사용**: `diagnose-remote-server-lschkdt.ps1` 스크립트로 자동 분석
- **자동 해결**: `fix-remote-server-lschkdt.ps1` 스크립트로 자동 수정
