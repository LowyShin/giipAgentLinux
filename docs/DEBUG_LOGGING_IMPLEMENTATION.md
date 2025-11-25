# auto_discover KVS 저장 문제 진단용 DEBUG 로깅 구현

**작성일**: 2025-11-25  
**상태**: ✅ **구현 완료** - 모든 DEBUG 로깅이 giipAgent3.sh에 추가됨  
**목표**: auto_discover_complete는 기록되는데 auto_discover_init이 기록되지 않는 문제 진단

---

## 📍 적용된 로깅 위치 (5개)

### 1️⃣ DEBUG-로깅 #1: 환경 변수 검증 (라인 54-56)

**위치**: giipAgent3.sh 초기화 단계

```bash
# 🔴 [DEBUG-로깅 #1] 환경 변수 검증 (KVS 저장 실패 진단용)
echo "[giipAgent3.sh] 🔍 [DEBUG-1] SCRIPT_DIR=${SCRIPT_DIR}" >&2
echo "[giipAgent3.sh] 🔍 [DEBUG-1] LIB_DIR=${LIB_DIR}" >&2
```

**목적**: Agent 시작 시 기본 경로 변수가 올바르게 설정되었는지 확인

**예상 출력**:
```
[giipAgent3.sh] 🔍 [DEBUG-1] SCRIPT_DIR=/home/istyle/giipAgentLinux
[giipAgent3.sh] 🔍 [DEBUG-1] LIB_DIR=/home/istyle/giipAgentLinux/lib
```

---

### 2️⃣ DEBUG-로깅 #2: KVS 필수 변수 검증 (라인 137-140)

**위치**: LSvrGetConfig API 호출 후 (설정 로드 완료 단계)

```bash
# 🔴 [DEBUG-로깅 #2] KVS 필수 변수 검증
echo "[giipAgent3.sh] 🔍 [DEBUG-2] Validating KVS variables before auto-discover phase" >&2
echo "[giipAgent3.sh] 🔍 [DEBUG-2] sk=${sk:-(empty ❌)}" >&2
echo "[giipAgent3.sh] 🔍 [DEBUG-2] apiaddrv2=${apiaddrv2:-(empty ❌)}" >&2
echo "[giipAgent3.sh] 🔍 [DEBUG-2] apiaddrcode=${apiaddrcode:-(empty)}" >&2
```

**목적**: `kvs_put` 함수에 필수적인 변수(`$sk`, `$apiaddrv2`)가 설정되었는지 확인

**예상 출력**:
```
✅ 정상:
[giipAgent3.sh] 🔍 [DEBUG-2] sk=YWJjZDEyMzQ1Njc4OTBhYmNkZWY=
[giipAgent3.sh] 🔍 [DEBUG-2] apiaddrv2=https://giipfaw.azurewebsites.net/api/giipApiSk2
[giipAgent3.sh] 🔍 [DEBUG-2] apiaddrcode=Xxxxxxxxxxxx

❌ 실패:
[giipAgent3.sh] 🔍 [DEBUG-2] sk=(empty ❌)
[giipAgent3.sh] 🔍 [DEBUG-2] apiaddrv2=(empty ❌)
```

**진단**: 
- empty 표시 → LSvrGetConfig API 호출 실패 또는 응답 파싱 오류
- 변수 존재 → DEBUG-3 이상으로 진행

---

### 3️⃣ DEBUG-로깅 #3: 파일 존재 여부 상세 검증 (라인 305-313)

**위치**: auto-discover 단계 시작 시, 스크립트 파일 확인 전/후

