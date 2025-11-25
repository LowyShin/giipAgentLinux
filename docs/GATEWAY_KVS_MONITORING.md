# Gateway 모니터링 - KVS 조회 가이드

## 개요
Gateway 서버가 KVS에 저장하는 상태 정보를 조회하는 방법입니다.

## KVS 키 구조

### 1. Gateway 시작 상태
- **키**: `gateway_{lssn}_startup`
- **타입**: `gateway_status`
- **데이터**:
  ```json
  {
    "status": "started",
    "version": "1.80",
    "lssn": 71240,
    "timestamp": "2025-11-04 12:34:56",
    "mode": "gateway"
  }
  ```

### 2. Gateway 동기화 상태
- **키**: `gateway_{lssn}_sync`
- **타입**: `gateway_status`
- **데이터**:
  ```json
  {
    "status": "synced",
    "server_count": 3,
    "timestamp": "2025-11-04 12:35:00"
  }
  ```

### 3. Heartbeat 트리거
- **키**: `gateway_{lssn}_heartbeat_trigger`
- **타입**: `gateway_heartbeat`
- **데이터**:
  ```json
  {
    "status": "triggered",
    "interval": 300,
    "timestamp": "2025-11-04 12:40:00"
  }
  ```

### 4. Heartbeat 실행 상태
- **키**: `gateway_{lssn}_heartbeat_status`
- **타입**: `gateway_heartbeat`
- **데이터**:
  ```json
  {
    "status": "running",
    "pid": 12345,
    "timestamp": "2025-11-04 12:40:01"
  }
  ```

### 5. 서버별 체크 결과
- **키**: `gateway_{lssn}_server_{remote_lssn}`
- **타입**: `gateway_heartbeat`
- **성공 데이터**:
  ```json
  {
    "lssn": 71221,
    "hostname": "p-cnsldb01m",
    "status": "success",
    "timestamp": "2025-11-04 12:40:10"
  }
  ```
- **실패 데이터**:
  ```json
  {
    "lssn": 71221,
    "hostname": "p-cnsldb01m",
    "status": "failed",
    "error": "SSH connection failed",
    "timestamp": "2025-11-04 12:40:10"
  }
  ```

### 6. Heartbeat 요약
- **키**: `gateway_{lssn}_summary`
- **타입**: `gateway_heartbeat`
- **데이터**:
  ```json
  {
    "status": "completed",
    "total": 3,
    "success": 2,
    "failed": 1,
    "timestamp": "2025-11-04 12:40:30"
  }
  ```

### 7. 에러 상태
- **키**: `gateway_{lssn}_error` 또는 `gateway_{lssn}_heartbeat_error`
- **타입**: `gateway_status` 또는 `gateway_heartbeat`
- **데이터**:
  ```json
  {
    "status": "error",
    "error": "Failed to setup sshpass",
    "timestamp": "2025-11-04 12:34:56"
  }
  ```

## 스크립트로 KVS 조회

⚠️ **KVS 조회는 반드시 스크립트를 사용해야 합니다 (SQL 직접 조회 금지)**

### Gateway 시작 상태 확인
**스크립트**: [`giipdb/mgmt/query-gateway-startup-status.ps1`](../../giipdb/mgmt/query-gateway-startup-status.ps1)

```powershell
# 기본 조회 (LSSN 71240)
pwsh .\mgmt\query-gateway-startup-status.ps1

# 특정 LSSN 조회
pwsh .\mgmt\query-gateway-startup-status.ps1 -Lssn 71174

# CSV로 내보내기
pwsh .\mgmt\query-gateway-startup-status.ps1 -Lssn 71240 -ExportCsv
```

### 최근 Heartbeat 결과
**스크립트**: [`giipdb/mgmt/query-gateway-heartbeat-results.ps1`](../../giipdb/mgmt/query-gateway-heartbeat-results.ps1)

