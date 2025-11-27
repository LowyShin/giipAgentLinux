# Auto-Discover 문제 시각화 및 해결책

> ⚠️ **이 문서는 문제 시각화 분석 기록입니다.**
>
> 📌 **메인 문서**: [AUTO_DISCOVER_ISSUE_DIAGNOSIS_REPORT.md](./AUTO_DISCOVER_ISSUE_DIAGNOSIS_REPORT.md) ← 최신 진단 결과 확인
>
> 이 문서는 문제를 시각화한 분석 자료이며, 최신 정보는 메인 문서를 참조하세요.

**작성**: 2025-11-26  
**기반**: KVS 실제 데이터 분석  
**상태**: 🔴 원인 명확히 파악됨

---

## 🔍 STEP별 상태 다이어그램

```
┌─────────────────────────────────────────────────────────────────┐
│ LSSN 71240 - auto-discover 실행 흐름                            │
│ 시간: 2025-11-26 12:15:03 ~ 12:15:08 (5초)                     │
└─────────────────────────────────────────────────────────────────┘

⏱️  12:15:03: giipAgent 시작 (startup ✅)
        ↓
⏱️  12:15:04: gateway_init (✅)
        ↓
⏱️  12:15:04: STEP-1 Configuration Check
        ├─ 필수 변수 확인
        │  ├─ sk: 설정됨 (length=32) ✅
        │  ├─ apiaddrv2: 설정됨 ✅
        │  └─ lssn: 71240 ✅
        └─ 결과: 저장됨 ✅
        ↓
⏱️  12:15:04: STEP-2 Script Path Check
        ├─ 찾는 경로:
        │  /home/shinh/scripts/infraops01/giipAgentLinux/lib/lib/giipscripts/auto-discover-linux.sh
        │                                                   ↑  ↑
        │                                                lib 중복! ❌
        ├─ exists: false ❌
        ├─ 오류: "auto-discover script not found"
        └─ 결과: 저장됨 ✅ (오류도 함께)
        ↓
⏱️  12:15:05: STEP-3 Initialize KVS Records
        ├─ 상태: STEP-2 오류 무시하고 계속 진행
        ├─ 동작: Initialize marker 저장
        └─ 결과: 저장됨 ✅ (⚠️ 하지만 실제로는 실패 상태)
        ↓
⏱️  12:15:05: STEP-4 Execute Auto-Discover Script
        ├─ 실행 대상:
        │  /home/shinh/scripts/infraops01/giipAgentLinux/lib/lib/giipscripts/auto-discover-linux.sh
        │  (잘못된 경로)
        ├─ 결과: exit_code = 127 ❌
        │  (127 = "command not found" / "No such file or directory")
        ├─ error_log: "" (비어있음)
        ├─ stderr 출력: (캡처되지 않음)
        └─ 오류 저장됨 ✅ (exit_code와 함께)
        ↓
⏱️  12:15:06: STEP-5 Validate Result File
        ├─ 기대 파일: /tmp/auto_discover_result_8074.json
        ├─ 실제: 파일 없음 (STEP-4 실패했으므로)
        ├─ 오류: "Result file is empty or does not exist"
        └─ 오류 저장됨 ✅
        ↓
⏱️  12:15:07: STEP-6 Store Result to KVS
        ├─ 저장할 데이터: (없음)
        ├─ file_size: 0 ❌
        └─ 결과: 저장됨 ✅ (하지만 데이터 없음)
        ↓
⏱️  12:15:08: STEP-7 Store Complete Marker
        ├─ 상태: COMPLETED (무조건)
        ├─ all_steps: "PASSED" ⚠️ (거짓!)
        └─ 결과: 저장됨 ✅ (잘못된 상태)
        ↓
⏱️  12:15:08: COMPLETE: Auto-Discover Phase Complete
        ├─ 표시: "PASSED" ⚠️ (실제로는 FAILED)
        └─ 결과: 저장됨 ✅ (거짓 상태)
```

---

## 📊 KVS 저장 상태 비교

### ✅ 저장된 것 (STEPS 1-7)

