# auto_discover KVS 저장 문제 진단 - 로깅 구현 완료

**작성일**: 2025-11-25  
**상태**: ✅ **구현 완료**  
**대상**: LSSN 71240 auto_discover_init 미기록 문제 진단

---

## 📋 구현 요약

### 문제 상황
```
✅ auto_discover_complete (KVS에 기록됨)
❌ auto_discover_init (KVS에 기록 안 됨)
❌ auto_discover_result (KVS에 기록 안 됨)
❌ auto_discover_error_log (KVS에 기록 안 됨)
```

### 원인 추정
`auto_discover_complete` 만 라인 381에서 항상 실행되는데, 중간 로깅이 모두 else 블록 내부(라인 320-379)에 있음
→ **kvs_put 함수 호출 실패 또는 변수 미설정**

---

## ✅ 적용된 DEBUG 로깅 (5개)

| # | 라인 | 검증 항목 | 파일 |
|---|-----|---------|------|
| 1 | 54-56 | 환경 변수 (SCRIPT_DIR, LIB_DIR) | giipAgent3.sh |
| 2 | 137-140 | KVS 필수 변수 (sk, apiaddrv2) | giipAgent3.sh |
| 3 | 305-318 | auto-discover-linux.sh 파일 존재 | giipAgent3.sh |
| 4 | 322-326 | kvs_put 호출 전 파라미터 | giipAgent3.sh |
| 5 | 328-340 | kvs_put 호출 후 결과 및 stderr | giipAgent3.sh |

---

## 🚀 실행 방법

### 1단계: 서버에서 로그 수집
```bash
# 서버 LSSN 71240에서 실행
bash /path/to/giipAgent3.sh 2>&1 | tee /tmp/giipAgent3_debug_$(date +%s).log
```

### 2단계: DEBUG 메시지 확인
```bash
# 모든 DEBUG 메시지 추출
grep "\[DEBUG" /tmp/giipAgent3_debug_*.log

# 또는 각 DEBUG별로
grep "\[DEBUG-1\]" /tmp/giipAgent3_debug_*.log  # 환경 변수
grep "\[DEBUG-2\]" /tmp/giipAgent3_debug_*.log  # KVS 변수
grep "\[DEBUG-3\]" /tmp/giipAgent3_debug_*.log  # 파일 확인
grep "\[DEBUG-4\]" /tmp/giipAgent3_debug_*.log  # kvs_put 전
grep "\[DEBUG-5\]" /tmp/giipAgent3_debug_*.log  # kvs_put 후 (중요!)
```

### 3단계: kvs_put 에러 로그 확인
```bash
# DEBUG-5에서 /tmp/kvs_put_debug_*.log 파일이 생성됨
# 실패 시 이 파일에 에러 메시지 저장됨
cat /tmp/kvs_put_debug_*.log
```

### 4단계: KVS 최종 확인 (5분 기다린 후)
```powershell
# PowerShell (giipdb 디렉토리)
pwsh .\mgmt\check-latest.ps1 -Lssn 71240

# 또는 auto_discover_init만 확인
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71240 -KFactor "auto_discover_init" -Hours 0.1
```

---

## 📊 예상 출력

### ✅ 정상 흐름
```
[giipAgent3.sh] 🔍 [DEBUG-1] SCRIPT_DIR=/home/istyle/giipAgentLinux
[giipAgent3.sh] 🔍 [DEBUG-1] LIB_DIR=/home/istyle/giipAgentLinux/lib
[giipAgent3.sh] 🔍 [DEBUG-2] sk=YWJjZDEyMzQ1Njc4...
[giipAgent3.sh] 🔍 [DEBUG-2] apiaddrv2=https://giipfaw.azurewebsites.net/api/giipApiSk2
[giipAgent3.sh] 🔍 [DEBUG-3] File exists: YES ✅
[giipAgent3.sh] 🔍 [DEBUG-3] Script found, proceeding with execution
[giipAgent3.sh] 🔍 [DEBUG-4] sk length: 64
[giipAgent3.sh] 🔍 [DEBUG-4] apiaddrv2=https://giipfaw.azurewebsites.net/api/giipApiSk2
[giipAgent3.sh] 🔍 [DEBUG-5] exit_code=0 (0=success, non-zero=failure)
[giipAgent3.sh] ✅ [DEBUG-5] kvs_put SUCCESS

→ KVS: auto_discover_init ✅ 기록됨
```

### ❌ 실패 흐름 - 원인: DEBUG-2에서 변수 미설정
```
[giipAgent3.sh] 🔍 [DEBUG-1] SCRIPT_DIR=/home/istyle/giipAgentLinux
[giipAgent3.sh] 🔍 [DEBUG-1] LIB_DIR=/home/istyle/giipAgentLinux/lib
[giipAgent3.sh] 🔍 [DEBUG-2] sk=(empty ❌)
[giipAgent3.sh] 🔍 [DEBUG-2] apiaddrv2=(empty ❌)

→ 해결: LSvrGetConfig API 호출 실패
  - DB 연결 확인
  - 네트워크 연결 확인
  - API 엔드포인트 확인 (giipAgent.cnf)
```

### ❌ 실패 흐름 - 원인: DEBUG-3에서 파일 없음
```
[giipAgent3.sh] 🔍 [DEBUG-3] File exists: NO ❌
[giipAgent3.sh] 🔍 [DEBUG-3] Searched paths:
[giipAgent3.sh] 🔍 [DEBUG-3]   - Path 1: /home/istyle/giipAgentLinux/giipscripts/auto-discover-linux.sh
[giipAgent3.sh] 🔍 [DEBUG-3]   - Path 2: /home/istyle/giipAgentLinux/lib/giipscripts/auto-discover-linux.sh

→ 해결: 파일 경로 확인
  find /home -name "auto-discover-linux.sh" 2>/dev/null
```