```powershell
# 기본 조회 (최근 10개)
pwsh .\mgmt\query-gateway-heartbeat-results.ps1

# 특정 LSSN 조회
pwsh .\mgmt\query-gateway-heartbeat-results.ps1 -Lssn 71174

# 요약 모드 (kFactor별 집계)
pwsh .\mgmt\query-gateway-heartbeat-results.ps1 -Lssn 71240 -Summary

# 특정 기간만 조회 (최근 2시간)
pwsh .\mgmt\query-gateway-heartbeat-results.ps1 -Lssn 71240 -Hours 2

# CSV로 내보내기
pwsh .\mgmt\query-gateway-heartbeat-results.ps1 -Lssn 71240 -ExportCsv
```

### 특정 서버 체크 이력
**스크립트**: [`giipdb/mgmt/query-gateway-server-check-history.ps1`](../../giipdb/mgmt/query-gateway-server-check-history.ps1)

```powershell
# 기본 조회 (Gateway 71240, 서버 71221의 체크 이력)
pwsh .\mgmt\query-gateway-server-check-history.ps1 -GatewayLssn 71240 -ServerLssn 71221

# 더 많은 레코드 조회 (최근 50개)
pwsh .\mgmt\query-gateway-server-check-history.ps1 -GatewayLssn 71240 -ServerLssn 71221 -Top 50

# 성공한 체크만 조회
pwsh .\mgmt\query-gateway-server-check-history.ps1 -GatewayLssn 71240 -ServerLssn 71221 -StatusFilter "success"

# 실패한 체크만 조회
pwsh .\mgmt\query-gateway-server-check-history.ps1 -GatewayLssn 71240 -ServerLssn 71221 -StatusFilter "failed"

# CSV로 내보내기
pwsh .\mgmt\query-gateway-server-check-history.ps1 -GatewayLssn 71240 -ServerLssn 71221 -ExportCsv
```

### 모든 Gateway 상태 요약
**스크립트**: [`giipdb/mgmt/query-gateway-status-summary.ps1`](../../giipdb/mgmt/query-gateway-status-summary.ps1)

```powershell
# 기본 조회 (LSSN 71240)
pwsh .\mgmt\query-gateway-status-summary.ps1

# 특정 LSSN 조회
pwsh .\mgmt\query-gateway-status-summary.ps1 -Lssn 71174

# 요약 모드 (kType별 집계)
pwsh .\mgmt\query-gateway-status-summary.ps1 -Lssn 71240 -Summary

# 특정 기간만 조회 (최근 2시간)
pwsh .\mgmt\query-gateway-status-summary.ps1 -Lssn 71240 -Hours 2

# 더 많은 레코드 조회 (최근 100개)
pwsh .\mgmt\query-gateway-status-summary.ps1 -Lssn 71240 -Top 100

# CSV로 내보내기
pwsh .\mgmt\query-gateway-status-summary.ps1 -Lssn 71240 -ExportCsv
```

## API로 KVS 조회

### PowerShell 예제
```powershell
$apiUrl = "https://giipfaw.azurewebsites.net/api/giipApiSk2?code=YOUR_CODE"
$body = @{
    text = "KVSGet kType kKey"
    token = "YOUR_SK"
    jsondata = @{
        kType = "gateway_heartbeat"
        kKey = "gateway_71240_summary"
    } | ConvertTo-Json
} | ConvertTo-Json

$response = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $body -ContentType "application/json"
$response | ConvertTo-Json -Depth 10
```

### curl 예제
```bash
curl -X POST "https://giipfaw.azurewebsites.net/api/giipApiSk2?code=YOUR_CODE" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "KVSGet kType kKey",
    "token": "YOUR_SK",
    "jsondata": {
      "kType": "gateway_heartbeat",
      "kKey": "gateway_71240_summary"
    }
  }'
```

## Web UI 통합 (예정)

### lsvrdetail 페이지에 추가할 기능

1. **Gateway 상태 섹션**
   - 마지막 시작 시간
   - 관리 서버 수
   - 마지막 동기화 시간

2. **Heartbeat 상태**
   - 마지막 실행 시간
   - 실행 간격
   - 실행 중 여부 (PID)

3. **서버별 체크 결과**
   - 각 서버의 마지막 체크 시간
   - 성공/실패 상태
   - 에러 메시지 (실패 시)

