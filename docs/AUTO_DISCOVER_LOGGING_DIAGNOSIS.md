# Auto-Discover 미실행 원인 진단 가이드

> ⚠️ **이 문서는 초기 진단 기록입니다.**
>
> 📌 **메인 문서**: [AUTO_DISCOVER_ISSUE_DIAGNOSIS_REPORT.md](./AUTO_DISCOVER_ISSUE_DIAGNOSIS_REPORT.md) ← 최신 진단 결과 확인
>
> 이 문서는 초기 진단 과정의 기록이며, 최신 정보는 메인 문서를 참조하세요.

**작성일**: 2025-11-23 (업데이트: 2025-11-25)  
**상태**: auto-discover가 실행되지 않음 (KVS discovery_collection_local만 경고 상태)  
**목표**: 로깅 강화를 통해 실제 원인 파악

---

## 🔗 **문서 간 링크**

| 문서 | 관계 | 링크 |
|------|------|------|
| **[GATEWAY_HANG_DIAGNOSIS.md](GATEWAY_HANG_DIAGNOSIS.md)** | 이 문서의 진입점 | 필수 읽기 문서 목록에 포함 |
| **[AUTO_DISCOVER_LOGGING_ENHANCED.md](AUTO_DISCOVER_LOGGING_ENHANCED.md)** | 진단 완료 후 읽기 | 로깅 구현 결과 |
| **[GATEWAY_KVS_MONITORING.md](GATEWAY_KVS_MONITORING.md)** | KVS 모니터링 | 진단을 위한 쿼리 도구 |
| **[AUTO_DISCOVERY_ARCHITECTURE.md](AUTO_DISCOVERY_ARCHITECTURE.md)** | 설계 배경 | Discovery 아키텍처 이해 |

---

## 🔗 로깅 강화 문서 (옵션 B 완료)

> ⚠️ **중요**: 먼저 이 문서를 읽으세요!

📄 **[AUTO_DISCOVER_LOGGING_ENHANCED.md](AUTO_DISCOVER_LOGGING_ENHANCED.md)**

- 실행 흐름도 (로깅 위치 명시)
- 26개 로깅 포인트 (실행 순서대로)
- 문제별 확인 포인트
- 실시간 진단 명령어

> 📌 **KVS 표준**: 모든 로깅은 [KVS_STORAGE_STANDARD.md](KVS_STORAGE_STANDARD.md)의 `kvs_put()` 함수 기반 표준을 따릅니다.

---

## 1. 현재 진단 결과

### 1.1 KVS 로그 상태
```
✅ discovery_collection_local: 진행 중 (exit_code: 1, warning)
   - LSSN: 71174
   - 최근: 2025/11/25 02:35:05
   - 상태: warning, exit_code: 1 (실패)

❌ LOCAL_EXECUTION: 없음
   - auto-discover 자체가 실행되지 않음
   - KVS 로그만으로는 원인 파악 불가
```

### 1.2 필요한 추가 정보
- **Discovery 수집은 진행** → 왜 auto-discover 단계로 진행되지 않는가?
- **exit_code: 1** → discovery_collection_local이 실패하는 이유는?
- **스케줄링 문제인가?** → auto-discover가 아예 호출되지 않는가?
- **권한/환경 문제인가?** → discovery_collection_local 실패와 연계?

---

## 2. 진단 방법 (3가지 옵션)

### 옵션 A: 기존 로그만 확인 (로깅 강화 없음)

**확인 방법:**
```bash
# LSSN 71174 서버의 실제 로그 파일 확인
ls -lah /var/log/giip*
tail -100f /var/log/giipAgent.log

# auto-discover 스크립트 로그 (있다면)
ls -lah /var/log/auto-discover*
tail -50f /var/log/auto-discover-linux.log

# cron 실행 로그
grep -i "auto-discover\|discovery" /var/log/cron
grep -i "auto-discover\|discovery" /var/log/syslog

# ps로 현재 실행 프로세스 확인
ps aux | grep -i auto-discover
ps aux | grep -i discovery
```

**확인 가능한 정보:**
- auto-discover 스크립트 실행 여부
- cron에서 호출되는지 여부
- 실패시 에러 메시지

