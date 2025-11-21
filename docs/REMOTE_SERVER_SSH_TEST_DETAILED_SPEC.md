# 리모트 서버 SSH 접속 테스트 - 상세 사양

> **문서**: API 요청/응답, DB 업데이트, SP 코드, 에러 처리 상세

---

## API 사양 상세

### RemoteServerSSHTest API

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
      "ssh_auth_method": "key",
      "test_result": "success",
      "test_message": "SSH connection successful",
      "response_time_ms": 245,
      "last_test_time": "2025-11-22 14:30:00",
      "os_info": "Ubuntu 20.04",
      "kernel_version": "5.4.0-42-generic"
    }
  ]
}
```

**실패 사례**:

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
| 200 | ✅ 성공 | SSH 접속 성공 | DB 업데이트 완료 |
| 401 | 🔓 인증 실패 | Secret Key 불일치 | SK 확인 |
| 404 | 🔍 리모트 서버 없음 | LSSN이 DB에 없음 | 리모트 서버 등록 확인 |
| 422 | ❌ 접속 실패 | SSH 연결 타임아웃/거부 | 방화벽, 네트워크, SSH 설정 확인 |
| 500 | ⚠️ 서버 에러 | Azure Function 오류 | 로그 확인 |

---

## DB 업데이트 메커니즘

### Stored Procedure: pApiRemoteServerSSHTestbyAK

**파일**: `giipdb/SP/pApiRemoteServerSSHTestbyAK.sql`

```sql
CREATE PROCEDURE pApiRemoteServerSSHTestbyAK
    @sk VARCHAR(200),                    -- Secret Key
    @lssn INT,                          -- 리모트 서버 LSSN
    @gateway_lssn INT,                  -- Gateway 서버 LSSN
    @test_type VARCHAR(50) = 'ssh',    -- 테스트 유형
    @test_timeout_sec INT = 10         -- 타임아웃 (초)
AS
BEGIN
    -- 1️⃣ 인증 확인
    DECLARE @csn INT
    SELECT @csn = csn FROM tLSvrAuth WITH(NOLOCK)
    WHERE sk = @sk AND sk_status = 1
    
    IF @csn IS NULL
    BEGIN
        INSERT INTO tLogSP (lsName, lsParam, lsRstVal) 
        VALUES ('pApiRemoteServerSSHTestbyAK', 'auth_failed', '401')
        SELECT 401 AS RstVal, 'Secret Key 불일치' AS RstMsg
        RETURN
    END
    
    -- 2️⃣ 리모트 서버 확인
    IF NOT EXISTS(SELECT 1 FROM tLSvr WHERE LSSN = @lssn AND is_gateway = 0 AND gateway_lssn = @gateway_lssn)
    BEGIN
        INSERT INTO tLogSP (lsName, lsParam, lsRstVal)
        VALUES ('pApiRemoteServerSSHTestbyAK', 'server_not_found', '404')
        SELECT 404 AS RstVal, 'LSSN ' + CAST(@lssn AS VARCHAR) + '을 찾을 수 없습니다' AS RstMsg
        RETURN
    END
    
    -- 3️⃣ Gateway 서버 확인
    IF NOT EXISTS(SELECT 1 FROM tLSvr WHERE LSSN = @gateway_lssn AND is_gateway = 1)
    BEGIN
        INSERT INTO tLogSP (lsName, lsParam, lsRstVal)
        VALUES ('pApiRemoteServerSSHTestbyAK', 'gateway_not_found', '404')
        SELECT 404 AS RstVal, 'Gateway 서버를 찾을 수 없습니다' AS RstMsg
        RETURN
    END
    
    -- 4️⃣ SSH 정보 조회
    DECLARE @ssh_host VARCHAR(100), @ssh_port INT, @ssh_user VARCHAR(50)
    SELECT @ssh_host = gateway_ssh_host, @ssh_port = ISNULL(gateway_ssh_port, 22), @ssh_user = ISNULL(gateway_ssh_user, 'root')
    FROM tLSvr WHERE LSSN = @lssn
    
    IF @ssh_host IS NULL
    BEGIN
        INSERT INTO tLogSP (lsName, lsParam, lsRstVal)
        VALUES ('pApiRemoteServerSSHTestbyAK', 'ssh_config_missing', '422')
        SELECT 422 AS RstVal, 'SSH 호스트 정보가 설정되지 않았습니다' AS RstMsg
        RETURN
    END
    
    -- 5️⃣ 테스트 결과 업데이트 (테스트는 Azure Function에서 수행)
    DECLARE @test_result VARCHAR(20) = 'success'  -- 실제로는 Azure Function에서 전달받음
    DECLARE @response_time_ms INT = 245
    DECLARE @auth_method VARCHAR(20) = 'key'
    DECLARE @test_message VARCHAR(500) = 'SSH connection successful'
    
    UPDATE tLSvr
    SET 
        gateway_ssh_last_test_result = @test_result,
        gateway_ssh_last_test_time = GETUTCDATE(),
        gateway_ssh_response_time_ms = @response_time_ms,
        gateway_ssh_auth_method = @auth_method,
        gateway_ssh_last_test_message = @test_message,
        LSChkdt = GETUTCDATE()  -- 📍 최종 체크 완료 날짜
    WHERE LSSN = @lssn
    
    INSERT INTO tLogSP (lsName, lsParam, lsRstVal)
    VALUES ('pApiRemoteServerSSHTestbyAK', 'test_result:' + @test_result, '200')
    
    SELECT 200 AS RstVal, 'SSH 접속 테스트 완료' AS RstMsg