```bash
# 🔴 [DEBUG-로깅 #3] 파일 존재 여부 상세 검증
echo "[giipAgent3.sh] 🔍 [DEBUG-3] BRANCH: auto-discover script check" >&2
echo "[giipAgent3.sh] 🔍 [DEBUG-3] Expected path: $auto_discover_script" >&2
echo "[giipAgent3.sh] 🔍 [DEBUG-3] File exists: $([ -f "$auto_discover_script" ] && echo 'YES ✅' || echo 'NO ❌')" >&2

if [ ! -f "$auto_discover_script" ]; then
    # ... if 블록 (파일 없음)
    echo "[giipAgent3.sh] 🔍 [DEBUG-3] Searched paths:" >&2
    echo "[giipAgent3.sh] 🔍 [DEBUG-3]   - Path 1: ${SCRIPT_DIR}/giipscripts/auto-discover-linux.sh" >&2
    echo "[giipAgent3.sh] 🔍 [DEBUG-3]   - Path 2: ${SCRIPT_DIR}/lib/giipscripts/auto-discover-linux.sh" >&2
else
    echo "[giipAgent3.sh] 🔍 [DEBUG-3] Script found, proceeding with execution" >&2
fi
```

**목적**: `auto-discover-linux.sh` 파일의 위치 및 존재 여부 확인

**예상 출력**:
```
✅ 파일 존재:
[giipAgent3.sh] 🔍 [DEBUG-3] Expected path: /home/istyle/giipAgentLinux/giipscripts/auto-discover-linux.sh
[giipAgent3.sh] 🔍 [DEBUG-3] File exists: YES ✅
[giipAgent3.sh] 🔍 [DEBUG-3] Script found, proceeding with execution

❌ 파일 없음:
[giipAgent3.sh] 🔍 [DEBUG-3] File exists: NO ❌
[giipAgent3.sh] 🔍 [DEBUG-3] Searched paths:
[giipAgent3.sh] 🔍 [DEBUG-3]   - Path 1: .../giipscripts/auto-discover-linux.sh
[giipAgent3.sh] 🔍 [DEBUG-3]   - Path 2: .../lib/giipscripts/auto-discover-linux.sh
```

**진단**:
- YES ✅ → else 블록으로 진행 (DEBUG-4, 5로 계속)
- NO ❌ → if 블록 진입 (failure kvs_put 호출)

---

### 4️⃣ DEBUG-로깅 #4: kvs_put 호출 전 최종 변수 검증 (라인 322-326)

**위치**: `kvs_put` 함수 호출 직전

```bash
# 🔴 [DEBUG-로깅 #4] kvs_put 호출 전 최종 변수 검증
echo "[giipAgent3.sh] 🔍 [DEBUG-4] BEFORE kvs_put auto_discover_init:" >&2
echo "[giipAgent3.sh] 🔍 [DEBUG-4]   sk length: ${#sk}" >&2
echo "[giipAgent3.sh] 🔍 [DEBUG-4]   apiaddrv2=${apiaddrv2:-(empty ❌)}" >&2
echo "[giipAgent3.sh] 🔍 [DEBUG-4]   kType=lssn, kKey=${lssn}, kFactor=auto_discover_init" >&2
```

**목적**: `kvs_put` 함수에 전달될 모든 파라미터와 환경 변수 상태 확인

**예상 출력**:
```
[giipAgent3.sh] 🔍 [DEBUG-4] BEFORE kvs_put auto_discover_init:
[giipAgent3.sh] 🔍 [DEBUG-4]   sk length: 64
[giipAgent3.sh] 🔍 [DEBUG-4]   apiaddrv2=https://giipfaw.azurewebsites.net/api/giipApiSk2
[giipAgent3.sh] 🔍 [DEBUG-4]   kType=lssn, kKey=71240, kFactor=auto_discover_init
```

**진단**:
- sk length ≥ 32 → 토큰 설정됨
- apiaddrv2 URL 보임 → API 엔드포인트 설정됨
- 모든 파라미터 보임 → kvs_put 호출 가능 상태

---

### 5️⃣ DEBUG-로깅 #5: kvs_put 호출 후 결과 검증 (라인 331-340)

**위치**: `kvs_put` 함수 호출 후 (가장 중요한 진단 정보)

