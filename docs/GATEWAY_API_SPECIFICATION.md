# Gateway API 명세서

## 개요

Gateway 서버가 사용하는 API 엔드포인트 및 호출 방법을 정의합니다.

- **엔드포인트**: `${apiaddrv2}?code=${apiaddrcode}`
- **메서드**: POST
- **Content-Type**: `application/x-www-form-urlencoded`
- **인증**: Secret Key (SK) 기반

---

## 1. GatewayManagedDatabaseList - 관리 DB 목록 조회

### 용도
Gateway 서버가 관리하는 데이터베이스 목록을 조회합니다.

### 요청

**Parameters:**
```bash
text=GatewayManagedDatabaseList lssn
token=${sk}
jsondata={"lssn":${lssn}}
```

**Shell 예시:**
```bash
wget -O response.json --quiet \
    --post-data="text=GatewayManagedDatabaseList lssn&token=${sk}&jsondata={\"lssn\":${lssn}}" \
    --header="Content-Type: application/x-www-form-urlencoded" \
    "${apiaddrv2}?code=${apiaddrcode}" \
    --no-check-certificate
```

### 응답

**성공 시 (200 OK):**
```json
{
  "status": "success",
  "data": [
    {
      "mdb_id": 4,
      "mdb_name": "p-cnsldb01m",
      "mdb_type": "MySQL",
      "mdb_host": "p-cnsldb01m",
      "mdb_port": "3306",
      "mdb_user": "admin",
      "mdb_password": "********",
      "mdb_database": "counseling",
      "last_check_dt": "2025-11-13T09:28:26",
      "health_status": "healthy"
    }
  ]
}
```

**실패 시:**
```json
{
  "status": "error",
  "message": "Invalid SK or LSSN not found"
}
```

### 응답 필드 설명

| 필드 | 타입 | 설명 |
|------|------|------|
| `mdb_id` | int | Managed Database ID (PK) |
| `mdb_name` | string | 데이터베이스 식별 이름 |
| `mdb_type` | string | DB 타입 (MySQL, PostgreSQL, MSSQL, Redis, MongoDB) |
| `mdb_host` | string | DB 호스트명 또는 IP |
| `mdb_port` | string | DB 포트 번호 |
| `mdb_user` | string | DB 접속 계정 |
| `mdb_password` | string | DB 접속 암호 (암호화됨) |
| `mdb_database` | string | 연결할 데이터베이스명 |
| `last_check_dt` | datetime | 마지막 체크 시각 |
| `health_status` | string | 상태 (healthy, error, warning) |

### 사용 예시

**check_managed_databases.sh:**
```bash
check_managed_databases() {
    local temp_file=$(mktemp)
    local text="GatewayManagedDatabaseList lssn"
    local jsondata="{\"lssn\":${lssn}}"
    
    wget -O "$temp_file" --quiet \
        --post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
        --header="Content-Type: application/x-www-form-urlencoded" \
        "${apiaddrv2}?code=${apiaddrcode}" \
        --no-check-certificate
    
    # Python으로 JSON 파싱
    local db_list=$(python3 -c "
import json
with open('$temp_file') as f:
    data = json.load(f)
if 'data' in data:
    for item in data['data']:
        print(json.dumps(item))
")
    
    rm -f "$temp_file"
    echo "$db_list"
}
```

---

## 2. GatewayRemoteServerList - 원격 서버 목록 조회

### 용도
Gateway 서버가 관리하는 원격 서버(하트비트 대상) 목록을 조회합니다.

### 요청

**Parameters:**
```bash
text=GatewayRemoteServerList lssn
token=${sk}
jsondata={"lssn":${lssn}}
```

### 응답

```json
{
  "status": "success",
  "data": [
    {
      "LSsn": 71221,
      "LSHostname": "p-cnsldb01m",
      "gateway_ssh_host": "p-cnsldb01m",
      "gateway_ssh_port": "22",
      "gateway_ssh_user": "istyle",
      "gateway_ssh_password": "********",
      "LSStatus": 1
    }
  ]
}
```

### 응답 필드 설명

| 필드 | 타입 | 설명 |
|------|------|------|
| `LSsn` | int | 원격 서버 번호 (tLSvr.LSsn) |
| `LSHostname` | string | 서버 호스트명 |
| `gateway_ssh_host` | string | SSH 접속 호스트 |
| `gateway_ssh_port` | string | SSH 포트 (기본 22) |
| `gateway_ssh_user` | string | SSH 사용자명 |
| `gateway_ssh_password` | string | SSH 암호 (암호화됨) |
| `LSStatus` | int | 서버 상태 (1=활성) |

---

