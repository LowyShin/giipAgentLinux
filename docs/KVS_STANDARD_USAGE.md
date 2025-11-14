# KVS Standard Module - Shell Usage Guide

KVS 표준 모듈(`lib/kvs_standard.sh`)의 Shell 스크립트 사용 가이드입니다.

## 목차

1. [개요](#개요)
2. [설치](#설치)
3. [기본 사용법](#기본-사용법)
4. [함수 레퍼런스](#함수-레퍼런스)
5. [실전 예제](#실전-예제)
6. [마이그레이션 가이드](#마이그레이션-가이드)
7. [문제 해결](#문제-해결)

---

## 개요

### 주요 기능

- ✅ **표준 kValue 구조**: `event_type`, `timestamp`, `details` 필드 자동 생성
- ✅ **안전한 JSON 생성**: `jq` 기반으로 escape 문제 없음
- ✅ **자동 URL 인코딩**: `jq -sRr @uri`로 안전한 전송
- ✅ **응답 검증**: `RstVal=200` 자동 확인
- ✅ **에러 처리**: 3가지 에러 코드로 명확한 실패 원인 파악

### 기존 방식과의 차이

| 항목 | 기존 (`kvsput.sh`) | 표준 (`kvs_standard.sh`) |
|------|-------------------|-------------------------|
| JSON 생성 | 수동 문자열 조합 ❌ | jq 기반 생성 ✅ |
| kValue 구조 | 자유 형식 ❌ | 표준 구조 ✅ |
| Timestamp | 수동 입력 ❌ | 자동 ISO 8601 ✅ |
| 에러 코드 | 단일 실패 ❌ | 3단계 코드 ✅ |
| 사용법 | 파일 기반 | 함수 호출 + 파일 둘 다 ✅ |

---

## 설치

### 1. 필수 요구사항

```bash
# jq 설치 확인
jq --version
# jq-1.6 이상 필요

# jq 설치 (없는 경우)
sudo apt-get install jq  # Debian/Ubuntu
sudo yum install jq      # RHEL/CentOS
```

### 2. 모듈 가져오기

```bash
# 스크립트에서 source
source /path/to/giipAgentLinux/lib/kvs_standard.sh

# 또는 설치 경로 자동 탐지
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/kvs_standard.sh"
```

### 3. 환경 변수 설정

```bash
# 필수 환경 변수 (giipAgent.cnf에서 자동 로드됨)
export lssn="12345"
export sk="your-secret-key"
export apiaddrv2="https://giipapi.azurewebsites.net"

# 선택 환경 변수
export HOSTNAME="$(hostname)"
export VERSION="1.0.0"
```

---

## 기본 사용법

### 방법 1: kvs_send() 함수 호출

```bash
#!/bin/bash
source lib/kvs_standard.sh

# AutoDiscover 결과 전송
kvs_send \
  "autodiscover" \
  "discovery_complete" \
  '{
    "os": "Ubuntu 20.04",
    "cpu": "Intel Xeon",
    "memory_gb": 16,
    "network": [
      {"name": "eth0", "ipv4": "192.168.1.100", "mac": "00:11:22:33:44:55"}
    ],
    "software": [
      {"name": "nginx", "version": "1.18.0"}
    ]
  }'

if [ $? -eq 0 ]; then
  echo "✓ Discovery data sent successfully"
else
  echo "✗ Failed to send discovery data"
fi
```

### 방법 2: kvs_send_file() 파일 전송

```bash
#!/bin/bash
source lib/kvs_standard.sh

# JSON 파일 생성
cat > /tmp/discovery_result.json << 'EOF'
{
  "event_type": "discovery_complete",
  "details": {
    "os": "Ubuntu 20.04",
    "cpu": "Intel Xeon",
    "memory_gb": 16
  }
}
EOF

# 파일로 전송
kvs_send_file /tmp/discovery_result.json "autodiscover"
```

---

## 함수 레퍼런스

### kvs_send()

표준 kValue 구조로 KVS API에 데이터를 전송합니다.

#### Syntax

```bash
kvs_send <kfactor> <event_type> <details_json>
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `kfactor` | string | ✅ | KVS Factor 이름 (`autodiscover`, `giipagent`, `cqeresult`, `ssh_connection`) |
| `event_type` | string | ✅ | 이벤트 유형 (`discovery_complete`, `agent_start`, `query_result` 등) |
| `details_json` | JSON string | ✅ | Factor별 상세 데이터 (JSON 형식) |

#### Return Codes

| Code | Meaning | Description |
|------|---------|-------------|
| `0` | Success | API 호출 성공 (RstVal=200) |
| `1` | Validation Error | 파라미터 누락 또는 JSON 오류 |
| `2` | Network Error | API 연결 실패 (timeout, DNS 등) |
| `3` | API Error | API 응답 오류 (RstVal≠200) |

#### Standard kValue Structure

자동으로 생성되는 구조:

```json
{
  "event_type": "discovery_complete",
  "timestamp": "2024-11-05T12:34:56Z",
  "lssn": 12345,
  "hostname": "server01",
  "version": "3.0.0",
  "details": {
    // 사용자가 전달한 details_json 내용
  }
}
```

#### Example

```bash
# GiipAgent 실행 로그 전송
kvs_send \
  "giipagent" \
  "agent_start" \
  '{
    "pid": '"$$"',
    "command": "'"$0"'",
    "start_time": "'"$(date -u '+%Y-%m-%dT%H:%M:%SZ')"'",
    "config_status": {
      "lssn": "OK",
      "sk": "OK"
    }
  }'

EXIT_CODE=$?
case $EXIT_CODE in
  0) echo "✓ Agent start logged successfully" ;;
  1) echo "✗ Invalid parameters" >&2 ;;
  2) echo "✗ Network error" >&2 ;;
  3) echo "✗ API error" >&2 ;;
esac
```

---

### kvs_send_file()

JSON 파일을 읽어서 KVS API에 전송합니다.

#### Syntax

```bash
kvs_send_file <json_file> <kfactor>
```

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `json_file` | file path | ✅ | JSON 파일 경로 (절대/상대 경로) |
| `kfactor` | string | ✅ | KVS Factor 이름 |

#### JSON File Format

파일에는 `event_type`과 `details`가 포함되어야 합니다:

```json
{
  "event_type": "query_result",
  "details": {
    "query": "SELECT COUNT(*) FROM users",
    "result": [{"count": 42}],
    "execution_time": "0.05s"
  }
}
```

#### Example

```bash
# CQE 쿼리 결과 파일 전송
cat > /tmp/cqe_result.json << EOF
{
  "event_type": "query_result",
  "details": {
    "query": "SELECT TOP 10 * FROM tbl_lsvr WHERE deleted=0",
    "result_count": 10,
    "execution_time": "0.12s",
    "status": "success"
  }
}
EOF

kvs_send_file /tmp/cqe_result.json "cqeresult"

# 파일 정리
rm -f /tmp/cqe_result.json
```

---

## 실전 예제

### 예제 1: AutoDiscover 통합

```bash
#!/bin/bash
# giip-auto-discover.sh (표준 모듈 적용)

source lib/kvs_standard.sh

# 시스템 정보 수집
OS_INFO=$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
CPU_MODEL=$(lscpu | grep "Model name" | sed 's/Model name: *//')
MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')

# 네트워크 인터페이스 수집 (JSON 배열)
NETWORK_JSON=$(ip -j addr show | jq '[
  .[] | select(.ifname != "lo") | {
    name: .ifname,
    ipv4: (.addr_info[] | select(.family == "inet") | .local),
    mac: .address
  }
]')

# KVS 전송
kvs_send \
  "autodiscover" \
  "discovery_complete" \
  "{
    \"os\": \"$OS_INFO\",
    \"cpu\": \"$CPU_MODEL\",
    \"memory_gb\": $MEMORY_GB,
    \"network\": $NETWORK_JSON,
    \"agent_version\": \"$VERSION\"
  }"

if [ $? -eq 0 ]; then
  echo "[$(date)] Discovery data sent successfully" >> /var/log/giipagent.log
else
  echo "[$(date)] Failed to send discovery data" >&2
fi
```

### 예제 2: GiipAgent 실행 로그

```bash
#!/bin/bash
# giipAgent3.sh (표준 모듈 적용)

source lib/kvs_standard.sh

START_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Agent 시작 로그
kvs_send "giipagent" "agent_start" \
  "{
    \"pid\": $$,
    \"command\": \"$0 $*\",
    \"start_time\": \"$START_TIME\",
    \"user\": \"$(whoami)\",
    \"config_status\": {
      \"lssn\": \"$([ -n "$lssn" ] && echo OK || echo MISSING)\",
      \"sk\": \"$([ -n "$sk" ] && echo OK || echo MISSING)\"
    }
  }"