```bash
# kvs_put 호출 (stderr 캡처 추가 ⭐)
kvs_put "lssn" "${lssn}" "auto_discover_init" "{\"status\":\"starting\",\"script_path\":\"${auto_discover_script}\",\"lssn\":${lssn},\"hostname\":\"${hn}\"}" 2>&1 | tee -a /tmp/kvs_put_debug_$$.log
kvs_put_result=$?

# 🔴 [DEBUG-로깅 #5] kvs_put 호출 후 결과 검증
echo "[giipAgent3.sh] 🔍 [DEBUG-5] AFTER kvs_put auto_discover_init:" >&2
echo "[giipAgent3.sh] 🔍 [DEBUG-5]   exit_code=$kvs_put_result (0=success, non-zero=failure)" >&2
if [ $kvs_put_result -ne 0 ]; then
    echo "[giipAgent3.sh] ❌ [DEBUG-5] ERROR: kvs_put FAILED!" >&2
    echo "[giipAgent3.sh] 🔍 [DEBUG-5] kvs_put stderr (last 20 lines):" >&2
    [ -f /tmp/kvs_put_debug_$$.log ] && tail -20 /tmp/kvs_put_debug_$$.log | sed 's/^/  [DEBUG-5] /' >&2
else
    echo "[giipAgent3.sh] ✅ [DEBUG-5] kvs_put SUCCESS" >&2
fi
```

**목적**: `kvs_put` 함수 호출의 성공/실패 여부 및 에러 정보 확인

**특징**:
- `2>&1` 추가: stderr을 stdout으로 리다이렉트
- `tee -a /tmp/kvs_put_debug_$$.log`: 동시에 파일에도 저장
- `tail -20`: 에러 메시지만 추출
- PID(`$$`)를 사용한 고유 파일명: 동시 실행 시 충돌 방지

**예상 출력** (성공):
```
[giipAgent3.sh] 🔍 [DEBUG-5] AFTER kvs_put auto_discover_init:
[giipAgent3.sh] 🔍 [DEBUG-5]   exit_code=0 (0=success, non-zero=failure)
[giipAgent3.sh] ✅ [DEBUG-5] kvs_put SUCCESS
```

**예상 출력** (실패):
```
[giipAgent3.sh] 🔍 [DEBUG-5] AFTER kvs_put auto_discover_init:
[giipAgent3.sh] 🔍 [DEBUG-5]   exit_code=1 (0=success, non-zero=failure)
[giipAgent3.sh] ❌ [DEBUG-5] ERROR: kvs_put FAILED!
[giipAgent3.sh] 🔍 [DEBUG-5] kvs_put stderr (last 20 lines):
  [DEBUG-5] [KVS-Put] ⚠️ Missing required variables (sk, apiaddrv2)
  [DEBUG-5] [KVS-Put] ⚠️ Failed (exit_code=7): Connection refused
```

---

## 🔄 실행 흐름 및 로깅 순서

```
라인 54-56    [DEBUG-1] 환경 변수 (SCRIPT_DIR, LIB_DIR)
    ↓ (초기화 완료)
라인 137-140  [DEBUG-2] KVS 변수 검증 (sk, apiaddrv2) ← LSvrGetConfig 후
    ↓ (변수 확인)
라인 305-313  [DEBUG-3] 파일 존재 여부 (auto-discover-linux.sh)
    ├─ YES ✅ → 라인 320+: else 블록
    │         ↓
    │         라인 322-326 [DEBUG-4] kvs_put 호출 전 (파라미터 확인)
    │         ↓
    │         라인 328: kvs_put 호출 + stderr 캡처
    │         ↓
    │         라인 331-340 [DEBUG-5] kvs_put 후 결과 확인
    │                     ✅ exit_code=0 → KVS 저장 성공!
    │                     ❌ exit_code≠0 → 에러 정보 출력
    │
    └─ NO ❌  → 라인 310+: if 블록
              ├─ kvs_put failure 호출
              └─ [DEBUG-3]에서 경로 정보 출력

라인 381: auto_discover_complete (항상 실행)
```

---

## 🔍 진단 방법

### 단계 1: 로그 수집

**서버에서 실행**:
```bash
bash /path/to/giipAgent3.sh 2>&1 | tee /tmp/giipAgent3_debug_$(date +%s).log
```

### 단계 2: DEBUG 메시지 확인

**모든 DEBUG 메시지 추출**:
```bash
grep "\[DEBUG" /tmp/giipAgent3_debug_*.log
```