```json
✅ auto_discover_step_1_config
{
  "step": "STEP-1",
  "name": "Configuration Check",
  "data": {
    "lssn": 71240,
    "sk_length": 32,         ← ✅ 설정됨
    "apiaddrv2_set": true    ← ✅ 설정됨
  }
}

✅ auto_discover_step_2_scriptpath
{
  "step": "STEP-2",
  "name": "Script Path Check",
  "data": {
    "path": "...lib/lib/giipscripts/auto-discover-linux.sh",  ← ❌ 경로 오류
    "exists": false          ← ❌ 파일 없음
  }
}

✅ auto_discover_error_log (STEP-2)
{
  "step": "STEP-2",
  "type": "SCRIPT_NOT_FOUND",
  "message": "auto-discover script not found",
  "context": {
    "searched_path_1": ".../lib/giipscripts/...",
    "searched_path_2": ".../lib/lib/giipscripts/..."   ← ❌ 둘 다 오류
  }
}

✅ auto_discover_error_log (STEP-4)
{
  "step": "STEP-4",
  "type": "SCRIPT_EXECUTION_FAILED",
  "message": "Script failed with non-zero exit code",
  "context": {
    "exit_code": 127,        ← ❌ "command not found"
    "error_log": ""          ← ⚠️ 상세 오류 없음
  }
}
```

### ❌ 저장되지 않은 것

```
❌ auto_discover_init
   의도: 발견 프로세스 시작 (첫 로그)
   현재: 저장되지 않음
   이유: STEP-3 이전에 오류가 있어도 무시됨

❌ auto_discover_result
   의도: 최종 발견 결과 (수집한 데이터)
   현재: 저장되지 않음
   이유: STEP-4 실패 → 결과 파일 미생성

❌ 수집된 서버 정보 (OS, 디스크, 네트워크 등)
   의도: 인프라 정보 저장
   현재: 저장되지 않음
   이유: 스크립트가 실행되지 않았음
```

---

## 🎯 **핵심 문제: 경로 오류 추적**

### 의심되는 코드 위치

**giipAgent3.sh에서 경로 생성 부분**:

```bash
# ❌ 잘못된 코드 (추측)
SCRIPT_DIR="./lib"  # 또는 다른 경로 설정
auto_discover_script="${SCRIPT_DIR}/lib/giipscripts/auto-discover-linux.sh"
                              ↑ 여기서 lib이 이미 포함되었는데 또 추가됨!

# 결과 경로:
# /home/shinh/scripts/infraops01/giipAgentLinux/lib/lib/giipscripts/auto-discover-linux.sh
                                                       ↑ lib 중복
```

### 가능한 원인들

#### 원인 1: SCRIPT_DIR 설정 오류
```bash
# ❌ 잘못된 설정
SCRIPT_DIR="${base_dir}/lib"
# 그 후
auto_discover_script="${SCRIPT_DIR}/lib/giipscripts/..."  # lib 중복!

# ✅ 올바른 설정
SCRIPT_DIR="${base_dir}"
auto_discover_script="${SCRIPT_DIR}/lib/giipscripts/..."  # 한 번만!
```

#### 원인 2: 경로 재정의 오류
```bash
# ❌ 문제 코드
if [ ! -d "${SCRIPT_DIR}/lib" ]; then
    SCRIPT_DIR="${SCRIPT_DIR}/lib"  # 이미 lib이 있으면 또 추가됨!
fi
```

#### 원인 3: 상대 경로 문제
```bash
# ❌ 현재 위치에 따라 결과가 다름
cd /home/shinh/scripts/infraops01
bash giipAgentLinux/giipAgent3.sh
# 결과: lib/lib이 될 수 있음

# ✅ 절대 경로 사용
bash /home/shinh/scripts/infraops01/giipAgentLinux/giipAgent3.sh
```

---

## 🔧 해결책 (3가지 옵션)

### Option 1: 경로 검증 강화 (추천)

```bash
# giipAgent3.sh에서

# 현재 경로 출력
echo "[DEBUG] Base directory: ${base_dir}" >&2

# 경로 변수 한 번에 설정
SCRIPT_DIR="${base_dir}/giipAgentLinux"  # lib 없음!
auto_discover_script="${SCRIPT_DIR}/lib/giipscripts/auto-discover-linux.sh"

# 검증
if [ ! -f "$auto_discover_script" ]; then
    echo "[ERROR] Script not found: $auto_discover_script" >&2
    # 두 번째 경로 시도
    auto_discover_script="${SCRIPT_DIR}/giipscripts/auto-discover-linux.sh"
    if [ ! -f "$auto_discover_script" ]; then
        echo "[ERROR] Script not found in any location" >&2
        # 오류 로그 저장
        kvs_put "..." "{\"error\":\"script_not_found\"}"
        exit 1
    fi
fi

echo "[DEBUG] Using script: $auto_discover_script" >&2
```

### Option 2: 경로 자동 검색

```bash
# 시스템에서 파일을 찾음
auto_discover_script=$(find ${base_dir} -name "auto-discover-linux.sh" -type f | head -1)

if [ -z "$auto_discover_script" ] || [ ! -f "$auto_discover_script" ]; then
    echo "[ERROR] auto-discover-linux.sh not found anywhere!" >&2
    kvs_put "..." "{\"error\":\"script_not_found\"}"
    exit 1
fi

echo "[DEBUG] Found script at: $auto_discover_script" >&2
```