# Agent 작업 수행
run_giip_tasks

# Agent 종료 로그
END_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
EXIT_CODE=$?

kvs_send "giipagent" "agent_complete" \
  "{
    \"pid\": $$,
    \"start_time\": \"$START_TIME\",
    \"end_time\": \"$END_TIME\",
    \"exit_code\": $EXIT_CODE,
    \"status\": \"$([ $EXIT_CODE -eq 0 ] && echo success || echo error)\"
  }"
```

### 예제 3: SSH 연결 모니터링

```bash
#!/bin/bash
# monitor-ssh-connections.sh

source lib/kvs_standard.sh

CONNECT_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# SSH 연결 시도
ssh -i ~/.ssh/id_rsa user@target-host "echo 'Connected'"
SSH_EXIT=$?

DISCONNECT_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# 연결 결과 전송
kvs_send \
  "ssh_connection" \
  "$([ $SSH_EXIT -eq 0 ] && echo connected || echo failed)" \
  "{
    \"target_host\": \"target-host\",
    \"user\": \"user\",
    \"auth_method\": \"key\",
    \"key_path\": \"~/.ssh/id_rsa\",
    \"connect_time\": \"$CONNECT_TIME\",
    \"disconnect_time\": \"$DISCONNECT_TIME\",
    \"status\": \"$([ $SSH_EXIT -eq 0 ] && echo success || echo error)\",
    \"exit_code\": $SSH_EXIT
  }"
