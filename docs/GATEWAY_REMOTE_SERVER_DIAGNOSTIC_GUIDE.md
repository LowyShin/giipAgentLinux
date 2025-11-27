# 🔍 Gateway 리모트 서버 처리 중단 - 진단 가이드

> **📅 문서 메타데이터**  
> - 작성일: 2025-11-27
> - 용도: Gateway가 리모트 서버를 처리하지 않을 때 원인 파악
> - 대상: DevOps, Gateway 관리자
> - 관련 파일: `giipAgent3.sh`, `lib/gateway.sh`

---

## 🎯 개요

Gateway 서버가 갑자기 리모트 서버 처리를 중단한 경우 체계적으로 원인을 파악하는 진단 가이드입니다.

---

## 📊 진단 체크리스트

### ✅ Level 1: 기본 설정 확인 (소요 시간: 5분)

#### 1️⃣ Gateway 모드 활성화 확인

```bash
# giipAgent.cnf 확인
cat /path/to/giipAgent.cnf | grep -E "is_gateway|gateway_mode"

# 예상 결과:
# is_gateway=1 또는 gateway_mode=1
```

**진단 포인트:**
- [ ] `is_gateway` 또는 `gateway_mode`가 `1` 또는 `true`로 설정되어 있는가?
- [ ] 값이 `0` 또는 `false`로 변경되었는가?

**문제 발견 시:**
```bash
# giipAgent.cnf 수정
sed -i 's/is_gateway=0/is_gateway=1/g' giipAgent.cnf
```

#### 2️⃣ DB 설정 값 조회 (실시간 확인)

```bash
# giipAgent3.sh 로그 포인트 #5.2 확인
# 로그에서 "is_gateway" 값 추출

# 직접 조회 (API 테스트)
curl -X POST \
  -d "text=LSvrGetConfig lssn hostname&token=YOUR_SECRET_KEY&jsondata={\"lssn\":YOUR_LSSN,\"hostname\":YOUR_HOSTNAME}" \
  https://YOUR_API_URL

# 응답 형식 예시:
# {"data":[{"is_gateway":true,"RstVal":"200",...}]}
```

**진단 포인트:**
- [ ] API 응답에 `is_gateway` 필드가 있는가?
- [ ] 값이 `true` 또는 `1`인가?
- [ ] API 자체가 응답하는가 (연결 실패는 아닌가)?

#### 3️⃣ 로그 포인트 확인 (실행 흐름 추적)

```bash
# giipAgent3.sh 실행 후 로그 확인
# 로그 위치: 보통 /var/log/giip/ 또는 /tmp/

# 포인트 #5.1 ~ #5.3 확인
grep -E "\[5\.[1-3]\]" /path/to/logfile

# 예상 출력:
# [giipAgent3.sh] 🟢 [5.1] Agent 시작: version=3.00
# [giipAgent3.sh] 🟢 [5.2] 설정 로드 완료: lssn=12345, hostname=gateway01, is_gateway=1
# [giipAgent3.sh] 🟢 [5.3] Gateway 모드 감지 및 초기화
```

**진단 포인트:**
- [ ] `[5.1]` 로그가 있는가? (Agent 시작)
- [ ] `[5.2]` 로그가 있는가? (설정 로드)
  - [ ] `is_gateway=1`이 명시되어 있는가?
- [ ] `[5.3]` 로그가 있는가? (Gateway 모드 초기화)

**문제 발견 시:**
- `[5.2]`에서 `is_gateway=0`이면 DB 설정 확인 필요
- `[5.2]`가 없으면 DB API 연결 문제
- `[5.3]`이 없으면 실제 Gateway 모드 진입 실패

**✅ 더 빠른 방법: KVS 데이터로 확인**

```powershell
# Windows/PowerShell에서
cd giipdb
pwsh .\mgmt\check-latest.ps1

# 출력:
# 최근 5분 내 [5.x] 포인트 로그 표시
# 예: 16/82 (전체 82개 중 최근 5분 내 16개)
```

