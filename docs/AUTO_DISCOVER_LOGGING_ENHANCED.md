# Auto-Discover 로깅 강화 (옵션 B)

**작성일**: 2025-11-25  
**목적**: auto-discover가 실행되지 않는 원인 명확히 파악  
**상태**: 로깅 강화 완료  

---

## 📋 추가된 로깅 포인트

### 1️⃣ giipAgent3.sh - auto-discover 호출 단계 (9개 로깅 포인트)

**위치**: giipAgent3.sh [5.2] 섹션  
**목표**: auto-discover 실행 여부와 각 단계 진행 상황 추적

#### 로깅 포인트:
```
🟢 [5.2.1] auto-discover-linux.sh 찾음/못 찾음
✅ [5.2.1] auto-discover-linux.sh 발견 및 실행 시작
📋 [5.2.2] 실행 환경 정보 (LSSN, Hostname, OS, PID)
⏱️  [5.2.3] 실행 시작 시간
✅ [5.2.4] auto-discover 성공 완료
🕒 [5.2.5] 실행 종료 시간
📊 [5.2.6] 결과 파일 크기
💾 [5.2.7] 결과 KVS 저장 여부
📝 [5.2.8] 전체 결과 KVS 저장 완료
❌ [5.2.4] auto-discover 실패 (Timeout 또는 Exit Code)
📋 [5.2.5] 에러 로그 라인 수 및 미리보기
🧹 [5.2.9] 임시 파일 정리
```

#### KVS 저장 항목:
- `auto_discover_init` - 시작 정보
- `auto_discover_result` - 결과 상태 (SUCCESS/FAILED/TIMEOUT)
- `auto_discover_full_result` - 전체 JSON 결과
- `auto_discover_error_log` - 에러 로그
- `auto_discover_complete` - 완료 알림

---

### 2️⃣ auto-discover-linux.sh - 실행 로깅 강화

**위치**: 각 수집 단계  
**목표**: 어느 단계에서 문제가 발생하는지 파악

#### 로깅 포인트:
```
🟢 START       - 스크립트 시작 (PID, 시간)
📋 Parameters  - 수신한 파라미터 (LSSN, Hostname, OS)
📋 Step 1      - OS 정보 수집 중
✅ Step 1      - OS 정보 수집 완료
📋 Step 2      - CPU 정보 수집 중
✅ Step 2      - CPU 정보 수집 완료
📋 Step 3      - 메모리 정보 수집 중
✅ Step 3      - 메모리 정보 수집 완료
📋 Step 4      - Hostname 수집 중
✅ Step 4      - Hostname 수집 완료
📋 Step 5      - 네트워크 수집 중
📋 Step Final  - JSON 생성 중
📊 Statistics  - 수집 통계 (OS, CPU, Memory)
🌐 Network     - IP 주소 정보
📦 Inventory   - 인벤토리 수 (Network, Software, Services)
✅ COMPLETED   - 스크립트 완료 (PID, 시간)
🕒 Total execution time - 전체 실행 시간
```

---

## 🔍 진단 방법

### Step 1: KVS에서 auto-discover 관련 로그 조회

```powershell
# giipdb 디렉토리에서 실행

# 1️⃣ auto-discover 초기화 로그
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71174 -KFactor "auto_discover_init" -Hours 1

# 2️⃣ auto-discover 결과 로그
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71174 -KFactor "auto_discover_result" -Hours 1

# 3️⃣ auto-discover 전체 결과 (JSON)
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71174 -KFactor "auto_discover_full_result" -Hours 1

# 4️⃣ auto-discover 에러 로그
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71174 -KFactor "auto_discover_error_log" -Hours 1

# 5️⃣ auto-discover 완료 알림
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71174 -KFactor "auto_discover_complete" -Hours 1

# 6️⃣ 모든 auto-discover 관련 로그 요약
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71174 -Hours 0.5 -Summary | grep -i auto
```

### Step 2: 실시간 모니터링 (cron 실행 후)

cron에서 실행되는 giipAgent3.sh의 stderr를 확인:

```bash
# 서버에서:
# giipAgent3.sh가 다음 cycle에서 실행될 때까지 대기 후

# 최근 실행 로그 확인 (cron이 자동 기록)
grep giipAgent /var/log/syslog | tail -50

# 또는 직접 stderr 캡처 (수동 실행)
cd /opt/giip/agent/linux
bash giipAgent3.sh 2>&1 | grep -E "auto-discover|auto_discover|\[5\.2\]"
```

