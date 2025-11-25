# Auto-Discovery Architecture

---

## 🔗 **문서 간 링크**

| 문서 | 용도 | 링크 |
|------|------|------|
| **[GATEWAY_HANG_DIAGNOSIS.md](GATEWAY_HANG_DIAGNOSIS.md)** | Architecture 필수 이해 | 필수 읽기 문서 목록 |
| **[AUTO_DISCOVER_LOGGING_DIAGNOSIS.md](AUTO_DISCOVER_LOGGING_DIAGNOSIS.md)** | Discovery 진단 | 문제 발생시 참조 |
| **[AUTO_DISCOVER_LOGGING_ENHANCED.md](AUTO_DISCOVER_LOGGING_ENHANCED.md)** | 로깅 구현 | 실행 흐름 및 로깅 포인트 |
| **[MODULAR_ARCHITECTURE.md](MODULAR_ARCHITECTURE.md)** | 모듈 설계 | 함수 정의 위치 규칙 |
| **[SHELL_COMPONENT_SPECIFICATION.md](SHELL_COMPONENT_SPECIFICATION.md)** | 컴포넌트 표준 | 에러 핸들링 규칙 |

---

## 📁 파일 구조

```
giipAgentLinux/
├── giip-auto-discover.sh              # Wrapper (통합 관리자)
├── giipAgent.cnf                      # 설정 파일 (sk, lssn, API 주소)
└── giipscripts/
    └── auto-discover-linux.sh         # Data Collector (데이터 수집 전문)
```

---

## 🎯 설계 철학: Separation of Concerns

### Unix Philosophy
> "Do one thing and do it well"

각 스크립트는 하나의 책임만 가지며, 독립적으로 테스트/수정 가능합니다.

---

## 📋 역할 분리

### 1. giip-auto-discover.sh (Wrapper/Orchestrator)

**책임**: 비즈니스 로직 및 통합 관리

#### 주요 기능:
- ✅ **설정 로드**: `giipAgent.cnf` 읽기
  ```bash
  . "$CONFIG_FILE"  # sk, lssn, apiaddrv2 변수 로드
  ```

- ✅ **데이터 수집 호출**: 하위 스크립트 실행
  ```bash
  DISCOVERY_JSON=$("$DISCOVERY_SCRIPT" 2>&1)
  ```

- ✅ **메타데이터 추가**: Agent 버전 정보
  ```bash
  DISCOVERY_JSON=$(echo "$DISCOVERY_JSON" | sed "s/}$/, \"agent_version\": \"$AGENT_VERSION\" }/")
  ```

- ✅ **API 통신**: Azure Function 호출
  ```bash
  curl -X POST "${apiaddrv2}" \
    --data-urlencode "text=AgentAutoRegister hostname" \
    --data-urlencode "jsondata=$DISCOVERY_JSON" \
    --data-urlencode "sk=$sk"
  ```

- ✅ **LSSN 자동 등록**: 신규 서버 처리
  ```bash
  if [ "$lssn" = "0" ]; then
      NEW_LSSN=$(echo "$RESPONSE" | grep -oP '"lssn":\s*\K\d+')
      sed -i "s/lssn=\"0\"/lssn=\"$NEW_LSSN\"/" "$CONFIG_FILE"
  fi
  ```

- ✅ **로깅**: 전체 프로세스 기록
  ```bash
  echo "[$(date)] Starting auto-discovery..." >> "$LOG_FILE"
  ```

#### 실행 방법:
```bash
# Cron에서 자동 실행
*/5 * * * * /root/giipAgentLinux/giip-auto-discover.sh

# 수동 실행
./giip-auto-discover.sh
```

---

### 2. giipscripts/auto-discover-linux.sh (Data Collector)

**책임**: 순수 데이터 수집 및 JSON 생성

#### 주요 기능:
- ✅ **OS 정보**: `/etc/os-release`, `uname`
- ✅ **CPU**: `lscpu`, `/proc/cpuinfo`
- ✅ **메모리**: `/proc/meminfo`
- ✅ **네트워크**: `ip addr`, `ifconfig`
- ✅ **소프트웨어**: `rpm -qa` / `dpkg -l` (서비스 패키지만 필터링)
- ✅ **서비스**: `systemctl list-units --type=service`
- ✅ **JSON 출력**: 표준 출력으로 구조화된 데이터 반환

#### 특징:
- ❌ 설정 파일 읽지 않음 (독립적)
- ❌ API 호출 안함 (순수 데이터 수집)
- ❌ 로그 파일 기록 안함 (stdout만)
- ❌ LSSN 몰라도 됨 (서버 식별 관여 안함)