```

### 예제 4: CQE 쿼리 실행

```bash
#!/bin/bash
# giipCQE.sh (표준 모듈 적용)

source lib/kvs_standard.sh

QUERY="SELECT COUNT(*) as total FROM tbl_lsvr WHERE deleted=0"
START_TIME=$(date +%s%3N)  # milliseconds

# 쿼리 실행
RESULT=$(mssql_run_query "$CONNECTION_ID" "$QUERY")
QUERY_EXIT=$?

END_TIME=$(date +%s%3N)
EXECUTION_MS=$((END_TIME - START_TIME))

# 결과 전송
if [ $QUERY_EXIT -eq 0 ]; then
  RESULT_COUNT=$(echo "$RESULT" | jq '.rowCount')
  
  kvs_send "cqeresult" "query_result" \
    "{
      \"query\": \"$(echo "$QUERY" | jq -Rs .)\",
      \"status\": \"success\",
      \"result_count\": $RESULT_COUNT,
      \"execution_time\": \"${EXECUTION_MS}ms\",
      \"result\": $(echo "$RESULT" | jq '.rows')
    }"
else
  kvs_send "cqeresult" "query_error" \
    "{
      \"query\": \"$(echo "$QUERY" | jq -Rs .)\",
      \"status\": \"error\",
      \"error\": \"Query execution failed\",
      \"error_code\": $QUERY_EXIT
    }"
