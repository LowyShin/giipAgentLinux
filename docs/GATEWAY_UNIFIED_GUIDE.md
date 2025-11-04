# GIIP Agent - Gateway Mode 통합 가이드

## 개요
`giipAgent.sh` **하나의 스크립트**로 모든 Gateway 기능을 처리합니다.

### 자동 처리 항목
1. ✅ Gateway 서버 자기 자신의 정보 수집
2. ✅ 관리 중인 원격 서버 목록 자동 동기화 (Web UI → CSV)
3. ✅ 원격 서버에 SSH로 접속해서 정보 수집 (Heartbeat)
4. ✅ 수집한 정보를 DB에 자동 업데이트 (`LSChkdt` 포함)
5. ✅ CQE 큐 실행 (원격 명령 실행)
6. ✅ Database 쿼리 실행 (선택사항)

## 빠른 시작

### 1. 설정 파일 편집

```bash
cd /home/giip/giipAgentLinux
vi giipAgent.cnf
```

**필수 설정**:
```bash
# Secret Key (GIIP 포털에서 확인)
sk="your_secret_key_here"

# Gateway 서버의 LSSN (tLSvr 테이블에서 확인)
lssn="71240"

# Gateway 모드 활성화
gateway_mode="1"

# Heartbeat 주기 (초) - 원격 서버 정보 수집 간격
gateway_heartbeat_interval="300"  # 5분마다

# API 설정
apiaddr="https://giipasp.azurewebsites.net"
apiaddrv2="https://giipfaw.azurewebsites.net/api/giipApiSk2"
apiaddrcode="your_azure_function_key"
```

**선택 설정**:
```bash
# Web UI 동기화 주기 (초)
gateway_sync_interval="300"  # 5분마다 Web UI에서 서버 목록 재조회

# Agent 실행 주기 (초)
giipagentdelay="60"  # CQE 큐 체크 간격
```

### 2. 단일 명령으로 실행

```bash
# 실행
./giipAgent.sh

# 또는 백그라운드 실행
nohup ./giipAgent.sh > /dev/null 2>&1 &
```

### 3. Cron 등록 (권장)

```bash
# Cron 편집
crontab -e

# 5분마다 실행 (자동 재시작)
*/5 * * * * cd /home/giip/giipAgentLinux && ./giipAgent.sh >/dev/null 2>&1
```

## 동작 방식

```
┌─────────────────────────────────────────────────────────────┐
│                    giipAgent.sh (Gateway Mode)               │
│                                                              │
│  1. 자기 자신 등록 (LSSN: 71240)                               │
│     └─→ API: AgentAutoRegister                              │
│                                                              │
│  2. Web UI에서 관리 대상 서버 목록 가져오기                      │
│     └─→ API: GatewayRemoteServerList                        │
│     └─→ 저장: giipAgentGateway_servers.csv                  │
│                                                              │
│  3. Heartbeat 실행 (5분마다)                                  │
│     └─→ 백그라운드: giipAgentGateway-heartbeat.sh           │
│         ├─ SSH 접속 → 서버 정보 수집                          │
│         ├─ OS, Memory, Disk, CPU, IP 등                     │
│         └─→ API: AgentAutoRegister (원격 서버 대신 등록)       │
│                                                              │
│  4. CQE 큐 처리 (60초마다)                                    │
│     ├─ 각 원격 서버의 큐 조회                                  │
│     └─ SSH로 명령 실행                                        │
│                                                              │
│  5. Database 쿼리 실행 (선택사항)                              │
│     └─ MySQL, PostgreSQL, MSSQL, Oracle 지원                │
└─────────────────────────────────────────────────────────────┘
```

## 로그 확인