**장점:** 즉시 확인 가능  
**단점:** 로그가 없으면 원인 파악 불가능

---

### 옵션 B: 로깅 강화 (권장)

**추가해야 할 로깅 포인트:**

#### 2.1 giipAgent.sh 또는 giipAgent3.sh에서 auto-discover 호출 부분

**현재 상태:**
- auto-discover 호출 시점의 로깅 부족
- 호출 성공/실패 판단 기준 불명확

**개선사항:**
```bash
# giipAgent.sh 또는 giipAgent3.sh에 다음 로깅 추가

# [추가] auto-discover 호출 전
LOG_MSG="[AUTO-DISCOVER] Starting auto-discover process (LSSN=$LSSN, Hostname=$HOSTNAME)"
write_kvs_log "giipagent" "auto_discover_init" "$LOG_MSG" "info"
echo "$(date '+%Y-%m-%d %H:%M:%S') - $LOG_MSG" >> "$LOGFILE"

# auto-discover 실행
/path/to/auto-discover-linux.sh "$@" 2>&1

# [추가] 실행 결과 로깅
AUTO_DISCOVER_EXIT_CODE=$?
if [ $AUTO_DISCOVER_EXIT_CODE -eq 0 ]; then
    LOG_MSG="[AUTO-DISCOVER] Completed successfully (exit_code: 0)"
    write_kvs_log "giipagent" "auto_discover_success" "$LOG_MSG" "info"
else
    LOG_MSG="[AUTO-DISCOVER] Failed with exit_code: $AUTO_DISCOVER_EXIT_CODE"
    write_kvs_log "giipagent" "auto_discover_failed" "$LOG_MSG" "error"
fi
echo "$(date '+%Y-%m-%d %H:%M:%S') - $LOG_MSG" >> "$LOGFILE"
```

**추가되는 KVS 로그:**
- `auto_discover_init` - auto-discover 호출 시작
- `auto_discover_success` - 완료 (exit_code: 0)
- `auto_discover_failed` - 실패 (exit_code: non-zero)

**확인 방법:**
```powershell
# PowerShell에서 확인
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71174 -KFactor "auto_discover" -Hours 1 -Summary
```

---

#### 2.2 discovery_collection_local 실패 원인 파악

**현재 문제:**
```
discovery_collection_local: exit_code: 1 (warning)
```

**필요한 로깅:**
```bash
# discovery_collection_local 실행 스크립트에 추가

DISCOVERY_COLLECTION_LOG="/var/log/discovery_collection_$(date +%Y%m%d_%H%M%S).log"

# [추가] 실행 전 상태 로깅
{
    echo "=== Discovery Collection Local Started ==="
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "LSSN: $LSSN"
    echo "Hostname: $HOSTNAME"
    echo "Current User: $(whoami)"
    echo "Working Directory: $(pwd)"
    echo "Disk Space:"
    df -h /
    echo "Network Status:"
    netstat -an | grep -E "ESTABLISHED|LISTEN" | head -20
} > "$DISCOVERY_COLLECTION_LOG"

# 실제 수집 작업 실행
perform_discovery_collection >> "$DISCOVERY_COLLECTION_LOG" 2>&1
COLLECTION_EXIT_CODE=$?

# [추가] 실행 결과 로깅
{
    echo ""
    echo "=== Discovery Collection Local Completed ==="
    echo "Exit Code: $COLLECTION_EXIT_CODE"
    echo "End Time: $(date '+%Y-%m-%d %H:%M:%S')"
} >> "$DISCOVERY_COLLECTION_LOG"

# KVS에도 상세 로깅
if [ $COLLECTION_EXIT_CODE -eq 0 ]; then
    write_kvs_log "giipagent" "discovery_collection_local" \
        "$(cat $DISCOVERY_COLLECTION_LOG | head -50)" "success"
else
    write_kvs_log "giipagent" "discovery_collection_local" \
        "$(tail -50 $DISCOVERY_COLLECTION_LOG)" "error"
fi
```

**추가되는 정보:**
- 실행 시간, 사용자, 권한
- 디스크 상태, 네트워크 상태
- 수집 실패시 상세 에러 메시지