**각 DEBUG별 상세 확인**:
```bash
# DEBUG-1~3
grep "\[DEBUG-[1-3]\]" /tmp/giipAgent3_debug_*.log

# DEBUG-4~5 (가장 중요)
grep "\[DEBUG-[4-5]\]" /tmp/giipAgent3_debug_*.log

# kvs_put 에러 로그 (파일로 저장된 것)
cat /tmp/kvs_put_debug_*.log
```

### 단계 3: KVS 확인

**최근 5분 로그 (전체)**:
```powershell
pwsh .\mgmt\check-latest.ps1 -Lssn 71240 -Minutes 5
```

**auto_discover_init만**:
```powershell
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71240 -KFactor "auto_discover_init" -Hours 0.1
```

---

## 📊 트러블슈팅 테이블

| DEBUG | 정상 신호 | 비정상 신호 | 대응 방법 |
|------|---------|----------|---------|
| #1 | SCRIPT_DIR=/home/.../giipAgentLinux | 경로가 비어있음 | 스크립트 실행 경로 확인 |
| #2 | sk=abc..., apiaddrv2=https://... | (empty ❌) | LSvrGetConfig API 실패 진단 |
| #3 | File exists: YES ✅ | File exists: NO ❌ | 파일 경로 및 권한 확인 |
| #4 | sk length: 32+, apiaddrv2=url | sk length: 0, apiaddrv2=(empty) | 변수 전달 오류 |
| #5 | exit_code=0, SUCCESS | exit_code=1, ERROR | kvs_put 에러 로그 확인 |

---

## 💾 생성되는 임시 파일

| 파일 | 목적 | 보존 기간 |
|------|------|---------|
| `/tmp/giipAgent3_debug_*.log` | 전체 Agent 실행 로그 | 수동 삭제 필요 |
| `/tmp/kvs_put_debug_$$.log` | kvs_put 함수의 stderr | 수동 삭제 필요 |

**정리 방법**:
```bash
# 오래된 로그 정리
rm -f /tmp/giipAgent3_debug_*.log
rm -f /tmp/kvs_put_debug_*.log

# 또는 1시간 이상 된 파일만 정리
find /tmp -name "giipAgent3_debug_*.log" -mtime +1 -delete
find /tmp -name "kvs_put_debug_*.log" -mtime +1 -delete
```

---

## 📌 요약

**적용 상태**: ✅ 완료 (5개 DEBUG 로깅 모두 추가됨)

**검증 프로세스**:
1. 로컬에서 stdout/stderr 출력으로 DEBUG 메시지 확인
2. `/tmp/kvs_put_debug_*.log` 파일로 kvs_put 에러 저장
3. PowerShell에서 KVS 쿼리로 최종 기록 확인

**기대 효과**:
- ✅ 환경 변수 설정 오류 → DEBUG-1, 2에서 즉시 파악
- ✅ 파일 경로 오류 → DEBUG-3에서 즉시 파악
- ✅ kvs_put 호출 실패 → DEBUG-5에서 에러 메시지 포함
- ✅ 임시 파일 저장 → 재현 불가능한 오류도 분석 가능

---

## 🔗 관련 문서

- [AUTO_DISCOVER_KVS_RECORDING_ISSUE.md](AUTO_DISCOVER_KVS_RECORDING_ISSUE.md) - 문제 분석
- [AUTO_DISCOVER_LOGGING_ENHANCED.md](AUTO_DISCOVER_LOGGING_ENHANCED.md) - 로깅 설계
- [KVS_STORAGE_STANDARD.md](KVS_STORAGE_STANDARD.md) - KVS 표준

---

## ✅ 체크리스트

진단 시 다음 항목을 확인하세요:

- [ ] `giipAgent3.sh` 실행 (로컬 서버)
- [ ] `grep "\[DEBUG"` 결과 5개 라인 모두 확인
- [ ] DEBUG-2에서 sk, apiaddrv2 변수 확인
- [ ] DEBUG-3에서 파일 존재 여부 확인
- [ ] DEBUG-5에서 kvs_put exit_code 확인
- [ ] `/tmp/kvs_put_debug_*.log` 파일 내용 확인
- [ ] `check-latest.ps1` 또는 `query-kvs.ps1`로 KVS 확인
- [ ] auto_discover_init 기록 여부 최종 확인