4. **통계**
   - 전체 서버 수
   - 성공한 서버 수
   - 실패한 서버 수
   - 성공률

## 디버깅 체크리스트

### 1. Gateway가 시작되었는지 확인
**스크립트**: `query-gateway-startup-status.ps1`

```powershell
pwsh .\mgmt\query-gateway-startup-status.ps1 -Lssn 71240
```

- ❌ 결과 없음: Gateway가 시작되지 않음
- ✅ 최근 데이터: Gateway 정상 시작

### 2. Heartbeat가 트리거되었는지 확인
**스크립트**: `query-gateway-heartbeat-results.ps1`

```powershell
pwsh .\mgmt\query-gateway-heartbeat-results.ps1 -Lssn 71240 -Top 5
```

- ❌ 결과 없음: Heartbeat 간격이 아직 도달하지 않음 (5분 대기)
- ✅ 최근 데이터: Heartbeat 트리거됨

### 3. Heartbeat가 실행되었는지 확인
**스크립트**: `query-gateway-heartbeat-results.ps1`

```powershell
# kKey가 'gateway_71240_heartbeat_status'인 레코드만 조회하려면
# query-gateway-status-summary.ps1 사용 후 필터링하거나
# 직접 DB에서 조회할 수 있습니다
pwsh .\mgmt\query-gateway-heartbeat-results.ps1 -Lssn 71240 -Top 10
```

- ❌ 결과 없음: Heartbeat 스크립트 없음 또는 실행 실패
- ✅ 최근 데이터: Heartbeat 실행 중

### 4. 서버 체크 결과 확인
**스크립트**: `query-gateway-server-check-history.ps1`

```powershell
# 특정 서버의 체크 이력 조회
pwsh .\mgmt\query-gateway-server-check-history.ps1 -GatewayLssn 71240 -ServerLssn 71221

# 모든 서버의 최근 결과를 요약하려면
pwsh .\mgmt\query-gateway-heartbeat-results.ps1 -Lssn 71240 -Summary
```

- ❌ 결과 없음: 서버 목록이 비어있거나 SSH 연결 모두 실패
- ✅ success 데이터: 정상 체크 완료
- ⚠️ failed 데이터: SSH 연결 실패 (에러 메시지 확인)

### 5. 에러 확인
**스크립트**: [`giipdb/mgmt/query-gateway-error-status.ps1`](../../giipdb/mgmt/query-gateway-error-status.ps1)

```powershell
# 최근 24시간 에러 확인
pwsh .\mgmt\query-gateway-error-status.ps1 -Lssn 71240

# 최근 6시간 에러만 확인
pwsh .\mgmt\query-gateway-error-status.ps1 -Lssn 71240 -Hours 6

# 에러 타입별 집계
pwsh .\mgmt\query-gateway-error-status.ps1 -Lssn 71240 -Summary
```

## 모니터링 대시보드 (향후 구현)

```
┌─────────────────────────────────────────────────────────────┐
│ Gateway 서버: p-gw01 (LSSN: 71240)                          │
├─────────────────────────────────────────────────────────────┤
│ 상태: 🟢 실행 중                                              │
│ 시작 시간: 2025-11-04 12:34:56                              │
│ 버전: 1.80                                                  │
│ 관리 서버: 3개                                               │
├─────────────────────────────────────────────────────────────┤
│ Heartbeat                                                   │
│ 상태: 🟢 정상                                                │
│ 마지막 실행: 2025-11-04 12:40:01                            │
│ 다음 실행: 2분 후                                            │
│ 성공률: 66.7% (2/3)                                         │
├─────────────────────────────────────────────────────────────┤
│ 관리 중인 서버                                               │
│                                                             │
│ ✅ p-cnsldb01m (71221) - 5분 전                             │
│ ✅ p-webserver (71222) - 5분 전                             │
│ ❌ p-dbserver (71223) - SSH 연결 실패                       │
└─────────────────────────────────────────────────────────────┘
```

## 참고 문서
- [Gateway 통합 가이드](./GATEWAY_UNIFIED_GUIDE.md)
- [Heartbeat 설정 가이드](./GATEWAY_HEARTBEAT_GUIDE.md)