#### 실행 방법:
```bash
# 독립 실행 (JSON 출력)
./giipscripts/auto-discover-linux.sh

# JSON 파일로 저장
./giipscripts/auto-discover-linux.sh > server-info.json

# jq로 분석
./giipscripts/auto-discover-linux.sh | jq '.software | length'
```

---

## 🔄 실행 흐름 (Sequence Diagram)

```
┌─────────┐
│  Cron   │ (*/5 * * * *)
└────┬────┘
     │
     ▼
┌────────────────────────────────────────────────┐
│  giip-auto-discover.sh (Wrapper)               │
├────────────────────────────────────────────────┤
│ 1. Load giipAgent.cnf                          │
│    - sk="ffd96879858fe73fc31d923a74ae23b5"    │
│    - lssn="71174"                              │
│    - apiaddrv2="...giipApiSk2"                 │
└────┬───────────────────────────────────────────┘
     │
     ▼
┌────────────────────────────────────────────────┐
│ 2. Execute giipscripts/auto-discover-linux.sh  │
├────────────────────────────────────────────────┤
│    ┌──────────────────────────────────────┐    │
│    │  Data Collection                     │    │
│    ├──────────────────────────────────────┤    │
│    │  • OS: CentOS Linux 7                │    │
│    │  • CPU: 1 cores - Intel Xeon        │    │
│    │  • Memory: 3 GB                      │    │
│    │  • Network: eth0 (20.196.193.155)   │    │
│    │  • Software: 37 packages (filtered)  │    │
│    │  • Services: 50 services             │    │
│    └──────────────────────────────────────┘    │
│                                                │
│    Output: JSON to stdout                      │
└────┬───────────────────────────────────────────┘
     │
     ▼
┌────────────────────────────────────────────────┐
│ 3. Capture JSON                                │
│    DISCOVERY_JSON=$("$DISCOVERY_SCRIPT" 2>&1)  │
└────┬───────────────────────────────────────────┘
     │
     ▼
┌────────────────────────────────────────────────┐
│ 4. Add agent_version metadata                  │
│    { ...data..., "agent_version": "1.72" }     │
└────┬───────────────────────────────────────────┘
     │
     ▼
┌────────────────────────────────────────────────┐
│ 5. POST to Azure Function (giipApiSk2)         │
│    curl -X POST "${apiaddrv2}" \               │
│      --data-urlencode "text=AgentAutoRegister" │
│      --data-urlencode "jsondata=$JSON"         │
│      --data-urlencode "sk=$sk"                 │
└────┬───────────────────────────────────────────┘
     │
     ▼
┌────────────────────────────────────────────────┐
│ Azure Function: giipApiSk2                     │
├────────────────────────────────────────────────┤
│ 1. Validate SK                                 │
│ 2. Parse jsondata (OPENJSON)                   │
│ 3. Call pApiAgentAutoRegisterBySk              │
└────┬───────────────────────────────────────────┘
     │
     ▼
┌────────────────────────────────────────────────┐
│ SQL Server: pApiAgentAutoRegisterBySk          │
├────────────────────────────────────────────────┤
│ 1. Validate SK → get usn                       │
│ 2. INSERT/UPDATE tLSvr (server info)           │
│ 3. DELETE old + INSERT new tLSvrNetwork        │
│ 4. UPDATE old + INSERT new tLSvrSoftware       │
│ 5. DELETE old + INSERT new tLSvrService        │
│ 6. Return: {"status":"ok","lssn":71174}        │
└────┬───────────────────────────────────────────┘
     │
     ▼
┌────────────────────────────────────────────────┐
│ 6. Process API Response                        │
│    if lssn="0" then extract and update config  │
│    else log success                            │
└────┬───────────────────────────────────────────┘
     │
     ▼
┌────────────────────────────────────────────────┐
│ 7. Log to /var/log/giip-auto-discover.log     │
│    [2025-10-28 11:00:39] SUCCESS: {"status":.. │
└────────────────────────────────────────────────┘
```

---

## 📊 책임 비교표