| 포인트 | 의미 | KVS Factor | 정상 상태 |
|-------|------|-----------|---------|
| [5.1] | Agent 시작 | giipagent | 매 사이클마다 1회 |
| [5.2] | 설정 로드 완료 | api_lsvrgetconfig_success | is_gateway=1 포함 |
| [5.3] | Gateway 모드 초기화 | gateway_init | 항상 나타남 |
| [5.4] | 서버 목록 조회 시작 | gateway_operation | 주기적 반복 |

**의심 신호:**
- ❌ [5.1] ~ [5.3] 중 하나 이상 없음: 초기화 실패
- ❌ [5.3] 이후 [5.4]가 오지 않음: 서버 조회 루프 미진입
- ❌ 같은 포인트가 반복: Hang/데드락 가능성

---

### ✅ Level 2: 데이터베이스 조회 확인 (소요 시간: 10분)

#### 1️⃣ `process_gateway_servers()` 함수 추적

```bash
# gateway.sh에서 로깅 포인트 #5.4 확인
# 이 함수가 리모트 서버 목록을 조회하고 처리를 시작하는 지점

grep -E "\[5\.4\]|GatewayRemoteServerListForAgent" /path/to/logfile

# 예상 출력:
# [gateway.sh] 🟢 [5.4] Gateway 서버 목록 조회 시작: lssn=12345
```

**진단 포인트:**
- [ ] `[5.4]` 로그가 있는가?
- [ ] 있다면 → **Level 3 (데이터 조회 문제)**로 진행
- [ ] 없다면 → Gateway 모드가 실제로 진입되지 않음

#### 2️⃣ API 호출 직접 테스트

```bash
# GatewayRemoteServerListForAgent API 직접 호출
TEMP_FILE="/tmp/test_gateway_servers.json"

curl -X POST \
  -d "text=GatewayRemoteServerListForAgent lssn&token=YOUR_SECRET_KEY&jsondata={\"lssn\":YOUR_LSSN}" \
  https://YOUR_API_URL \
  -o "$TEMP_FILE"

# 결과 확인
cat "$TEMP_FILE" | jq .

# 예상 결과:
# {
#   "data": [
#     {"lssn": 12346, "hostname": "remote01", ...},
#     {"lssn": 12347, "hostname": "remote02", ...}
#   ]
# }
```

**진단 포인트:**
- [ ] API 호출이 성공하는가? (HTTP 200 + JSON 응답)
- [ ] `data` 배열이 있는가?
- [ ] 배열이 비어있는가? → **리모트 서버가 없음**
- [ ] 예상했던 리모트 서버가 있는가?

#### 3️⃣ 데이터베이스 테이블 직접 확인

```bash
# DB 직접 조회 (SQL Server 예시)
sqlcmd -S YOUR_DB_SERVER -d YOUR_DB -U YOUR_USER -P YOUR_PASSWORD -Q "
  SELECT 
    tManagedServer.lssn,
    tManagedServer.hostname,
    tManagedServer.is_gateway,
    tManagedServerDetail.remote_gateways
  FROM tManagedServer
  LEFT JOIN tManagedServerDetail ON tManagedServer.lssn = tManagedServerDetail.lssn
  WHERE tManagedServer.is_gateway = 1
"

# MySQL 예시
mysql -h YOUR_DB_HOST -u YOUR_USER -p -e "
  SELECT 
    lssn, hostname, is_gateway
  FROM tManagedServer
  WHERE is_gateway = 1;
"
```

**진단 포인트:**
- [ ] Gateway 서버가 `is_gateway=1`로 표시되어 있는가?
- [ ] 리모트 서버 관계 테이블이 있는가?
- [ ] 해당 Gateway에 할당된 리모트 서버가 있는가?

---

### ✅ Level 3: 데이터 조회 및 처리 확인 (소요 시간: 15분)

