# 리모트 서버 SSH 접속 테스트 - 상세 사양

> **문서**: API 요청/응답, DB 업데이트, SP 코드, 에러 처리 상세

---

## 📋 전제 조건

**이 문서를 읽기 전에 반드시 확인하세요:**

1. **SP 배포 필수**: [`giipdb/docs/SP_DEPLOYMENT_GUIDE.md`](../../giipdb/docs/SP_DEPLOYMENT_GUIDE.md)
   - 배포 방법 A/B/C 중 선택하여 `pApiRemoteServerSSHTestbyAK` 배포
   - 배포 확인: `SELECT * FROM sys.procedures WHERE name = 'pApiRemoteServerSSHTestbyAK'`

2. **SP 파일 확인**: [`giipdb/SP/pApiRemoteServerSSHTestbyAK.sql`](../../giipdb/SP/pApiRemoteServerSSHTestbyAK.sql)

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

**파일**: [`giipdb/SP/pApiRemoteServerSSHTestbyAK.sql`](../../giipdb/SP/pApiRemoteServerSSHTestbyAK.sql)

**용도**: RemoteServerSSHTest API 호출 시 LSChkdt 업데이트

**주요 기능**:
1. Secret Key 인증 확인
2. 리모트 서버 존재 및 소유권 확인 (gateway_lssn 일치)
3. Gateway 서버 존재 확인
4. SSH 설정 유효성 확인
5. **LSChkdt = GETUTCDATE()** 업데이트 (최종 체크 완료)

**SP 코드**는 아래 파일에서 확인:

📄 [`giipdb/SP/pApiRemoteServerSSHTestbyAK.sql`](../../giipdb/SP/pApiRemoteServerSSHTestbyAK.sql)

**SP 실행 순서**:
1. Secret Key 인증
2. 리모트 서버 존재/소유권 확인
3. Gateway 서버 존재 확인
4. SSH 설정 확인
5. **LSChkdt = GETUTCDATE()** 업데이트

---

### tLSvr 테이블 스키마

LSChkdt 업데이트를 위해 다음 필드가 필요합니다:

```sql
ALTER TABLE tLSvr ADD
    gateway_ssh_last_test_result VARCHAR(20) NULL,     -- 'success' or 'failure'
    gateway_ssh_last_test_time DATETIME NULL,          -- 테스트 실행 시각
    gateway_ssh_response_time_ms INT NULL,             -- 응답 시간
    gateway_ssh_auth_method VARCHAR(20) NULL,          -- 'key' or 'password'
    gateway_ssh_last_test_message VARCHAR(500) NULL    -- 테스트 메시지
GO
```

**주의**: `LSChkdt` 필드는 이미 존재하며, **가장 최종 체크 완료 날짜**를 나타냅니다.

---

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