END
```

### tLSvr 테이블 스키마 확장

```sql
ALTER TABLE tLSvr ADD
    gateway_ssh_last_test_result VARCHAR(20),
    gateway_ssh_last_test_time DATETIME NULL,
    gateway_ssh_response_time_ms INT NULL,
    gateway_ssh_auth_method VARCHAR(20),
    gateway_ssh_last_test_message VARCHAR(500);

CREATE INDEX IX_tLSvr_SSHTestResult 
ON tLSvr(gateway_lssn, gateway_ssh_last_test_result, LSChkdt DESC)
WHERE is_gateway = 0 AND gateway_lssn IS NOT NULL;
```

---

## 에러 처리

### 에러 시나리오

#### 1. SSH 연결 타임아웃
```json
{
  "RstVal": 422,
  "RstMsg": "SSH 접속 테스트 실패: Connection timeout",
  "data": [{
    "lssn": 71221,
    "test_result": "failure",
    "test_message": "Connection timeout after 10 seconds",
    "response_time_ms": 10000
  }]
}
```

**원인**: 방화벽, 리모트 서버 오프라인, 네트워크 불안정

#### 2. SSH 인증 실패
```json
{
  "RstVal": 422,
  "RstMsg": "SSH 접속 테스트 실패: Permission denied",
  "data": [{
    "lssn": 71221,
    "test_result": "failure",
    "test_message": "Permission denied (publickey,password)",
    "response_time_ms": 500
  }]
}
```

**원인**: SSH 사용자명/키/비밀번호 오류

#### 3. SSH 호스트 접근 불가
```json
{
  "RstVal": 422,
  "RstMsg": "SSH 접속 테스트 실패: Host is unreachable",
  "data": [{
    "lssn": 71221,
    "test_result": "failure",
    "test_message": "No route to host",
    "response_time_ms": 5000
  }]
}
```

**원인**: SSH 호스트 IP/도메인 오류, 네트워크 경로 단절

---

## KVS 로깅 상세

### 로깅 포인트

#### #6.1 인증 실패
```
[RemoteServerSSHTest] 🔴 [6.1] 인증 실패: sk_mismatch
- timestamp: 2025-11-22 14:30:00
- RstVal: 401
```

#### #6.2 리모트 서버 없음
```
[RemoteServerSSHTest] 🔴 [6.2] 리모트 서버 없음: lssn=71221
- gateway_lssn: 71174
- RstVal: 404
```

#### #6.3 Gateway 서버 없음
```
[RemoteServerSSHTest] 🔴 [6.3] Gateway 서버 없음: gateway_lssn=71174
- lssn: 71221
- RstVal: 404
```

#### #6.4 SSH 설정 불완전
```
[RemoteServerSSHTest] 🔴 [6.4] SSH 설정 불완전: lssn=71221
- ssh_host: NULL or empty
- RstVal: 422
```

#### #6.5 SSH 테스트 완료
```
[RemoteServerSSHTest] 🟢 [6.5] SSH 테스트 완료: lssn=71221
- test_result: success
- response_time_ms: 245
- auth_method: key
- RstVal: 200
```

### KVS 저장 형식

**Key**: `lssn_{lssn}`  
**Factor**: `giipagent`

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

## 실행 흐름 상세

### 시나리오 1: Gateway Agent의 자동 테스트

```
1. giipAgent3.sh (Gateway 모드)
   └─ get_gateway_servers()
      └─ API: GatewayRemoteServerListForAgent
         결과: 리모트 서버 목록 [71221, 71222, 71223]
         
2. FOR each remote_server in list
   └─ SSH 테스트 수행
      ├─ SSH key 시도
      └─ OR SSH password 시도
      
3. RemoteServerSSHTest API 호출
   REQUEST: {
     "lssn": 71221,
     "gateway_lssn": 71174,
     "test_type": "ssh"
   }
   
   RESPONSE: {
     "RstVal": 200,
     "test_result": "success",
     "response_time_ms": 245
   }
   
4. KVS 로깅
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
1. 사용자: lsvrdetail 페이지 → "연결 테스트" 버튼 클릭
   
2. Frontend: RemoteServerTestButton
   └─ fetchAzureCommand('RemoteServerSSHTest', {
        jsondata: {
          "lssn": 71221,
          "gateway_lssn": 71174,
          "test_type": "ssh"
        }
      })
   
3. Azure Function (giipApiSk2/run.ps1)
   └─ SP 호출: pApiRemoteServerSSHTestbyAK
   
4. SP 실행
   ├─ 인증 확인 ✅
   ├─ 리모트 서버 확인 ✅
   ├─ Gateway 서버 확인 ✅
   ├─ SSH 정보 조회 ✅
   ├─ tLSvr 테이블 업데이트 ✅
   └─ 로깅 ✅
   
5. Response
   {
     "RstVal": 200,
     "test_result": "success",
     "response_time_ms": 245,
     "last_test_time": "2025-11-22 14:30:00"
   }
   
6. Frontend 화면 업데이트
   UI: "✅ 성공 (245ms)"
   마지막 테스트: 2025-11-22 14:30:00
```

---

## 향후 확장 계획

### Phase 2: 추가 테스트 유형
- `test_type: "port"` → SSH 포트만 확인 (빠른 확인)
- `test_type: "command"` → 원격 명령 실행 (OS 정보 수집)
- `test_type: "rsync"` → rsync 포트 테스트 (파일 전송 확인)

### Phase 3: 자동 복구
- SSH 연결 실패 시 자동으로 설정 재검토
- SSH 키 재생성 제안
- Gateway 서버 헬스 체크

### Phase 4: 모니터링 대시보드
- 리모트 서버별 연결 상태 (성공/실패)
- 평균 응답 시간 추이
- 최근 테스트 이력
- 문제 서버 자동 알림