#### 1️⃣ 서버 목록 처리 로그 확인

```bash
# gateway.sh의 주요 로깅 포인트들
grep -E "\[5\.[4-9]\]|\[6\.[0-9]\]" /path/to/logfile

# 예상 출력 시퀀스:
# [5.4] 서버 목록 조회 시작
# [5.5] 서버 목록 조회 완료 (count=2)
# [5.6] 서버 1 처리 시작
# [5.7] SSH 연결 테스트
# [5.8] 원격 명령 실행
# [6.0] 서버 2 처리 시작
# ... (반복)
```

**진단 포인트:**
- [ ] `[5.4]` 이후 로그가 없는가? → **API 응답 문제**
- [ ] `[5.5]` 이후 로그가 없는가? → **서버 목록 처리 루프 진입 실패**
- [ ] `[5.6]` 이후 로그가 없는가? → **SSH 연결 문제**

#### 2️⃣ SSH 연결 상태 확인

```bash
# 각 리모트 서버별 SSH 테스트
for server in $(cat /path/to/remote_servers.txt); do
  echo "Testing $server..."
  sshpass -p YOUR_PASSWORD ssh -o ConnectTimeout=5 giip@$server "echo 'OK'"
done

# 또는 gateway.sh 로그에서 SSH 결과 확인
grep -i "ssh\|connection\|connectivity" /path/to/logfile
```

**진단 포인트:**
- [ ] SSH 연결이 성공하는가?
- [ ] SSH 인증 실패는 아닌가?
- [ ] 네트워크 타임아웃이 발생하는가?
- [ ] sshpass 도구가 설치되어 있는가?

#### 3️⃣ 데이터 수집 상태 확인

```bash
# gateway.sh에서 리모트 명령 실행 결과 확인
grep -E "remote_command_result|ssh_output|command_execution" /path/to/logfile

# KVS에 저장된 데이터 확인
# (KVS 저장소 접근 방법은 환경에 따라 다름)
```

**진단 포인트:**
- [ ] 리모트 명령 실행 로그가 있는가?
- [ ] 명령 실행이 실패했는가?
- [ ] 데이터가 KVS에 저장되었는가?

#### 4️⃣ KVS 데이터 확인 (중요!)

**방법 1️⃣: PowerShell 스크립트로 조회 (권장)**

```powershell
# giipdb 디렉토리에서 실행
cd giipdb

# 1. 최근 5분 Gateway 실행 흐름 확인 (가장 빠르고 정확!)
pwsh .\mgmt\check-latest.ps1

# 2. 특정 서버의 최근 20개 Gateway 로그 조회
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey YOUR_GATEWAY_LSSN -KFactor gateway_operation -Top 20

# 3. 특정 서버의 모든 Factor 목록 (summary)
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey YOUR_GATEWAY_LSSN -Summary
```

**방법 2️⃣: Web UI로 조회**

```
# 특정 서버의 모든 Factor 목록 확인
https://giip.littleworld.net/ko/kvsfactorlistlsvr?kType=lssn&kKey=YOUR_GATEWAY_LSSN

# 특정 Factor 데이터 조회 (예: gateway_operation)
https://giip.littleworld.net/ko/kvslist?kFactor=gateway_operation&kKey=YOUR_GATEWAY_LSSN
```

**방법 3️⃣: SQL 직접 조회**

