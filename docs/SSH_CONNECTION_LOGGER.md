# SSH Connection Logger Module

Gateway 서버의 SSH 접속 시도를 KVS에 자동으로 로깅하는 모듈입니다.

## 📁 파일 구조

```
giipAgentLinux/
├── lib/
│   ├── ssh_connection_logger.sh    # SSH 접속 로깅 모듈 (NEW)
│   ├── gateway.sh                  # Gateway 라이브러리 (수정됨)
│   └── kvs.sh                      # KVS 로깅 함수
│
giipdb/
└── query/
    └── ssh_connection_logging_queries.sql  # KVS 조회 쿼리 모음
```

## 🎯 기능

### 1. SSH 접속 시도 로깅 (`ssh_connection_attempt`)
Gateway에서 원격 서버로 SSH 접속을 시도할 때 자동으로 기록됩니다.

**기록 내용**:
- 대상 호스트, 포트, 사용자
- 인증 방법 (password/key)
- 대상 서버 LSSN, hostname
- 시도 시각

### 2. SSH 접속 결과 로깅 (`ssh_connection_result`)
SSH 접속 완료 후 결과를 기록합니다.

**기록 내용**:
- 성공/실패 상태
- Exit code
- 실행 시간 (초)
- 대상 서버 정보

### 3. 원격 실행 로깅 (`remote_execution`)
원격 서버 처리 전체 이벤트를 기록합니다.

**기록 내용**:
- 처리 상태 (started/success/failed)
- Queue 존재 여부
- 에러 메시지 (실패 시)

## 🔧 사용 방법

### 모듈 로드

`lib/gateway.sh`에서 자동으로 로드됩니다:

```bash
# gateway.sh 상단에 자동 포함
. "${SCRIPT_DIR}/ssh_connection_logger.sh"
```

### 함수 사용

#### 1. SSH 접속 시도 기록
```bash
log_ssh_attempt "192.168.1.21" "22" "root" "password" "71221" "server71221"
```

**파라미터**:
- `$1`: remote_host (필수)
- `$2`: remote_port (필수)
- `$3`: remote_user (필수)
- `$4`: auth_method ("password" or "key", 필수)
- `$5`: remote_lssn (선택, default: 0)
- `$6`: hostname (선택, default: "unknown")

#### 2. SSH 접속 결과 기록
```bash
log_ssh_result "192.168.1.21" "22" "0" "3" "71221" "server71221"
```

**파라미터**:
- `$1`: remote_host (필수)
- `$2`: remote_port (필수)
- `$3`: exit_code (필수, 0=성공)
- `$4`: duration_seconds (필수)
- `$5`: remote_lssn (선택, default: 0)
- `$6`: hostname (선택, default: "unknown")

#### 3. 원격 실행 이벤트 기록
```bash
log_remote_execution "success" "server71221" "71221" "192.168.1.21" "22" "true"
```

**파라미터**:
- `$1`: execution_status ("started"/"success"/"failed", 필수)
- `$2`: hostname (필수)
- `$3`: lssn (필수)
- `$4`: ssh_host (필수)
- `$5`: ssh_port (필수)
- `$6`: queue_available ("true"/"false", 선택)
- `$7`: error_message (선택, 실패 시 사용)

## 📊 KVS 데이터 구조

### ssh_connection_attempt
```json
{
  "event_type": "ssh_connection_attempt",
  "timestamp": "2025-11-14 15:30:45",
  "lssn": 71174,
  "hostname": "gateway-server",
  "mode": "gateway",
  "version": "3.0",
  "details": {
    "target_host": "192.168.1.21",
    "target_port": 22,
    "target_user": "root",
    "target_lssn": 71221,
    "target_hostname": "server71221",
    "auth_method": "password",
    "status": "attempting",
    "timestamp": "2025-11-14 15:30:45"
  }
}
```

### ssh_connection_result
```json
{
  "event_type": "ssh_connection_result",
  "timestamp": "2025-11-14 15:30:48",
  "lssn": 71174,
  "hostname": "gateway-server",
  "mode": "gateway",
  "version": "3.0",
  "details": {
    "target_host": "192.168.1.21",
    "target_port": 22,
    "target_lssn": 71221,
    "target_hostname": "server71221",
    "exit_code": 0,
    "status": "success",
    "duration_seconds": 3,
    "timestamp": "2025-11-14 15:30:48"
  }
}
```

### remote_execution
```json
{
  "event_type": "remote_execution",
  "timestamp": "2025-11-14 15:30:48",
  "lssn": 71174,
  "hostname": "gateway-server",
  "mode": "gateway",
  "version": "3.0",
  "details": {
    "hostname": "server71221",
    "lssn": 71221,
    "ssh_host": "192.168.1.21",
    "ssh_port": 22,
    "queue_available": true,
    "execution_status": "success"
  }
}
```

