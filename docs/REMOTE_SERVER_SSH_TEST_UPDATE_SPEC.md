# 리모트 서버 SSH 접속 테스트 및 정보 갱신 API 사양

> **📅 문서 메타데이터**  
> - 작성일: 2025-11-22
> - 버전: 1.0
> - 목적: 리모트 서버 SSH 접속 테스트 후 연결 상태, 접근 가능 여부, OS 정보 등을 DB에 기록하는 API 사양 문서

---

## 📋 목차

1. [개요](#개요)
2. [아키텍처](#아키텍처)
3. [API 사양](#api-사양)
4. [DB 업데이트 메커니즘](#db-업데이트-메커니즘)
5. [실행 흐름](#실행-흐름)
6. [에러 처리](#에러-처리)
7. [KVS 로깅](#kvs-로깅)

---

## 개요

### 목적
**리모트 서버** (Gateway를 경유하는 서버)에 대한 SSH 접속 테스트를 수행하고, 결과를 DB에 저장하여:
- Gateway가 해당 리모트 서버에 실제로 접근 가능한지 검증
- 접속 성공/실패 여부, 응답 시간, SSH 인증 방식 등을 기록
- 웹 UI에서 리모트 서버의 연결 상태를 표시

### 호출자
1. **Gateway Agent** (giipAgent3.sh)
   - 리모트 서버 목록 조회 후 각 서버에 SSH 테스트 실행
   - 결과를 API로 전송

2. **웹 UI** (lsvrdetail 페이지)
   - 사용자가 "연결 테스트" 버튼 클릭 시 API 호출
   - 테스트 결과를 즉시 표시

3. **정기 모니터링**
   - 정기적으로 리모트 서버 연결 상태 갱신
   - 문제 발생 시 알림

---

## 아키텍처

```
┌─────────────────────────────────────────────────────────┐
│  Gateway Agent (giipAgent3.sh)                          │
│  또는                                                    │
│  Web UI (lsvrdetail - RemoteServerTestButton)          │
└──────────────────────┬──────────────────────────────────┘
                       │
                       │ SSH 연결 테스트 + 결과 수집
                       ▼
┌─────────────────────────────────────────────────────────┐
│  1️⃣  RemoteServerSSHTest API                            │
│  (giipfaw Azure Function - giipApiSk2/run.ps1)         │
│  - SP: pApiRemoteServerSSHTestbyAK                     │
└──────────────────────┬──────────────────────────────────┘
                       │
                       │ 접속 정보 저장 + 상태 업데이트
                       ▼
┌─────────────────────────────────────────────────────────┐
│  SQL Server Database (tLSvr)                            │
│  - gateway_ssh_last_test_result                        │
│  - gateway_ssh_last_test_time                          │
│  - gateway_ssh_response_time_ms                        │
│  - gateway_ssh_auth_method                             │
└─────────────────────────────────────────────────────────┘
                       │
                       │ 상태 조회
                       ▼
┌─────────────────────────────────────────────────────────┐
│  Web UI (lsvrdetail)                                    │
│  - 연결 상태 표시: ✅ 성공 / ❌ 실패                    │
│  - 응답 시간: 123ms                                     │
│  - 마지막 테스트: 2025-11-22 14:30:00                  │
└─────────────────────────────────────────────────────────┘
```

---

## API 사양

### 1️⃣ RemoteServerSSHTest (SSH 접속 테스트 후 정보 갱신)

#### 엔드포인트
```
POST https://giipfaw.azurewebsites.net/api/giipApiSk2
```

#### 요청 (Request)

**형식**: `application/x-www-form-urlencoded`

```
text=RemoteServerSSHTest lssn gateway_lssn test_type
token={secret_key}
jsondata={...}
```

**파라미터**:

| 파라미터 | 위치 | 타입 | 필수 | 설명 | 예시 |
|---------|------|------|------|------|------|
| `text` | form | string | ✅ | API 명령 (고정값) | `RemoteServerSSHTest lssn gateway_lssn test_type` |
| `token` | form | string | ✅ | Secret Key (SK 인증) | `ffd96879858fe73fc31d923a74ae23b5` |
| `jsondata` | form | JSON | ✅ | 요청 데이터 | `{...}` |

**jsondata 구조**:

```json
{
  "lssn": 71221,                    // [필수] 테스트할 리모트 서버 LSSN
  "gateway_lssn": 71174,            // [필수] Gateway 서버 LSSN
  "test_type": "ssh",               // [필수] 테스트 유형 (현재는 "ssh"만 지원)
  "test_timeout_sec": 10            // [선택] 타임아웃 (초, 기본값: 10)
}
```

#### 응답 (Response)

**성공 (HTTP 200)**:

```json
{
  "RstVal": 200,
  "RstMsg": "SSH 접속 테스트 성공",
  "data": [
    {
      "lssn": 71221,
      "hostname": "server1",
      "gateway_lssn": 71174,
      "ssh_host": "192.168.1.21",
      "ssh_port": 22,
      "ssh_user": "root",
      "ssh_auth_method": "key",           // "key" 또는 "password"
      "test_result": "success",           // "success" 또는 "failure"
      "test_message": "SSH connection successful",
      "response_time_ms": 245,            // 응답 시간 (밀리초)
      "last_test_time": "2025-11-22 14:30:00",
      "os_info": "Ubuntu 20.04",          // 테스트 중 수집 (선택)
      "kernel_version": "5.4.0-42-generic" // (선택)
    }
  ]
}
```

**실패 (HTTP 200, RstVal=4xx)**:

```json
{
  "RstVal": 401,
  "RstMsg": "인증 실패 (Secret Key 불일치)",
  "data": []
}
```

```json
{
  "RstVal": 404,
  "RstMsg": "리모트 서버를 찾을 수 없음 (LSSN: 71221)",
  "data": []
}
```

```json
{
  "RstVal": 422,
  "RstMsg": "SSH 접속 테스트 실패: Connection timeout",
  "data": [
    {
      "lssn": 71221,
      "test_result": "failure",
      "test_message": "Connection timeout after 10 seconds",
      "response_time_ms": 10000
    }
  ]
}
```

#### 응답 코드

| RstVal | 의미 | 원인 | 대응 |
|--------|------|------|------|
| 200 | ✅ 성공 | SSH 접속 성공 | DB 업데이트 완료, UI에 "✅ 성공" 표시 |
| 401 | 🔓 인증 실패 | Secret Key 불일치 | SK 확인, API 다시 호출 |
| 404 | 🔍 리모트 서버 없음 | LSSN이 DB에 없음 | 리모트 서버 등록 여부 확인 |
| 422 | ❌ 접속 실패 | SSH 연결 타임아웃/거부 | 방화벽, 네트워크, SSH 설정 확인 |
| 500 | ⚠️ 서버 에러 | Azure Function 오류 | 로그 확인, 지원팀 연락 |

---

## DB 업데이트 메커니즘

### Stored Procedure: pApiRemoteServerSSHTestbyAK

**파일**: `giipdb/SP/pApiRemoteServerSSHTestbyAK.sql`

#### 서명

```sql
CREATE PROCEDURE pApiRemoteServerSSHTestbyAK
    @sk VARCHAR(200),                    -- Secret Key
    @lssn INT,                          -- 리모트 서버 LSSN
    @gateway_lssn INT,                  -- Gateway 서버 LSSN
    @test_type VARCHAR(50) = 'ssh',    -- 테스트 유형
    @test_timeout_sec INT = 10         -- 타임아웃 (초)
AS
```

#### 실행 로직 (5단계)

##### 1️⃣ 인증 확인 (Authentication)
```sql
-- Secret Key → 고객사 번호 (CSN) 조회
SELECT @csn = csn FROM tLSvrAuth WITH(NOLOCK)
WHERE sk = @sk AND sk_status = 1

IF @csn IS NULL
BEGIN
    -- 🔴 [로깅 포인트 #6.1] 인증 실패
    INSERT INTO tLogSP (lsName, lsParam, lsRstVal)
    VALUES ('pApiRemoteServerSSHTestbyAK', 
            'auth_failed', 
            '401 - Secret Key mismatch')
    
    SELECT 401 AS RstVal, 
           'Secret Key 불일치' AS RstMsg
    RETURN
END
```

##### 2️⃣ 리모트 서버 존재 확인 (Remote Server Validation)
```sql
-- 리모트 서버 존재 및 권한 확인
IF NOT EXISTS(
    SELECT 1 FROM tLSvr WITH(NOLOCK)
    WHERE LSSN = @lssn 
      AND is_gateway = 0                    -- 반드시 리모트 서버여야 함
      AND gateway_lssn = @gateway_lssn      -- 지정된 Gateway에 소속
      AND CSn IN (
          SELECT CSn FROM tLSvrAuth WITH(NOLOCK)
          WHERE sk = @sk
      )
)
BEGIN
    -- 🔴 [로깅 포인트 #6.2] 리모트 서버 없음
    INSERT INTO tLogSP (lsName, lsParam, lsRstVal)
    VALUES ('pApiRemoteServerSSHTestbyAK', 
            'server_not_found_lssn:' + CAST(@lssn AS VARCHAR), 
            '404 - Remote server not found')
    
    SELECT 404 AS RstVal, 
           'LSSN ' + CAST(@lssn AS VARCHAR) + '은 리모트 서버가 아니거나 접근 권한이 없습니다' AS RstMsg
    RETURN
END
```

##### 3️⃣ Gateway 서버 확인 (Gateway Validation)
```sql
-- Gateway 서버 존재 확인
IF NOT EXISTS(
    SELECT 1 FROM tLSvr WITH(NOLOCK)
    WHERE LSSN = @gateway_lssn 
      AND is_gateway = 1
      AND CSn IN (
          SELECT CSn FROM tLSvrAuth WITH(NOLOCK)
          WHERE sk = @sk
      )
)
BEGIN
    -- 🔴 [로깅 포인트 #6.3] Gateway 서버 없음
    INSERT INTO tLogSP (lsName, lsParam, lsRstVal)
    VALUES ('pApiRemoteServerSSHTestbyAK', 
            'gateway_not_found_lssn:' + CAST(@gateway_lssn AS VARCHAR), 
            '404 - Gateway server not found')
    
    SELECT 404 AS RstVal, 
           'Gateway 서버 LSSN ' + CAST(@gateway_lssn AS VARCHAR) + '을 찾을 수 없습니다' AS RstMsg
    RETURN
END
```

##### 4️⃣ SSH 정보 조회 (SSH Configuration Retrieval)
```sql
-- 리모트 서버의 SSH 정보 조회
SELECT 
    @ssh_host = gateway_ssh_host,
    @ssh_port = ISNULL(gateway_ssh_port, 22),
    @ssh_user = ISNULL(gateway_ssh_user, 'root'),
    @ssh_key_path = gateway_ssh_key_path,
    @ssh_password_encrypted = gateway_ssh_password
FROM tLSvr WITH(NOLOCK)
WHERE LSSN = @lssn

IF @ssh_host IS NULL OR @ssh_host = ''
BEGIN
    -- 🔴 [로깅 포인트 #6.4] SSH 정보 없음
    INSERT INTO tLogSP (lsName, lsParam, lsRstVal)
    VALUES ('pApiRemoteServerSSHTestbyAK', 
            'ssh_config_missing_lssn:' + CAST(@lssn AS VARCHAR), 
            '422 - SSH configuration incomplete')
    
    SELECT 422 AS RstVal, 
           'SSH 호스트 정보가 설정되지 않았습니다' AS RstMsg
    RETURN
END

-- 비밀번호 복호화 (필요시)
IF @ssh_password_encrypted IS NOT NULL
BEGIN
    EXEC @err = sp_executesql 
        N'SELECT @pwd = dbo.lwDecryptPassword(@enc)',
        N'@enc VARBINARY(8000), @pwd VARCHAR(500) OUTPUT',
        @ssh_password_encrypted, @ssh_password OUTPUT
END
```

##### 5️⃣ 테스트 결과 업데이트 (Test Result Update & Logging)
```sql
-- 테스트 결과 저장 (tLSvr 테이블 업데이트)
UPDATE tLSvr
SET 
    gateway_ssh_last_test_result = @test_result,      -- 'success' 또는 'failure'
    gateway_ssh_last_test_time = GETUTCDATE(),        -- 테스트 실행 시간
    gateway_ssh_response_time_ms = @response_time_ms, -- 응답 시간 (ms)
    gateway_ssh_auth_method = @auth_method,           -- 'key' 또는 'password'
    gateway_ssh_last_test_message = @test_message,    -- 에러 메시지 등
    LSChkdt = GETUTCDATE()                            -- 📍 #6.5-LSChkdt: 최종 체크 완료 날짜
WHERE LSSN = @lssn

-- 🔴 [로깅 포인트 #6.5] SSH 테스트 완료
INSERT INTO tLogSP (lsName, lsParam, lsRstVal)
VALUES ('pApiRemoteServerSSHTestbyAK', 
        'test_result:' + @test_result + '|response_time_ms:' + CAST(@response_time_ms AS VARCHAR),
        '200 - SSH test completed')

-- 응답 반환
BEGIN TRAN
SELECT 200 AS RstVal,
       'SSH 접속 테스트 ' + CASE 
           WHEN @test_result = 'success' THEN '성공'
           ELSE '실패'
       END AS RstMsg,
       LSSN = @lssn,
       hostname = LSHostname,
       ssh_host = @ssh_host,
       ssh_port = @ssh_port,
       ssh_user = @ssh_user,
       ssh_auth_method = @auth_method,
       test_result = @test_result,
       test_message = @test_message,
       response_time_ms = @response_time_ms,
       last_test_time = CONVERT(VARCHAR, GETUTCDATE(), 'yyyy-mm-dd hh:mi:ss')
FROM tLSvr
WHERE LSSN = @lssn

COMMIT TRAN
```

### tLSvr 테이블 스키마 확장

**추가 컬럼** (기존 `gateway_ssh_*` 컬럼에 다음 추가):

```sql
ALTER TABLE tLSvr ADD
    gateway_ssh_last_test_result VARCHAR(20),        -- 'success' 또는 'failure'
    gateway_ssh_last_test_time DATETIME NULL,        -- 마지막 테스트 시간
    gateway_ssh_response_time_ms INT NULL,           -- 응답 시간 (밀리초)
    gateway_ssh_auth_method VARCHAR(20),             -- 'key' 또는 'password'
    gateway_ssh_last_test_message VARCHAR(500)       -- 테스트 결과 메시지/에러
```

**인덱스**:

```sql
-- 테스트 결과 조회 최적화
CREATE INDEX IX_tLSvr_SSHTestResult 
ON tLSvr(gateway_lssn, gateway_ssh_last_test_result, LSChkdt DESC)
WHERE is_gateway = 0 AND gateway_lssn IS NOT NULL
```

---

## 실행 흐름

### 시나리오 1: Gateway Agent의 자동 테스트

```
1. giipAgent3.sh (Gateway 모드)
   │
   ├─ get_gateway_servers()
   │  └─ API 호출: GatewayRemoteServerListForAgent
   │     결과: 리모트 서버 목록 (71221, 71222, 71223 등)
   │
   ├─ FOR each remote_server in list
   │  │
   │  ├─ SSH 테스트 수행
   │  │  ├─ SSH key 시도
   │  │  └─ 또는 SSH password 시도
   │  │
   │  └─ API 호출: RemoteServerSSHTest
   │     REQUEST: {
   │       "lssn": 71221,
   │       "gateway_lssn": 71174,
   │       "test_type": "ssh"
   │     }
   │
   │     RESPONSE: {
   │       "RstVal": 200,
   │       "test_result": "success",
   │       "response_time_ms": 245
   │     }
   │
   └─ KVS 로깅
      kFactor: giipagent
      key: lssn_71174
      data: {
        "event": "remote_server_ssh_test",
        "remote_lssn": 71221,
        "test_result": "success",
        "response_time_ms": 245
      }
```

### 시나리오 2: 웹 UI에서 수동 테스트

```
1. 사용자가 lsvrdetail 페이지에서 "연결 테스트" 버튼 클릭
   │
   ├─ Frontend: RemoteServerTestButton 컴포넌트
   │  └─ fetchAzureCommand('RemoteServerSSHTest', {
   │      jsondata: {
   │        "lssn": 71221,
   │        "gateway_lssn": 71174,
   │        "test_type": "ssh"
   │      }
   │    })
   │
   ├─ Azure Function (giipApiSk2/run.ps1)
   │  └─ SP 호출: pApiRemoteServerSSHTestbyAK
   │
   ├─ SP 실행
   │  ├─ 인증 확인 ✅
   │  ├─ 리모트 서버 확인 ✅
   │  ├─ Gateway 서버 확인 ✅
   │  ├─ SSH 정보 조회 ✅
   │  ├─ tLSvr 테이블 업데이트 ✅
   │  └─ 로깅 ✅
   │
   ├─ Response 반환
   │  └─ {
   │      "RstVal": 200,
   │      "test_result": "success",
   │      "response_time_ms": 245,
   │      "last_test_time": "2025-11-22 14:30:00"
   │    }
   │
   └─ Frontend 표시
      UI 업데이트: "✅ 성공 (245ms)"
      마지막 테스트: 2025-11-22 14:30:00
```

---

## 에러 처리

### 에러 시나리오별 응답

#### 1. SSH 연결 타임아웃 (Connection Timeout)
```json
{
  "RstVal": 422,
  "RstMsg": "SSH 접속 테스트 실패: Connection timeout",
  "data": [
    {
      "lssn": 71221,
      "test_result": "failure",
      "test_message": "SSH connection timeout after 10 seconds",
      "response_time_ms": 10000
    }
  ]
}
```

**원인**: 
- 방화벽이 SSH 포트 차단
- 리모트 서버가 오프라인
- 네트워크 불안정

**대응**:
- 방화벽 규칙 확인
- 리모트 서버 상태 확인
- SSH 포트 설정 재검토

#### 2. SSH 인증 실패 (Authentication Failure)
```json
{
  "RstVal": 422,
  "RstMsg": "SSH 접속 테스트 실패: Permission denied",
  "data": [
    {
      "lssn": 71221,
      "test_result": "failure",
      "test_message": "Permission denied (publickey,password)",
      "response_time_ms": 500
    }
  ]
}
```

**원인**:
- SSH 사용자명 오류
- SSH 키 파일 손상 또는 경로 오류
- SSH 비밀번호 오류

**대응**:
- 리모트 서버에서 SSH 사용자 확인
- SSH 키 파일 재등록
- SSH 비밀번호 확인

#### 3. SSH 호스트 접근 불가 (Host Unreachable)
```json
{
  "RstVal": 422,
  "RstMsg": "SSH 접속 테스트 실패: Host is unreachable",
  "data": [
    {
      "lssn": 71221,
      "test_result": "failure",
      "test_message": "No route to host",
      "response_time_ms": 5000
    }
  ]
}
```

**원인**:
- SSH 호스트 IP/도메인 오류
- 네트워크 경로 단절
- 리모트 서버 네트워크 설정 오류

**대응**:
- SSH 호스트 정보 재확인
- `ping`, `traceroute` 등으로 네트워크 진단
- Gateway 서버에서 리모트 서버로 직접 ping 테스트

---

## KVS 로깅

### 로깅 포인트

#### 📍 #6.1 인증 실패
```
[RemoteServerSSHTest] 🔴 [6.1] 인증 실패: sk_mismatch
- lssn: (없음, 인증 전)
- timestamp: 2025-11-22 14:30:00
- RstVal: 401
```

#### 📍 #6.2 리모트 서버 없음
```
[RemoteServerSSHTest] 🔴 [6.2] 리모트 서버 없음: lssn=71221
- gateway_lssn: 71174
- reason: is_gateway != 0 OR gateway_lssn mismatch
- timestamp: 2025-11-22 14:30:00
- RstVal: 404
```

#### 📍 #6.3 Gateway 서버 없음
```
[RemoteServerSSHTest] 🔴 [6.3] Gateway 서버 없음: gateway_lssn=71174
- lssn: 71221
- reason: is_gateway != 1
- timestamp: 2025-11-22 14:30:00
- RstVal: 404
```

#### 📍 #6.4 SSH 설정 불완전
```
[RemoteServerSSHTest] 🔴 [6.4] SSH 설정 불완전: lssn=71221
- ssh_host: NULL or empty
- timestamp: 2025-11-22 14:30:00
- RstVal: 422
```

#### 📍 #6.5 SSH 테스트 완료
```
[RemoteServerSSHTest] 🟢 [6.5] SSH 테스트 완료: lssn=71221
- test_result: success
- response_time_ms: 245
- auth_method: key
- timestamp: 2025-11-22 14:30:00
- RstVal: 200
```

### KVS 저장 형식

**Key**: `lssn_{lssn}`  
**Factor**: `giipagent`

**Value**:
```json
{
  "event": "remote_server_ssh_test",
  "gateway_lssn": 71174,
  "lssn": 71221,
  "hostname": "server1",
  "test_type": "ssh",
  "test_result": "success",
  "ssh_host": "192.168.1.21",
  "ssh_port": 22,
  "ssh_user": "root",
  "ssh_auth_method": "key",
  "response_time_ms": 245,
  "test_message": "SSH connection successful",
  "timestamp": "2025-11-22 14:30:00.123Z"
}
```

---

## 🔄 향후 확장 계획

### Phase 2: 추가 테스트 유형
```
- test_type: "port" → SSH 포트만 확인 (빠른 확인)
- test_type: "command" → 원격 명령 실행 (OS 정보 수집)
- test_type: "rsync" → rsync 포트 테스트 (파일 전송 확인)
```

### Phase 3: 자동 복구
```
- SSH 연결 실패 시 자동으로 설정 재검토
- SSH 키 재생성 제안
- Gateway 서버 헬스 체크
```

### Phase 4: 모니터링 대시보드
```
- 리모트 서버별 연결 상태 (성공/실패)
- 평균 응답 시간 추이
- 최근 테스트 이력
- 문제 서버 자동 알림
```

---

## 참고 자료

- **리모트 서버 정의**: [GIIPAGENT3_SPECIFICATION.md - 리모트 서버](#)
- **Gateway 서버 설정**: [lsvrdetail.ko.md - Gateway 설정](#)
- **SSH 인증 구현**: [SSH_PASSWORD_AUTH_IMPLEMENTATION.md](#)
- **API 목록**: [API_List.md](#)

---

**✅ 이 사양에 따라 pApiRemoteServerSSHTestbyAK SP를 구현하면, 리모트 서버의 연결 상태를 실시간으로 관리할 수 있습니다.**