```bash
# 오늘 로그 (실시간)
tail -f /var/log/giipAgent_$(date +%Y%m%d).log

# Heartbeat 로그 (실시간)
tail -f /var/log/giipAgentGateway_heartbeat_$(date +%Y%m%d).log

# 최근 Gateway 활동 검색
grep "\[Gateway" /var/log/giipAgent_$(date +%Y%m%d).log

# Heartbeat 성공 확인
grep "✅" /var/log/giipAgentGateway_heartbeat_$(date +%Y%m%d).log
```

**예상 로그 출력**:
```log
[20251104123456] ========================================
[20251104123456] Starting GIIP Agent in GATEWAY MODE
[20251104123456] Version: 1.80
[20251104123456] Gateway LSSN: 71240
[20251104123456] ========================================
[20251104123456] [Gateway] Fetching initial server list from Web UI...
[20251104123457] [Gateway] ✅ Fetched 3 servers from API
[20251104123458] [Gateway-Heartbeat] Running heartbeat to collect remote server info...
[20251104123459] [Gateway-Heartbeat] Started (PID: 12345)
[20251104123500] [Gateway] Processing: p-cnsldb01m (LSSN:71221, istyle@p-cnsldb01m:22)
[20251104123501] [Gateway]   📥 Queue received, executing...
[20251104123502] [Gateway]   ✅ Success
```

## 원격 서버 관리

### Web UI에서 서버 추가

1. GIIP 포털 로그인
2. **Server List** 페이지
3. Gateway 서버 (LSSN: 71240) 상세 페이지 이동
4. **"Add Managed Server"** 버튼
5. 서버 정보 입력:
   - Hostname: `p-cnsldb01m`
   - SSH Host: `p-cnsldb01m` (또는 IP 주소)
   - SSH Port: `22`
   - SSH User: `istyle`
   - Auth Type: `Password`
   - SSH Password: `********`
6. **Save**

### 자동 동기화

- `giipAgent.sh`가 **5분마다 자동으로** Web UI에서 최신 서버 목록을 가져옵니다
- 서버 추가/삭제/수정 후 **최대 5분 이내**에 자동 반영
- 수동 동기화: `gateway_sync_interval="0"` 설정 후 재시작

## 상태 확인

### 1. 프로세스 확인

```bash
# giipAgent 실행 중인지 확인
ps aux | grep giipAgent.sh | grep -v grep

# 실행 중이면 출력 예:
# giip  12345  0.0  0.1  12345  6789 ?  S  12:34  0:00 /bin/bash ./giipAgent.sh
```

### 2. Web UI에서 확인

1. **Server Detail** 페이지 (Gateway 서버)
2. **"관리 중인 서버 목록"** 섹션 확인
3. 각 서버의 상태:
   - 🟢 **정상**: 10분 이내 체크됨
   - 🟡 **지연**: 10~60분 사이 체크
   - 🔴 **오프라인**: 60분 이상 체크 안 됨
   - ⚪ **미체크**: 한 번도 체크 안 됨

### 3. DB에서 확인

```sql
-- Gateway가 관리 중인 서버 목록
SELECT 
    LSSN,
    LSHostname,
    LSChkdt,
    DATEDIFF(MINUTE, LSChkdt, GETDATE()) AS minutes_ago,
    CASE 
        WHEN LSChkdt IS NULL THEN '미체크'
        WHEN DATEDIFF(MINUTE, LSChkdt, GETDATE()) < 10 THEN '정상'
        WHEN DATEDIFF(MINUTE, LSChkdt, GETDATE()) < 60 THEN '지연'
        ELSE '오프라인'
    END AS status
FROM tLSvr
WHERE gateway_lssn = 71240  -- Gateway LSSN
ORDER BY LSChkdt DESC;
```

## 트러블슈팅

### 문제: 원격 서버가 "미체크" 상태

**원인**: Heartbeat가 실행되지 않거나 SSH 접속 실패