| 기능 | giip-auto-discover.sh | giipscripts/auto-discover-linux.sh |
|------|----------------------|-----------------------------------|
| **설정 파일 읽기** | ✅ giipAgent.cnf | ❌ 불필요 |
| **데이터 수집** | ❌ 위임 | ✅ 전담 |
| **JSON 생성** | ❌ 수신만 | ✅ 생성 |
| **API 호출** | ✅ curl | ❌ 관여 안함 |
| **로그 기록** | ✅ 파일 기록 | ❌ stdout만 |
| **LSSN 관리** | ✅ 자동 업데이트 | ❌ 몰라도 됨 |
| **에러 처리** | ✅ API 실패 처리 | ❌ 데이터만 |
| **독립 실행 가능** | ❌ 설정 필요 | ✅ 완전 독립 |
| **재사용성** | ❌ GIIP 전용 | ✅ 범용 |

---

## 🎁 설계의 장점

### 1. 재사용성 (Reusability)
```bash
# 다른 API로 전송 가능
DISCOVERY_JSON=$(./giipscripts/auto-discover-linux.sh)
curl -X POST "https://other-monitoring-system.com" -d "$DISCOVERY_JSON"

# 로컬 분석용
./giipscripts/auto-discover-linux.sh | jq . > daily-report.json
```

### 2. 테스트 용이성 (Testability)
```bash
# 데이터 수집만 테스트 (API 호출 없이)
./giipscripts/auto-discover-linux.sh | jq .software

# API 호출만 테스트 (Mock JSON 사용)
API_URL="${apiaddrv2}"
curl -X POST "$API_URL" \
  --data-urlencode "text=AgentAutoRegister" \
  --data-urlencode "jsondata=$(cat test-data.json)" \
  --data-urlencode "sk=$sk"
```

### 3. 디버깅 (Debugging)
```bash
# 문제 격리
./giipscripts/auto-discover-linux.sh  # JSON 생성 문제?
./giip-auto-discover.sh               # API 호출 문제?

# 각각 독립적으로 디버깅
```

### 4. 유지보수성 (Maintainability)
```bash
# 소프트웨어 필터 변경 → auto-discover-linux.sh만 수정
SERVICE_FILTER='nginx|mysql|...'

# API 엔드포인트 변경 → giip-auto-discover.sh만 수정
API_URL="${apiaddrv2}"

# 로그 포맷 변경 → giip-auto-discover.sh만 수정
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ..." >> "$LOG_FILE"
```

### 5. 확장성 (Extensibility)
```bash
# 플랫폼별 collector 추가 가능
giip-auto-discover.sh  # 공통 wrapper
├── giipscripts/
    ├── auto-discover-linux.sh      # CentOS, Ubuntu
    ├── auto-discover-windows.ps1   # Windows (Future)
    ├── auto-discover-macos.sh      # macOS (Future)
    └── auto-discover-docker.sh     # Container (Future)

# Wrapper가 OS 감지해서 적절한 collector 호출
```

### 6. 성능 최적화
```bash
# Parallel execution (미래 확장)
DISCOVERY_JSON=$("$DISCOVERY_SCRIPT" &)
OTHER_DATA=$(./giipscripts/check-compliance.sh &)
wait
# 두 스크립트 병렬 실행 가능
```

---

## 🔒 보안 고려사항

### 설정 파일 보호
```bash
# giipAgent.cnf는 민감 정보 포함 (sk, lssn)
chmod 600 /root/giipAgent.cnf
chown root:root /root/giipAgent.cnf

# Git에 커밋 금지
echo "giipAgent.cnf" >> .gitignore
```

### SK 노출 방지
```bash
# auto-discover-linux.sh는 SK 몰라도 됨
# → SK 노출 위험 최소화
# → 데이터 수집 스크립트를 GitHub에 안전하게 공개 가능
```

---

## 📝 로그 예시

### 성공 케이스
```bash
[2025-10-28 11:00:00] Starting auto-discovery...
[2025-10-28 11:00:01] Collected service-related packages: 37
[2025-10-28 11:00:01] Sending data to API v2 (giipApiSk2)...
[2025-10-28 11:00:02] SUCCESS: {"status":"ok","lssn":71174}
[2025-10-28 11:00:02] Auto-discovery completed
```

### 신규 서버 등록
```bash
[2025-10-28 10:00:00] Starting auto-discovery...
[2025-10-28 10:00:01] Collected service-related packages: 37
[2025-10-28 10:00:01] Sending data to API v2 (giipApiSk2)...
[2025-10-28 10:00:02] SUCCESS: {"status":"ok","lssn":71174}
[2025-10-28 10:00:02] Received LSSN: 71174
[2025-10-28 10:00:02] Updated giipAgent.cnf with LSSN: 71174
[2025-10-28 10:00:02] Auto-discovery completed
```