## 3. KVSPut - KVS 데이터 저장

### 용도
Key-Value Store에 데이터를 저장합니다. (lib/kvs.sh 참조)

### 요청

**Parameters:**
```bash
text=KVSPut
token=${sk}
jsondata={
  "ksn": ${lssn},
  "kType": "lssn",
  "kKey": "${key}",
  "kFactor": "${factor}",
  "kValue": "${value_json}"
}
```

### 응답

```json
{
  "status": "success",
  "message": "KVS data saved successfully"
}
```

---

## 4. UpdateManagedDatabaseHealth - DB 헬스 상태 업데이트

### 용도
Managed Database의 health check 결과를 업데이트합니다.

### 요청

**Parameters:**
```bash
text=UpdateManagedDatabaseHealth
token=${sk}
jsondata={
  "lssn": ${lssn},
  "health_results": [
    {
      "mdb_id": 4,
      "check_status": "success",
      "check_message": "Connection successful",
      "response_time_ms": 352,
      "performance": {
        "threads_connected": 8,
        "threads_running": 2,
        "questions": 12345,
        "slow_queries": 0,
        "uptime": 86400
      }
    }
  ]
}
```

### 응답

```json
{
  "status": "success",
  "updated_count": 1
}
```

---

## 보안 고려사항

### 1. 암호 처리
- **저장**: DB 암호는 암호화되어 tManagedDatabase에 저장
- **전송**: HTTPS를 통해 암호화된 채널로 전송
- **사용**: 메모리에서만 복호화하여 사용, 로그에 출력 금지

### 2. Secret Key (SK) 검증
- 모든 API 요청은 유효한 SK 필요
- tSecretKey 테이블에서 SKStatus=1인 키만 유효
- 잘못된 SK 사용 시 401 Unauthorized 반환

### 3. 로깅 규칙
```bash
# ✅ 안전한 로깅
echo "Connecting to DB: $mdb_name ($mdb_type)"

# ❌ 위험한 로깅 (암호 노출)
echo "Password: $mdb_password"  # 절대 금지!

# ✅ 마스킹 처리
echo "Connection string: mysql -h$mdb_host -u$mdb_user -p****"
```

---

## 테스트 방법

### 수동 테스트 (curl)
```bash
# 변수 설정
LSSN=71240
SK="21ac953b6ed4134e5603f6df254a6d58"
API_URL="https://giipfaw.azurewebsites.net/api/giipApiSk2"

# API 호출
curl -X POST "$API_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "text=GatewayManagedDatabaseList lssn" \
  --data-urlencode "token=$SK" \
  --data-urlencode "jsondata={\"lssn\":$LSSN}"
```

### 스크립트 테스트
```bash
# giipAgent.cnf 설정 후
source ../giipAgent.cnf

# API 호출 함수 사용
source lib/check_managed_databases.sh
check_managed_databases
```

---

## 문제 해결

### API 응답이 없음
```bash
# 1. 네트워크 연결 확인
ping giipfaw.azurewebsites.net

# 2. SSL 인증서 문제 시
wget --no-check-certificate ...

# 3. API 로그 확인 (Azure Portal)
# Functions > giipApiSk2 > Monitor > Logs
```

### JSON 파싱 실패
```bash
# 응답 확인
cat response.json | jq .

# Python 파싱 테스트
python3 -c "
import json
with open('response.json') as f:
    data = json.load(f)
    print(json.dumps(data, indent=2))
"
```

### 인증 실패 (401)
```bash
# SK 확인
echo "SK: $sk"

# DB에서 유효성 확인
SELECT SKey, SKStatus FROM tSecretKey WHERE SKey='$sk'
# SKStatus=1 이어야 함
```

---

## 관련 문서

- [LIB_FUNCTIONS_REFERENCE.md](./LIB_FUNCTIONS_REFERENCE.md) - lib 함수 상세 레퍼런스
- [DATABASE_HEALTH_CHECK_FEATURE.md](./DATABASE_HEALTH_CHECK_FEATURE.md) - DB 헬스 체크 기능 명세
- [GATEWAY_UNIFIED_GUIDE.md](./GATEWAY_UNIFIED_GUIDE.md) - Gateway 통합 가이드
- [KVS_STORAGE_STANDARD.md](./KVS_STORAGE_STANDARD.md) - 🌟 KVS 저장 표준 (lib/kvs.sh 기반)
- [KVSPUT_USAGE_GUIDE.md](./KVSPUT_USAGE_GUIDE.md) - KVS 저장 API 사용법 (구 버전, 참고용)

---

**작성일**: 2025-11-13  
**버전**: 1.0  
**작성자**: GitHub Copilot