---

#### 2.3 Auto-discover 스케줄링 확인

**현재 상태:** cron 또는 다른 스케줄러에서 호출 여부 불명확

**필요한 로깅:**
```bash
# /etc/cron.d/giip-agent 또는 crontab에 다음 추가

# [기존] 
# */5 * * * * /path/to/giipAgent.sh

# [개선]
# */5 * * * * /path/to/giipAgent.sh 2>&1 | tee -a /var/log/giip-cron-$(date +\%Y\%m\%d).log

# 또는 wrapper 스크립트 사용:
# /usr/local/bin/giip-agent-wrapper.sh
```

**wrapper 스크립트 예시:**
```bash
#!/bin/bash
# /usr/local/bin/giip-agent-wrapper.sh

WRAPPER_LOG="/var/log/giip-agent-wrapper.log"

{
    echo "==============================================="
    echo "Cron Execution: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Current User: $(whoami)"
    echo "Process ID: $$"
    echo "Environment: $(env | head -20)"
    echo "---"
    /path/to/giipAgent.sh "$@"
    EXIT_CODE=$?
    echo "---"
    echo "Exit Code: $EXIT_CODE"
    echo "End Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "==============================================="
} >> "$WRAPPER_LOG" 2>&1

exit $EXIT_CODE
```

**확인 방법:**
```bash
tail -200f /var/log/giip-cron-$(date +%Y%m%d).log
cat /var/log/giip-agent-wrapper.log | grep -A 20 "auto-discover"
```

---

### 옵션 C: 코드 수정 (직접 해결)

**근본 원인 추측:**

1. **auto-discover가 조건부로 실행된다**
   ```bash
   # giipAgent.sh에서 (추측)
   if [ condition_for_auto_discover ]; then
       run_auto_discover
   fi
   ```
   **해결:** 조건 확인 및 항상 실행하거나 조건 수정

2. **discovery_collection_local 실패로 인해 다음 단계 스킵**
   ```bash
   # 실행 순서 (추측)
   run_discovery_collection_local || exit  # 실패하면 종료
   run_auto_discover  # 여기에 도달하지 못함
   ```
   **해결:** discovery_collection_local 실패 원인 제거

3. **환경 변수 또는 권한 문제**
   - LSSN 71174에서 실행되는 auto-discover에 필요한 권한 부족
   - 필요한 환경 변수 미설정
   **해결:** 권한 및 환경 변수 확인

---

## 3. 추천 진단 순서

### Step 1: 로그 파일 직접 확인 (5분)
```bash
# LSSN 71174 (p-infraops01 또는 해당 서버) SSH 접속 후
ssh infraops01.istyle.local
cd /var/log

# 가장 최근 로그 확인
tail -100f giipAgent.log
tail -50f auto-discover*.log

# 지난 1시간 로그 확인
grep -E "auto.discover|AUTO.DISCOVER|discovery_collection" giipAgent.log | tail -50
```

**예상 결과:**
- `auto-discover 호출 메시지` → auto-discover가 실행됨
- `no log` → auto-discover가 호출되지 않음 (원인 파악 필요)

### Step 2: Cron 스케줄 확인 (3분)
```bash
# 현재 cron 설정 확인
crontab -l
cat /etc/cron.d/giip*

# cron 실행 로그 확인
tail -50f /var/log/cron
grep giip /var/log/syslog | tail -50
```

**예상 결과:**
- cron 실행 기록 있음 → 스케줄 정상
- cron 실행 기록 없음 → 스케줄 비활성화 또는 에러

### Step 3: 권한 및 환경 확인 (5분)
```bash
# giipAgent.sh 실행 권한
ls -lah /path/to/giipAgent.sh

# 필요한 환경 변수 확인
grep -E "export|LSSN|HOSTNAME" giipAgent.sh | head -20

# 수동으로 실행해보기
bash -x /path/to/giipAgent.sh 2>&1 | grep -i "auto-discover\|discovery"
```

### Step 4: 로깅 강화 적용 (10분)
위의 "옵션 B" 로깅 추가를 적용하고 다음 실행 결과 대기

---

## 4. 각 시나리오별 해결 방법