### 에러 케이스
```bash
[2025-10-28 12:00:00] Starting auto-discovery...
[2025-10-28 12:00:01] ERROR: Discovery script not found: /root/giipAgentLinux/giipscripts/auto-discover-linux.sh

[2025-10-28 13:00:00] Starting auto-discovery...
[2025-10-28 13:00:01] Collected service-related packages: 37
[2025-10-28 13:00:01] Sending data to API v2 (giipApiSk2)...
[2025-10-28 13:00:06] ERROR: API call failed with code 7
curl: (7) Failed to connect to giipfaw.azurewebsites.net port 443: Connection refused
```

---

## 🚀 배포 및 설치

### 1. 초기 설치
```bash
cd /root
git clone https://github.com/LowyShin/giipAgentLinux.git
cd giipAgentLinux

# 설정 파일 생성
cp ../giipAgent.cnf.template ../giipAgent.cnf
vi ../giipAgent.cnf  # sk, lssn 입력

# 실행 권한 부여
chmod +x giip-auto-discover.sh
chmod +x giipscripts/auto-discover-linux.sh
```

### 2. Cron 등록
```bash
crontab -e

# 5분마다 실행
*/5 * * * * /root/giipAgentLinux/giip-auto-discover.sh
```

### 3. 수동 테스트
```bash
# 데이터 수집만 확인
./giipscripts/auto-discover-linux.sh | jq .

# 전체 프로세스 실행
./giip-auto-discover.sh

# 로그 확인
tail -50 /var/log/giip-auto-discover.log
```

---

## 🔍 트러블슈팅

### 문제: JSON 생성 실패
```bash
# 원인 격리
./giipscripts/auto-discover-linux.sh

# 예상 원인: rpm/dpkg 명령 없음, systemctl 권한 부족
```

### 문제: API 호출 실패
```bash
# 원인 격리
echo '{"test":"data"}' > /tmp/test.json
curl -X POST "${apiaddrv2}" \
  --data-urlencode "text=AgentAutoRegister" \
  --data-urlencode "jsondata=$(cat /tmp/test.json)" \
  --data-urlencode "sk=$sk"

# 예상 원인: 네트워크, SK 오류, API 주소 잘못됨
```

### 문제: 데이터가 UI에 안 보임
```bash
# 1. 로그 확인
tail -50 /var/log/giip-auto-discover.log

# 2. API 응답 확인
# SUCCESS: {"status":"ok","lssn":71174} ← 정상
# SUCCESS: ← 비정상 (빈 응답)

# 3. DB 확인
SELECT * FROM tLSvrSoftware WHERE LSsn=71174 AND swDeldt IS NULL
SELECT * FROM tLSvrService WHERE LSsn=71174
```

---

## 📚 관련 문서

- [API Endpoints Comparison](../../giipfaw/docs/API_ENDPOINTS_COMPARISON.md)
- [Service Package Filter](SERVICE_PACKAGE_FILTER.md)
- [Security Checklist](../../giipdb/docs/SECURITY_CHECKLIST.md)

---

## ✅ Best Practices

1. **설정 파일 보안**
   ```bash
   # Git에 실제 설정 커밋 금지
   cp giipAgent.cnf ../giipAgent.cnf.production
   ln -s ../giipAgent.cnf.production giipAgent.cnf
   ```

2. **로그 모니터링**
   ```bash
   # Logrotate 설정
   /var/log/giip-auto-discover.log {
       daily
       rotate 7
       compress
       missingok
   }
   ```

3. **에러 알림**
   ```bash
   # Cron에 MAILTO 설정
   MAILTO=admin@example.com
   */5 * * * * /root/giipAgentLinux/giip-auto-discover.sh
   ```

4. **주기적 업데이트**
   ```bash
   # 매일 새벽 4시 git pull
   0 4 * * * cd /root/giipAgentLinux && git pull
   ```

---

## 📚 참고 문서

| 문서 | 용도 |
|------|------|
| [MODULAR_ARCHITECTURE.md](MODULAR_ARCHITECTURE.md) | 전체 모듈 아키텍처 |
| **[SHELL_COMPONENT_SPECIFICATION.md](SHELL_COMPONENT_SPECIFICATION.md)** | **lib/*.sh 개발 표준 (필수 읽기)** |
| [GIIPAGENT3_SPECIFICATION.md](GIIPAGENT3_SPECIFICATION.md) | giipAgent3.sh 전체 사양 |
| [GATEWAY_HANG_DIAGNOSIS.md](GATEWAY_HANG_DIAGNOSIS.md) | Discovery 통합 문제 진단 |