```sql
-- 특정 Gateway의 최근 10개 gateway_operation 로그
SELECT TOP 10
    kvsn, kType, kKey, kFactor, kValue, kRegdt
FROM tKVS
WHERE kKey = 'YOUR_GATEWAY_LSSN'
  AND kFactor = 'gateway_operation'
ORDER BY kRegdt DESC

-- 모든 Factor 현황 확인
SELECT kFactor, COUNT(*) as cnt, MAX(kRegdt) as last_update
FROM tKVS
WHERE kKey = 'YOUR_GATEWAY_LSSN'
GROUP BY kFactor
ORDER BY last_update DESC

-- 특정 Factor의 JSON 값 파싱 (예: [5.x] 포인트 추출)
SELECT 
    kRegdt,
    JSON_VALUE(kValue, '$.point') as point,
    JSON_VALUE(kValue, '$.event_type') as event_type,
    kValue
FROM tKVS
WHERE kKey = 'YOUR_GATEWAY_LSSN'
  AND kFactor = 'gateway_operation'
ORDER BY kRegdt DESC
```

**KVS 데이터 해석:**

| kFactor | 의미 | 확인 항목 |
|---------|------|---------|
| gateway_operation | Gateway 실행 흐름 포인트 | [5.x] 포인트 시퀀스 |
| gateway_cycle | Gateway 사이클 시작/종료 | 주기적 실행 여부 |
| api_lsvrgetconfig_response | DB 설정 로드 응답 | is_gateway 값 |
| api_lsvrgetconfig_success | 설정 로드 성공 | 설정 정상 수신 |
| api_lsvrgetconfig_failed | 설정 로드 실패 | API 연결 문제 |
| gateway_init | Gateway 초기화 로그 | 초기화 상태 |

**진단 포인트:**
- [ ] 최근 5분 내 [5.4] 포인트가 있는가?
- [ ] [5.5] 이후 포인트들이 순서대로 나타나는가?
- [ ] 같은 포인트가 반복되는 것은 아닌가? (hang의 신호)
- [ ] kValue에 에러 메시지가 있는가?

---

### ✅ Level 4: 심화 진단 (소요 시간: 20-30분)

#### 1️⃣ 전체 실행 흐름 재구성

```bash
# giipAgent3.sh 전체 실행 로그 추출
tail -500 /path/to/complete_logfile > /tmp/giip_diagnostic_dump.log

# 특정 포인트만 추출
grep -E "ERROR|WARN|FAIL|\[5\.\d\]|\[6\.\d\]" /tmp/giip_diagnostic_dump.log > /tmp/giip_key_events.log

# 시간 순서대로 정렬 및 분석
cat /tmp/giip_key_events.log
```

#### 2️⃣ 환경 변수 확인

```bash
# giipAgent3.sh가 실행될 때의 환경 확인
env | grep -E "SCRIPT_DIR|LIB_DIR|PATH" | head -20

# 라이브러리 파일 존재 확인
ls -la /path/to/giipAgentLinux/lib/*.sh | grep -E "gateway|discovery|normal"
```

**진단 포인트:**
- [ ] 필수 라이브러리 파일이 모두 있는가?
  - [ ] `lib/gateway.sh`
  - [ ] `lib/db_clients.sh`
  - [ ] `lib/discovery.sh`
  - [ ] `lib/normal.sh`
- [ ] 파일 권한이 정상인가? (실행 가능한가?)
- [ ] `PATH` 환경 변수가 정상인가?

#### 3️⃣ 강제 디버그 모드 실행

```bash
# giipAgent3.sh를 디버그 모드로 실행
bash -x /path/to/giipAgent3.sh 2>&1 | tee /tmp/debug_output.log

# 또는 특정 부분만 디버그
bash -x -c 'source lib/gateway.sh; process_gateway_servers' 2>&1
```

#### 4️⃣ 네트워크 진단

```bash
# Gateway 서버의 네트워크 상태 확인
netstat -tuln | grep LISTEN
ss -tuln | grep LISTEN

# DNS 해석 확인
nslookup YOUR_REMOTE_SERVER_HOSTNAME
dig YOUR_REMOTE_SERVER_HOSTNAME

# 네트워크 경로 확인
traceroute YOUR_REMOTE_SERVER_IP
mtr YOUR_REMOTE_SERVER_IP
```

---

## 🔧 일반적인 원인과 해결책