**해결**:
```bash
# 1. Heartbeat 스크립트 존재 확인
ls -la giipAgentGateway-heartbeat.sh

# 2. 수동 실행 테스트
./giipAgentGateway-heartbeat.sh

# 3. SSH 접속 테스트
ssh istyle@p-cnsldb01m

# 4. sshpass 설치 확인 (Password 인증 사용 시)
which sshpass

# 5. 로그 확인
tail -50 /var/log/giipAgentGateway_heartbeat_$(date +%Y%m%d).log
```

### 문제: "jq: command not found"

```bash
# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL
sudo yum install jq

# macOS
brew install jq
```

### 문제: Heartbeat가 실행되지 않음

**확인 사항**:
```bash
# 1. gateway_heartbeat_interval 설정
grep gateway_heartbeat_interval giipAgent.cnf

# 2. 0이면 비활성화됨 - 300 이상으로 설정
# 3. giipAgent.sh 재시작
pkill -f giipAgent.sh
./giipAgent.sh
```

### 문제: 서버 목록이 비어있음

```bash
# 1. API 응답 확인
curl -X POST "https://giipfaw.azurewebsites.net/api/giipApiSk2?code=YOUR_CODE" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "GatewayRemoteServerList",
    "token": "YOUR_SK",
    "csn": 70363,
    "gateway_lssn": 71240
  }'

# 2. Web UI에서 서버가 Gateway에 할당되었는지 확인
# 3. gateway_lssn 필드가 올바른지 확인
```

## 성능 최적화

### Heartbeat 주기 조정

```bash
# 빠른 업데이트 (많은 SSH 연결)
gateway_heartbeat_interval="180"  # 3분

# 균형 잡힌 설정 (권장)
gateway_heartbeat_interval="300"  # 5분

# 느린 업데이트 (SSH 연결 최소화)
gateway_heartbeat_interval="600"  # 10분
```

### CQE 큐 체크 주기

```bash
# 빠른 명령 실행 (높은 CPU 사용)
giipagentdelay="30"  # 30초

# 균형 잡힌 설정 (권장)
giipagentdelay="60"  # 1분

# 느린 체크 (낮은 CPU 사용)
giipagentdelay="120"  # 2분
```

## 파일 구조

```
giipAgentLinux/
├── giipAgent.sh                        # 메인 스크립트 (라우터 역할)
├── giipAgent.cnf                       # 설정 파일 (단일 설정)
├── giipAgentGateway-heartbeat.sh       # Heartbeat 스크립트 (자동 호출됨)
├── giipAgentGateway_servers.csv        # 서버 목록 (자동 생성)
└── /var/log/
    ├── giipAgent_YYYYMMDD.log          # 메인 로그
    └── giipAgentGateway_heartbeat_YYYYMMDD.log  # Heartbeat 로그
```

## 요약

### ✅ 장점
- **단일 진입점**: `giipAgent.sh` 하나만 실행
- **단일 설정**: `giipAgent.cnf` 하나만 편집
- **단일 Cron**: 하나의 cron 항목만 등록
- **자동 동기화**: Web UI 변경사항 자동 반영
- **자동 Heartbeat**: 원격 서버 상태 자동 업데이트
- **백그라운드 처리**: Heartbeat는 비동기로 실행 (메인 루프 차단 안 함)

### 📋 체크리스트

- [ ] `giipAgent.cnf` 설정 완료 (`sk`, `lssn`, `gateway_mode="1"`)
- [ ] `giipAgent.sh` 실행 권한 부여 (`chmod +x`)
- [ ] Web UI에서 원격 서버 등록
- [ ] Cron 등록 완료
- [ ] 로그에서 "Gateway Mode" 확인
- [ ] Web UI에서 서버 상태 "정상" 확인

## 참고 문서
- [Gateway 설치 가이드](./README_GATEWAY.md)
- [Gateway 빠른 시작](./GATEWAY_QUICKSTART_KR.md)
- [Heartbeat 상세 가이드](./docs/GATEWAY_HEARTBEAT_GUIDE.md)