fi
```

---

## 마이그레이션 가이드

### 기존 `save_execution_log()` → `kvs_send()`

**Before (lib/kvs.sh):**

```bash
save_execution_log() {
  local ktype="$1"
  local kkey="$2"
  local kfactor="$3"
  local kvalue_raw="$4"
  
  # 수동 JSON 생성 (escape 문제 발생!)
  local jsondata="{\"kType\":\"$ktype\",\"kKey\":\"$kkey\",\"kFactor\":\"$kfactor\",\"kValue\":$kvalue_raw}"
  
  wget --quiet --output-document=- \
    "${apiaddrv2}/api/v2/kvsput?lssn=${lssn}&sk=${sk}&text=${ktype} ${kkey} ${kfactor}&jsondata=${jsondata}"
}

# 사용
save_execution_log "agent_log" "$lssn" "giipagent" \
  "{\"event\":\"start\",\"time\":\"$(date)\"}"
```

**After (kvs_standard.sh):**

```bash
source lib/kvs_standard.sh

# 사용
kvs_send "giipagent" "agent_start" \
  "{
    \"event\": \"start\",
    \"time\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\"
  }"
```

### 기존 `kvsput.sh` → `kvs_send_file()`

**Before:**

```bash
# JSON 파일 생성
cat > /tmp/result.json << EOF
{
  "event": "discovery",
  "data": {...}
}
EOF

# kvsput.sh 호출
/path/to/giipscripts/kvsput.sh \
  "autodiscover" \
  "$lssn" \
  "autodiscover" \
  /tmp/result.json
```

**After:**

```bash
source lib/kvs_standard.sh

# 표준 구조로 JSON 파일 생성
cat > /tmp/result.json << EOF
{
  "event_type": "discovery_complete",
  "details": {
    "data": {...}
  }
}
EOF

# 간단한 함수 호출
kvs_send_file /tmp/result.json "autodiscover"
```

---

## 문제 해결

### Q1: "command not found: jq"

```bash
# jq 설치
sudo apt-get update && sudo apt-get install -y jq
```

### Q2: "Environment variable not set: lssn"

```bash
# giipAgent.cnf 확인
cat giipAgent.cnf
# lssn, sk, apiaddrv2 값 확인

# 수동 설정
export lssn="12345"
export sk="your-secret-key"
export apiaddrv2="https://giipapi.azurewebsites.net"
```

### Q3: "API returned error: RstVal=400"

```bash
# 전송한 JSON 확인
echo "$details_json" | jq .

# API 로그 확인 (Azure Functions)
# Azure Portal → Functions → Monitor → Logs
```

### Q4: Large payload timeout

```bash
# 1MB 이상 데이터는 분할 전송
# 예: 네트워크 인터페이스 100개 → 20개씩 5번 전송

BATCH_SIZE=20
for i in $(seq 0 $BATCH_SIZE $TOTAL_COUNT); do
  BATCH_DATA=$(echo "$FULL_DATA" | jq ".[$i:$((i+BATCH_SIZE))]")
  
  kvs_send "autodiscover" "discovery_batch_$i" \
    "{\"batch\": $i, \"data\": $BATCH_DATA}"
done
```

### Q5: 기존 스크립트 호환성

```bash
# 기존 kvsput.sh와 공존 가능
# lib/kvs.sh에 deprecation warning 추가

save_execution_log() {
  echo "[DEPRECATED] save_execution_log() is deprecated. Use kvs_send() instead." >&2
  
  # Fallback to kvs_send
  source lib/kvs_standard.sh
  kvs_send "$3" "legacy_event" "$4"
}
```

---

## 참고 문서

- [KVS_STANDARD_SPECIFICATION.md](../../giipdb/docs/KVS_STANDARD_SPECIFICATION.md) - 표준 명세
- [giipapi_rules.md](../../giipdb/docs/giipapi_rules.md) - API 규칙
- [KVS_COMPONENT_GUIDE.md](../../giipv3/docs/KVS_COMPONENT_GUIDE.md) - Frontend 컴포넌트 가이드

---

**Last Updated:** 2024-11-05  
**Version:** 1.0.0