### 원인 1: `is_gateway` 설정이 0 또는 false

**증상:**
- 로그에 `[5.3]` 포인트가 없음
- "Running in NORMAL MODE" 메시지 표시

**해결:**
```bash
# 1. giipAgent.cnf 수정
sed -i 's/is_gateway=0/is_gateway=1/g' /path/to/giipAgent.cnf

# 2. DB 테이블 수정 (필요시)
# SQL Server:
UPDATE tManagedServer SET is_gateway = 1 WHERE lssn = YOUR_GATEWAY_LSSN

# 3. giipAgent3.sh 재실행
./giipAgent3.sh
```

---

### 원인 2: DB API 연결 실패

**증상:**
- 로그에 `[5.2]` 포인트가 없거나 "Failed to fetch server config" 메시지
- API URL이 잘못되었거나 네트워크 연결 불가

**확인:**
```bash
# API 연결 테스트
curl -I https://YOUR_API_URL

# SSL 인증서 문제 확인
curl -v https://YOUR_API_URL 2>&1 | grep -i "certificate\|ssl"

# 방화벽 확인
telnet YOUR_API_URL 443
```

**해결:**
```bash
# giipAgent.cnf에서 API URL 확인
grep -i "apiaddr" /path/to/giipAgent.cnf

# 필요시 수정
sed -i 's|apiaddrv2=.*|apiaddrv2="https://correct-url"|g' /path/to/giipAgent.cnf
```

---

### 원인 3: 리모트 서버 목록이 비어있음

**증상:**
- 로그에 `[5.5]` 포인트에서 "count=0" 표시
- GatewayRemoteServerListForAgent API가 빈 배열 반환

**확인:**
```bash
# DB에서 직접 확인
# 해당 Gateway에 할당된 리모트 서버가 있는가?
SELECT COUNT(*) FROM tManagedServer WHERE gateway_lssn = YOUR_GATEWAY_LSSN
```

**해결:**
```bash
# 1. DB 테이블에 리모트 서버 추가
# 2. 또는 API를 통해 서버 등록
# 3. 다시 시도
./giipAgent3.sh
```

---

### 원인 4: SSH 연결 실패

**증상:**
- 로그에 `[5.7]` (SSH 연결 테스트) 이후 에러 메시지
- "sshpass: Permission denied" 또는 "Connection refused"

**확인:**
```bash
# sshpass 설치 확인
which sshpass
sshpass -V

# SSH 키 또는 암호 확인
ssh -i /path/to/key giip@YOUR_REMOTE_SERVER "echo OK"
```

**해결:**
```bash
# 1. sshpass 설치 (없으면)
apt-get install sshpass  # Ubuntu/Debian
yum install sshpass      # CentOS/RHEL

# 2. SSH 인증 정보 확인
# giipAgent.cnf에서 SSH 설정 확인
grep -i "ssh\|remote_user\|remote_pass" /path/to/giipAgent.cnf

# 3. 방화벽 확인
# 리모트 서버의 SSH 포트(보통 22) 열려있는가?
telnet YOUR_REMOTE_SERVER_IP 22
```

---

### 원인 5: 라이브러리 파일 누락 또는 손상

**증상:**
- 에러: "gateway.sh not found" 또는 유사한 메시지
- 또는 라이브러리 함수 정의 안됨 에러

**확인:**
```bash
# 라이브러리 파일 확인
ls -la /path/to/giipAgentLinux/lib/

# 파일 무결성 확인
md5sum /path/to/giipAgentLinux/lib/*.sh

# 파일 인코딩 확인 (DOS/Unix line endings 문제)
file /path/to/giipAgentLinux/lib/gateway.sh
```

**해결:**
```bash
# 1. 라이브러리 파일 권한 수정
chmod +x /path/to/giipAgentLinux/lib/*.sh

# 2. 라인 ending 수정 (필요시)
dos2unix /path/to/giipAgentLinux/lib/*.sh

# 3. 파일 재다운로드 (손상된 경우)
# Git에서 다시 받아오기 등
```