### Option 3: 경로 하드코딩 (임시)

```bash
# 서버에서 find로 실제 경로 확인
find /home/shinh/scripts -name "auto-discover-linux.sh" -type f

# 결과 예시:
# /home/shinh/scripts/infraops01/giipAgentLinux/lib/giipscripts/auto-discover-linux.sh

# giipAgent3.sh에 직접 설정
auto_discover_script="/home/shinh/scripts/infraops01/giipAgentLinux/lib/giipscripts/auto-discover-linux.sh"

if [ ! -f "$auto_discover_script" ]; then
    # 상대 경로로 폴백
    auto_discover_script="$(dirname $0)/lib/giipscripts/auto-discover-linux.sh"
fi
```

---

## ✅ 검증 절차

### Step 1: 서버에서 파일 위치 확인

```bash
# SSH로 서버 접속
ssh admin@infraops01.istyle.local

# 실제 파일 위치 찾기
find /home/shinh/scripts -name "auto-discover-linux.sh" -type f

# 출력 예시:
# /home/shinh/scripts/infraops01/giipAgentLinux/lib/giipscripts/auto-discover-linux.sh
# /home/shinh/scripts/infraops01/giipAgentLinux/giipscripts/auto-discover-linux.sh  (있으면)
```

### Step 2: giipAgent3.sh 경로 수정

```bash
# 파일 위치: /home/shinh/scripts/infraops01/giipAgentLinux/giipAgent3.sh
# 검색: "auto_discover_script=" 찾기
# 수정: 정확한 경로로 변경

# Before:
# auto_discover_script="${SCRIPT_DIR}/lib/lib/giipscripts/auto-discover-linux.sh"

# After:
# auto_discover_script="${SCRIPT_DIR}/lib/giipscripts/auto-discover-linux.sh"
#                                     ↑ lib 한 번만!
```

### Step 3: 수정 후 테스트

```powershell
# Windows PowerShell에서 (giipdb 디렉토리)
cd c:\Users\lowys\Downloads\projects\giipprj\giipdb

# 최신 KVS 조회
pwsh .\mgmt\check-latest.ps1 -Lssn 71240 -Minutes 1

# 확인 사항:
# 1. auto_discover_step_4_execution의 exit_code가 0이 되는가?
# 2. auto_discover_error_log (STEP-4)가 사라지는가?
# 3. auto_discover_step_5_validation이 성공으로 표시되는가?
# 4. auto_discover_result에 데이터가 저장되는가?
```

---

## 📋 체크리스트

### 🔴 현재 상태 (문제)

- [x] STEP-1: ✅ 설정 OK
- [x] STEP-2: ❌ 파일 경로 오류 (lib/lib)
- [x] STEP-3: ⚠️ 오류 무시하고 계속
- [x] STEP-4: ❌ 스크립트 실행 실패 (exit_code=127)
- [x] STEP-5: ❌ 결과 파일 없음
- [x] STEP-6: ❌ 저장할 데이터 없음
- [x] STEP-7: ⚠️ 거짓 완료 표시 (PASSED)

### ✅ 수정 후 예상 상태

- [ ] STEP-1: ✅ 설정 OK (변경 없음)
- [ ] STEP-2: ✅ 파일 경로 정상 (lib 한 번만)
- [ ] STEP-3: ✅ Initialize 정상
- [ ] STEP-4: ✅ 스크립트 실행 성공 (exit_code=0)
- [ ] STEP-5: ✅ 결과 파일 있음
- [ ] STEP-6: ✅ 데이터 저장 성공
- [ ] STEP-7: ✅ 완료 표시 정상 (PASSED with data)

---

## 🎓 핵심 교훈

### 배울 점

1. **경로 오류는 DB에도 기록된다**
   - auto_discover_error_log에 상세히 저장됨
   - 문제 진단이 가능한 상태

2. **조용한 실패의 위험성**
   - STEP-7에서 무조건 "PASSED" 표시
   - 실제로는 실패했지만 사용자는 성공으로 인식
   - 오류 처리 강화 필요

3. **데이터 저장 메커니즘은 정상**
   - 각 단계의 오류 정보가 KVS에 저장됨
   - 문제는 데이터 수집의 조기 실패

---

## 🔗 참고 자료

| 문서 | 참고 내용 |
|------|---------|
| AUTO_DISCOVER_ROOT_CAUSE_ANALYSIS.md | 원인 분석 상세 |
| AUTO_DISCOVER_LOGGING_ENHANCED.md | 로깅 메커니즘 |
| KVS_STORAGE_STANDARD.md | KVS 저장 표준 |