### 시나리오 1: auto-discover 호출 안 됨
**증상:** auto-discover 관련 로그 전혀 없음

**원인:** 
- 조건부 실행 조건이 FALSE
- auto-discover 함수/스크립트 경로 오류
- 스케줄러에서 호출되지 않음

**해결:**
```bash
# 1. giipAgent.sh에서 auto-discover 호출 부분 찾기
grep -n "auto.discover\|AUTO.DISCOVER" giipAgent.sh

# 2. 조건 확인
# if [ "$RUN_AUTO_DISCOVER" == "true" ]; then
#     이 조건이 FALSE라면 이유 파악

# 3. 강제 실행으로 테스트
bash /path/to/giipAgent.sh --force-auto-discover
```

---

### 시나리오 2: discovery_collection_local 실패로 인해 차단
**증상:** discovery_collection_local exit_code: 1

**원인:**
- 디스크 공간 부족
- 네트워크 연결 실패
- DB 연결 실패
- 권한 문제

**해결:**
```bash
# discovery_collection_local 단독 실행
bash -x /path/to/discovery_collection_local.sh 2>&1

# 또는 함수가 embedded라면:
source /path/to/giipAgent.sh
discovery_collection_local 2>&1 | tee /tmp/discovery_debug.log
```

---

### 시나리오 3: auto-discover 실행되지만 실패
**증상:** auto_discover_failed 로그 or LOCAL_EXECUTION exit_code: non-zero

**원인:**
- auto-discover 스크립트 오류
- 필요한 환경 변수 미설정
- 원격 서버 연결 실패

**해결:**
```bash
# auto-discover 로그 확인
tail -100f /var/log/auto-discover-linux.log

# 상세 debug로 실행
bash -x /path/to/auto-discover-linux.sh 2>&1 | tee /tmp/auto-discover-debug.log
```

---

## 5. 로깅 강화 후 확인 방법

### KVS 쿼리로 진행 상황 모니터링
```powershell
# PowerShell (giipdb 디렉토리)

# 5분마다 실행되는 auto-discover 추적
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71174 -KFactor "auto_discover" -Hours 0.5 -Summary

# 실패한 단계 추적
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71174 -KFactor "discovery_collection_local" -Hours 0.5 -Top 3

# 결과 확인
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71174 -Hours 0.5 -Summary
```

### 로그 파일로 상세 추적
```bash
# 실시간 모니터링
watch -n 5 'tail -20 /var/log/giipAgent.log | grep -E "auto.discover|discovery_collection"'

# 최근 1시간 통계
awk '/auto.discover|discovery_collection/ {print $0}' /var/log/giipAgent.log | tail -50
```

---

## 6. 최종 체크리스트

```
[ ] Step 1: 서버 SSH 접속 및 로그 파일 확인
[ ] Step 2: auto-discover 호출 로그 유무 확인
[ ] Step 3: cron 스케줄 및 실행 여부 확인
[ ] Step 4: discovery_collection_local 실패 원인 파악
[ ] Step 5: 필요시 로깅 강화 코드 적용
[ ] Step 6: KVS 로그로 진행 상황 모니터링
[ ] Step 7: 해결 방법 적용 및 재실행
[ ] Step 8: 최소 3 사이클(15분) 모니터링하여 정상 작동 확인
```

---

## 부록: 추가 참고 자료

### 관련 로그 조회 스크립트
- `query-kvs-auto-discover-status.ps1` - auto-discover 실행 상태 조회
- `query-kvs-discovery-logs.ps1` - Discovery 로그 조회
- `check-latest.ps1` - 최근 5분 Gateway 로그 조회

### 수정 대상 파일들
- `giipAgent.sh` 또는 `giipAgent3.sh` - auto-discover 호출 부분
- `auto-discover-linux.sh` - auto-discover 스크립트
- discovery_collection 관련 스크립트
- crontab 또는 `/etc/cron.d/giip-*`

### KVS 신규 로그 타입 제안
- `auto_discover_init` - auto-discover 호출 시작
- `auto_discover_success` - auto-discover 완료 성공
- `auto_discover_failed` - auto-discover 완료 실패
- `discovery_collection_detail` - discovery_collection 상세 에러