### ❌ 실패 흐름 - 원인: DEBUG-5에서 kvs_put 실패
```
[giipAgent3.sh] 🔍 [DEBUG-4] sk length: 64
[giipAgent3.sh] 🔍 [DEBUG-4] apiaddrv2=https://...
[giipAgent3.sh] 🔍 [DEBUG-5] exit_code=1 (0=success, non-zero=failure)
[giipAgent3.sh] ❌ [DEBUG-5] ERROR: kvs_put FAILED!
[giipAgent3.sh] 🔍 [DEBUG-5] kvs_put stderr (last 20 lines):
  [DEBUG-5] [KVS-Put] ⚠️ Failed (exit_code=7): Connection refused

→ 해결: API 연결 오류
  - 인터넷 연결 확인
  - Azure Function App 상태 확인
  - 방화벽 규칙 확인
  
  또는 /tmp/kvs_put_debug_*.log 파일 내용 확인
```

---

## 🔍 진단 의사결정 트리

```
시작: giipAgent3.sh 실행
  ↓
1️⃣ DEBUG-1, DEBUG-2 확인
  ├─ sk 또는 apiaddrv2가 empty?
  │  ├─ YES: LSvrGetConfig API 실패 → DB 연결 확인
  │  └─ NO: 계속
  ↓
2️⃣ DEBUG-3 확인
  ├─ File exists: NO?
  │  ├─ YES: auto-discover-linux.sh 파일 경로 오류
  │  └─ NO: 계속
  ↓
3️⃣ DEBUG-5 확인
  ├─ ERROR: kvs_put FAILED?
  │  ├─ exit_code=1: 변수 미설정 또는 API 연결 오류
  │  ├─ exit_code=7: 네트워크 연결 거부
  │  ├─ exit_code=124: Timeout
  │  └─ /tmp/kvs_put_debug_*.log 에러 로그 확인
  ├─ SUCCESS?
  │  └─ YES: KVS에서 auto_discover_init 확인
  ↓
4️⃣ KVS 조회
  ├─ auto_discover_init 있음?
  │  ├─ YES: 성공! 문제 없음
  │  └─ NO: KVS API 저장 자체 오류
```

---

## 📁 관련 파일

| 파일 | 목적 | 상태 |
|------|------|------|
| `giipAgent3.sh` | DEBUG 로깅 구현 | ✅ 완료 (라인 54-56, 137-140, 305-318, 322-340) |
| `DEBUG_LOGGING_IMPLEMENTATION.md` | 로깅 상세 설명 | ✅ 완료 |
| `AUTO_DISCOVER_KVS_RECORDING_ISSUE.md` | 문제 분석 | ✅ 완료 |
| `AUTO_DISCOVER_LOGGING_ENHANCED.md` | 로깅 설계 | ✅ 기존 |
| `GATEWAY_HANG_DIAGNOSIS.md` | 최상위 진입점 | ✅ 기존 |

---

## 💡 주요 기능

### stderr 캡처 (⭐ 핵심)
```bash
# 기존 (에러 정보 손실):
kvs_put "lssn" "${lssn}" "auto_discover_init" "{...}"

# 개선 (에러 정보 보존):
kvs_put "lssn" "${lssn}" "auto_discover_init" "{...}" 2>&1 | tee -a /tmp/kvs_put_debug_$$.log
```

### PID 기반 고유 파일명
```bash
# 동시 실행 시에도 파일 충돌 방지
/tmp/kvs_put_debug_12345.log  # PID=12345
/tmp/kvs_put_debug_12346.log  # PID=12346
```

### tail + sed로 에러만 추출
```bash
# kvs_put 함수의 stderr 마지막 20줄만 출력
tail -20 /tmp/kvs_put_debug_$$.log | sed 's/^/  [DEBUG-5] /' >&2
```

---

## 🎯 다음 단계

1. **서버에서 테스트**:
   ```bash
   bash /path/to/giipAgent3.sh 2>&1 | grep "\[DEBUG"
   ```

2. **DEBUG 메시지 분석**:
   - DEBUG-1~3: 경로, 변수, 파일 확인
   - DEBUG-5: kvs_put 결과 확인

3. **KVS 확인**:
   ```powershell
   pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71240 -KFactor "auto_discover_init" -Hours 0.1
   ```

4. **문제 해결**:
   - 진단 트리에 따라 원인별 해결책 적용

---

## ⚠️ 주의사항

1. **stderr 출력**: DEBUG 메시지는 stderr(>&2)로 출력되므로 `2>&1`로 리다이렉트 필요
2. **임시 파일**: `/tmp/kvs_put_debug_*.log` 수동 정리 필요
3. **보안**: API 토큰($sk)이 로그에 포함될 수 있으니 민감한 환경에서는 주의

---

## 📞 지원

**질문사항**:
- [DEBUG_LOGGING_IMPLEMENTATION.md](DEBUG_LOGGING_IMPLEMENTATION.md) - 각 로깅의 상세 설명
- [AUTO_DISCOVER_KVS_RECORDING_ISSUE.md](AUTO_DISCOVER_KVS_RECORDING_ISSUE.md) - 문제 분석
- [AUTO_DISCOVER_LOGGING_ENHANCED.md](AUTO_DISCOVER_LOGGING_ENHANCED.md) - 설계 배경