### Step 3: Discovery 로그와 비교

이전에 확인한 `discovery_collection_local` 로그와 함께 비교:

```powershell
# discovery_collection_local 상태 확인
pwsh .\mgmt\query-kvs-discovery-logs.ps1 -Hours 1 -Summary

# auto-discover 상태 확인
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71174 -KFactor "auto_discover_result" -Hours 1

# 비교:
# - auto_discover_result가 없음 → auto-discover 실행 안 됨
# - auto_discover_result = "TIMEOUT" → 60초 초과
# - auto_discover_result = "FAILED" → 실패 (exit code 확인)
# - discovery_collection_local과 시간 비교
```

---

## 📊 가능한 진단 결과

### 시나리오 1: auto-discover 호출 안 됨
**증상**:
- `auto_discover_init` 로그 없음
- `auto_discover_result` 로그 없음

**원인**:
- giipAgent3.sh가 GATEWAY 모드가 아님
- auto-discover-linux.sh 파일 없음
- 스크립트 경로 오류

**해결**:
- giipAgent.cnf 확인: `is_gateway=1` 설정 여부
- `giipscripts/auto-discover-linux.sh` 파일 존재 확인

---

### 시나리오 2: auto-discover 실행됨 (성공)
**증상**:
- `auto_discover_init` = "starting"
- `auto_discover_result` = "success"
- `auto_discover_full_result` = JSON 데이터

**해석**: ✅ **정상 작동 중**

---

### 시나리오 3: auto-discover Timeout
**증상**:
- `auto_discover_result` = "timeout"
- `timeout_seconds: 60`

**원인**:
- 시스템 정보 수집 중 hang
- 네트워크 문제로 인한 지연
- 디스크 느림

**해결**:
- timeout 값 증가 (giipAgent3.sh 라인: `timeout_seconds=60`)
- 또는 특정 수집 항목 비활성화 (auto-discover-linux.sh 수정)

---

### 시나리오 4: auto-discover 실패 (Exit Code)
**증상**:
- `auto_discover_result` = "failed"
- `exit_code: [숫자]`
- `auto_discover_error_log` 있음

**원인**: 에러 로그 미리보기 참고

**해결**: 에러 로그에 따라 대응

---

## 🔧 필요시 Timeout 조정

auto-discover가 timeout되면 값을 늘릴 수 있습니다:

**giipAgent3.sh 라인 251 수정**:
```bash
# 현재
timeout_seconds=60

# 변경 예시 (120초로 증가)
timeout_seconds=120
```

---

## 📌 다음 확인 단계

1. **최근 5분간 자동 실행 대기** (cron이 5분 주기)
2. **KVS 로그 확인** (위의 쿼리 실행)
3. **시나리오별 결과 해석**
4. **문제 발견 시 문서 공유** (분석 결과와 함께)

---

## 💾 저장된 코드 변경사항

### 파일 1: giipAgent3.sh
**라인**: ~250-320 (새로 추가된 [5.2] auto-discover 섹션)
**내용**: 
- auto-discover 스크립트 경로 확인
- 60초 timeout 적용
- 9개 로깅 포인트
- KVS 저장 (5개 항목)

### 파일 2: auto-discover-linux.sh
**라인**: ~1-20 (시작 부분), ~280-320 (끝 부분)
**내용**:
- 스크립트 시작/종료 로깅
- 각 수집 단계 로깅 (Step 1-5, Final)
- 통계 정보 로깅

---

## 🎯 기대 효과

이제 다음을 정확히 파악할 수 있습니다:

| 확인 항목 | 로그 | 비고 |
|----------|------|------|
| auto-discover 호출 여부 | `auto_discover_init` | 없으면 호출 안 됨 |
| 실행 완료 여부 | `auto_discover_result` | SUCCESS/FAILED/TIMEOUT |
| 실행 시간 | giipAgent3.sh 로그 | [5.2.3] ~ [5.2.5] |
| 어느 단계에서 문제 | auto-discover stderr | Step 1-5 | 
| 타임아웃 여부 | `auto_discover_result` | timeout_seconds 확인 |
| 정확한 에러 | `auto_discover_error_log` | 원인 파악 가능 |

---

## ⏰ 예상 일정

- **5분 후**: 첫 번째 로그 확인
- **10분 후**: 패턴 파악 (성공/실패)
- **15분 후**: 원인 규명 및 대응
- **이후**: 근본 원인 해결