## 🔍 KVS 조회

### SQL 쿼리 파일 사용
```bash
cd giipdb
pwsh ./mgmt/execSQLFile.ps1 -sqlfile "./query/ssh_connection_logging_queries.sql"
```

### 주요 쿼리

#### 최근 SSH 접속 내역
```sql
SELECT TOP 50
    kRegdt,
    JSON_VALUE(kValue, '$.event_type') AS event_type,
    JSON_VALUE(kValue, '$.details.target_hostname') AS target_hostname,
    JSON_VALUE(kValue, '$.details.status') AS status,
    JSON_VALUE(kValue, '$.details.exit_code') AS exit_code
FROM tKVS
WHERE kFactor = 'giipagent'
  AND JSON_VALUE(kValue, '$.event_type') IN ('ssh_connection_attempt', 'ssh_connection_result')
ORDER BY kRegdt DESC
```

#### 특정 서버(LSSN=71221) 접속 내역
```sql
SELECT *
FROM tKVS
WHERE kFactor = 'giipagent'
  AND JSON_VALUE(kValue, '$.details.target_lssn') = '71221'
ORDER BY kRegdt DESC
```

#### SSH 접속 실패만 조회
```sql
SELECT *
FROM tKVS
WHERE kFactor = 'giipagent'
  AND JSON_VALUE(kValue, '$.event_type') = 'ssh_connection_result'
  AND JSON_VALUE(kValue, '$.details.status') = 'failed'
ORDER BY kRegdt DESC
```

## ⚙️ Exit Code 정의

| Exit Code | 의미 | 설명 |
|-----------|------|------|
| 0 | Success | SSH 접속 및 실행 성공 |
| 1 | Generic Error | 일반 실행 오류 |
| 125 | No Auth | 인증 방법 없음 (password/key 모두 없음) |
| 126 | SCP Failed | 스크립트 복사 실패 |
| 127 | No sshpass | sshpass 명령어 없음 (password 인증 시) |

## 🧪 테스트

### 1. 모듈 로드 확인
```bash
cd ~/giipAgentLinux
source lib/ssh_connection_logger.sh

# 확인
type log_ssh_attempt
# → function이 표시되면 정상
```

### 2. 수동 로깅 테스트
```bash
# KVS 함수 로드 필요
source lib/kvs.sh

# SSH 시도 기록
log_ssh_attempt "192.168.1.21" "22" "root" "password" "71221" "test-server"

# 결과 기록
log_ssh_result "192.168.1.21" "22" "0" "3" "71221" "test-server"
```

### 3. Gateway 실행 후 확인
```bash
# Gateway Agent 실행
cd ~/giipAgentGateway
./giipAgent3.sh

# 로그 확인
tail -f /root/giipAgent/logs/giipAgent.log | grep "SSH-Logger"

# KVS 확인 (DB)
# → ssh_connection_logging_queries.sql 사용
```

## 📝 디버깅

### 로그 파일 위치
```bash
# Gateway Agent 로그
/root/giipAgent/logs/giipAgent.log

# SSH 로거 메시지 grep
grep "SSH-Logger" /root/giipAgent/logs/giipAgent.log

# 특정 LSSN 검색
grep "LSSN:71221" /root/giipAgent/logs/giipAgent.log
```

### 모듈 로드 실패 시
```bash
# 1. 파일 존재 확인
ls -la ~/giipAgentLinux/lib/ssh_connection_logger.sh

# 2. 권한 확인
chmod +x ~/giipAgentLinux/lib/ssh_connection_logger.sh

# 3. 문법 체크
bash -n ~/giipAgentLinux/lib/ssh_connection_logger.sh
```

## 🔄 업데이트 방법

```bash
# 1. Git Pull
cd ~/giipAgentLinux
git pull

# 2. 파일 확인
ls -la lib/ssh_connection_logger.sh

# 3. Agent 재시작
pkill -f giipAgent3.sh
# cron이 자동으로 재시작함
```

## 📚 관련 문서

- [GIIPAGENT3_SPECIFICATION.md](../docs/GIIPAGENT3_SPECIFICATION.md) - Agent 전체 구조
- [MODULAR_ARCHITECTURE.md](../docs/MODULAR_ARCHITECTURE.md) - 모듈 아키텍처
- [KVS_QUERY_GUIDE.md](../../giipdb/docs/KVS_QUERY_GUIDE.md) - KVS 조회 가이드

## 🐛 알려진 이슈

없음

## ✨ 기여

버그 리포트나 기능 제안은 GitHub Issues에 등록해주세요.

---

**Version**: 1.0  
**Last Updated**: 2025-11-14  
**Author**: Lowy Shin