---

## 📋 빠른 진단 스크립트

### ⭐ 최우선: KVS 기반 Gateway 디버깅 (권장)

```powershell
# giipdb 디렉토리 이동
cd C:\path\to\giipdb

# 1️⃣ 최근 5분 Gateway 실행 흐름 확인 (가장 빠름!)
pwsh .\mgmt\check-latest.ps1

# 출력: [5.x] 포인트별 실행 흐름
# 예상:
# [5.1] Agent 시작
# [5.2] 설정 로드
# [5.3] Gateway 모드 초기화
# [5.4] 서버 목록 조회 시작
# ...

# 2️⃣ 특정 서버의 최근 Gateway 로그 상세 조회
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey YOUR_GATEWAY_LSSN -KFactor gateway_operation -Top 50

# 3️⃣ 모든 로그 카테고리 현황 확인
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey YOUR_GATEWAY_LSSN -Summary
```

### 전통적 방법: 로그 파일 기반 진단

```bash
#!/bin/bash
# 빠른 진단 자동화 스크립트

echo "=== GIIP Gateway 리모트 서버 처리 진단 ==="
echo ""

# 1. 설정 확인
echo "1️⃣ 설정 확인:"
cat /path/to/giipAgent.cnf | grep -i "is_gateway"

# 2. 최근 로그 확인
echo ""
echo "2️⃣ 최근 로그 확인:"
grep -E "\[5\.[1-4]\]" /path/to/logfile | tail -5

# 3. 라이브러리 확인
echo ""
echo "3️⃣ 라이브러리 파일 확인:"
ls -la /path/to/giipAgentLinux/lib/gateway.sh

# 4. 네트워크 확인
echo ""
echo "4️⃣ 네트워크 확인:"
ping -c 1 YOUR_API_URL 2>&1 | head -2

# 5. SSH 확인
echo ""
echo "5️⃣ SSH 확인:"
which sshpass && sshpass -V || echo "sshpass not installed"

echo ""
echo "=== 진단 완료 ==="
```

---

### 추가: Linux 환경 KVS 확인 (SSH 원격 접근)

```bash
#!/bin/bash
# Linux Gateway 서버에서 직접 KVS 데이터 확인

LSSN="YOUR_GATEWAY_LSSN"
LOGFILE="/var/log/giip/giipAgent3.log"  # 또는 /tmp/

echo "=== Gateway 최근 실행 흐름 ==="
grep -E "\[5\.[1-9]\]|\[6\.[0-9]\]" "$LOGFILE" | tail -20

echo ""
echo "=== Gateway 에러/경고 ==="
grep -E "ERROR|WARN|FAIL" "$LOGFILE" | tail -10

echo ""
echo "=== KVS 로그 파일 확인 ==="
ls -lht /tmp/discovery_kvs_log_*.txt 2>/dev/null | head -5
ls -lht /tmp/gateway_* 2>/dev/null | head -5
```

---

## 📞 문제 해결 결정 트리

```
리모트 서버 처리 중단 발생
│
├─ 로그 포인트 [5.3] 확인
│  ├─ 있음 → Level 2로 진행
│  └─ 없음 → is_gateway 설정 확인 (원인 1)
│
├─ API 응답 확인 (GatewayRemoteServerListForAgent)
│  ├─ 실패 → DB API 연결 확인 (원인 2)
│  ├─ 빈 배열 → 리모트 서버 목록 확인 (원인 3)
│  └─ 정상 → Level 3으로 진행
│
├─ SSH 연결 로그 확인
│  ├─ SSH 에러 → SSH 설정 확인 (원인 4)
│  └─ 에러 메시지 없음 → 라이브러리 확인 (원인 5)
│
└─ 해결되지 않으면 → Level 4 심화 진단 진행
```

---

## 📚 관련 문서

| 문서 | 용도 | 우선순위 |
|------|------|--------|
| [GIIPAGENT3_SPECIFICATION.md](./GIIPAGENT3_SPECIFICATION.md) | Agent 3.0 전체 스펙 | 🟠 중요 |
| [GATEWAY_CONFIG_PHILOSOPHY.md](./GATEWAY_CONFIG_PHILOSOPHY.md) | Gateway 설정 철학 | 🟡 참고 |
| [REMOTE_AUTO_DISCOVER_DESIGN.md](./REMOTE_AUTO_DISCOVER_DESIGN.md) | 리모트 auto-discover 설계 | 🟡 참고 |
| [KVS_LOGGING_DIAGNOSIS_GUIDE.md](./KVS_LOGGING_DIAGNOSIS_GUIDE.md) | KVS 로깅 진단 | 🔴 필수 |
| [SSH_CONNECTION_LOGGER.md](./SSH_CONNECTION_LOGGER.md) | SSH 연결 로깅 모듈 | 🟡 참고 |
| [KVS_QUERY_GUIDE.md](../../giipdb/docs/KVS_QUERY_GUIDE.md) | KVS 조회 가이드 | 🔴 **필수** |
| [KVS_DEBUG_GUIDE.md](../../giipdb/docs/KVS_DEBUG_GUIDE.md) | KVS 디버그 가이드 | 🔴 **필수** |

---

## 🔄 문제 해결 프로세스

1. **초기 진단**: Level 1 체크리스트 완료
2. **근본 원인 파악**: Level 2-3 진단 수행
3. **일반적 원인별 해결**: 5가지 원인 중 해당 항목 적용
4. **심화 진단**: 위의 모든 단계 후에도 미해결 시 Level 4 진행
5. **검증**: 변경 후 giipAgent3.sh 재실행 및 로그 확인

---

## 📝 체크리스트: 문제 해결 완료 확인

### 설정 및 초기화
- [ ] is_gateway 설정이 1 또는 true인가?
- [ ] 로그 포인트 [5.1]이 나타나는가?
- [ ] 로그 포인트 [5.2]에서 is_gateway=1인가?
- [ ] 로그 포인트 [5.3]이 나타나는가?

### 데이터 조회
- [ ] GatewayRemoteServerListForAgent API가 응답하는가?
- [ ] 리모트 서버 목록이 비어있지 않은가?
- [ ] 로그 포인트 [5.4] 이후 서버 처리 로그가 있는가?

### 연결 및 실행
- [ ] SSH 연결이 성공하는가?
- [ ] sshpass 또는 SSH 키가 제대로 설정되어 있는가?
- [ ] 라이브러리 파일이 모두 있는가?

### KVS 데이터 확인 (권장)
- [ ] `pwsh .\mgmt\check-latest.ps1` 결과에서 [5.x] 포인트 시퀀스가 정상인가?
- [ ] KVS에 `gateway_operation` Factor 데이터가 있는가?
- [ ] 최근 5분 내 [5.4] 포인트 이후 포인트들이 있는가?
- [ ] 같은 포인트가 무한 반복되는 것은 아닌가?

### 최종 검증
- [ ] giipAgent3.sh 재실행 후 리모트 서버가 처리되는가?
- [ ] 로그에서 에러나 경고 메시지가 없는가?
- [ ] 이전과 다르게 정상 작동하는가?

**모두 확인되면 문제 해결 완료! ✅**

---

## 🔗 다음 단계

**문제 해결 완료:**
- 정상적으로 작동 확인 후 모니터링 계속

**여전히 미해결:**
- [KVS_LOGGING_DIAGNOSIS_GUIDE.md](./KVS_LOGGING_DIAGNOSIS_GUIDE.md)의 Phase별 분석 참고
- [CURRENT_ISSUES.md](../../giipdb/docs/CURRENT_ISSUES.md)에서 유사 이슈 확인
