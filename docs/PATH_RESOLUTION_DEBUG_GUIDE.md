# 🔍 경로 해석(Path Resolution) 문제 디버깅 가이드

**작성일**: 2025-11-25  
**대상**: auto-discover-linux.sh 경로 해석 문제 사후 분석  
**목표**: 이 문제를 처음부터 빨리 찾을 수 있도록 하기 위한 진단 가이드

---

## 📋 근본 원인 분석: 왜 못 찾았나?

### 1. **문제의 핵심 구조**

```bash
# ❌ 문제 발생 상황
SCRIPT_DIR="/home/shinh/scripts/infraops01/giipAgentLinux"  # 스크립트 실제 위치
auto_discover_script="${SCRIPT_DIR}/lib/giipscripts/auto-discover-linux.sh"

# ✅ 실제 서버 구조  
/home/shinh/scripts/infraops01/giipAgentLinux/
├── lib/giipscripts/auto-discover-linux.sh  ← 여기에 있음
├── giipscripts/                            ← 이곳에는 없음
└── giipAgent3.sh
```

### 2. **못 찾은 이유 (5가지 근본 원인)**

#### 🔴 **원인 1: SCRIPT_DIR의 실제 값을 확인하지 않음**

```bash
# 코드상 가정
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 실제 서버에서의 값
# ❓ `/home/shinh/scripts/infraops01/giipAgentLinux` (맞음)
# 또는
# ❓ `/home/shinh/scripts/infraops01/giipAgentLinux/lib` (틀림!)

# 💡 대책: 스크립트 실행 시 DEBUG로 출력
echo "[DEBUG] SCRIPT_DIR=$SCRIPT_DIR" >&2
```

**교훈**: 가정하지 말고 **실제 값을 출력**해서 확인

---

#### 🔴 **원인 2: 로컬 dev 환경과 서버 환경의 디렉토리 구조 차이 간과**

| 환경 | 경로 |
|------|------|
| **로컬 dev** | `/home/.../giipAgentLinux/giipscripts/auto-discover-linux.sh` |
| **서버** | `/home/.../giipAgentLinux/lib/giipscripts/auto-discover-linux.sh` |

```bash
# ❌ 초기 코드: 로컬 dev만 고려
auto_discover_script="${SCRIPT_DIR}/giipscripts/auto-discover-linux.sh"

# ✅ 올바른 대응: 양쪽 다 지원
auto_discover_script="${SCRIPT_DIR}/giipscripts/auto-discover-linux.sh"
if [ ! -f "$auto_discover_script" ]; then
    auto_discover_script="${SCRIPT_DIR}/lib/giipscripts/auto-discover-linux.sh"
fi
```

**교훈**: 새 서버 배포 시 **디렉토리 구조를 확인하는 문서화** 필수

---

#### 🔴 **원인 3: KVS 에러 메시지를 제대로 해석하지 않음**

```json
// KVS에 저장된 오류
{
  "status": "failed",
  "reason": "script_not_found",
  "path": "/home/shinh/scripts/infraops01/giipAgentLinux/lib/lib/giipscripts/auto-discover-linux.sh"
  //                                                          ^^^^^^
  //                                                    lib이 중복됨!
}
```

**놓친 신호**:
- 초기 오류: `lib/giipscripts/auto-discover-linux.sh` ✓ (올바른 경로)
- 수정 후: `lib/lib/giipscripts/auto-discover-linux.sh` ✗ (중복 발생)

```bash
# ❌ 이것이 의미하는 것:
# SCRIPT_DIR이 이미 "lib"을 포함하고 있다는 뜻
# ${SCRIPT_DIR}/lib/... 하면 lib이 중복됨

# 💡 근본 원인: 코드 실행 위치 가정이 틀렸음
```

**교훈**: KVS 오류의 **경로 값 자체**를 분석 - 중복이나 이상한 구조가 있으면 SCRIPT_DIR 점검

---

#### 🔴 **원인 4: 경로 우선순위를 잘못 설정**

```bash
# ❌ 우선순위 1: lib/giipscripts (서버)
# ❌ 우선순위 2: giipscripts (로컬 dev)
auto_discover_script="${SCRIPT_DIR}/lib/giipscripts/auto-discover-linux.sh"
if [ ! -f "$auto_discover_script" ]; then
    auto_discover_script="${SCRIPT_DIR}/giipscripts/auto-discover-linux.sh"
fi

# ✅ 올바른 우선순위 1: giipscripts (로컬 dev)
# ✅ 올바른 우선순위 2: lib/giipscripts (서버)
auto_discover_script="${SCRIPT_DIR}/giipscripts/auto-discover-linux.sh"
if [ ! -f "$auto_discover_script" ]; then
    auto_discover_script="${SCRIPT_DIR}/lib/giipscripts/auto-discover-linux.sh"
fi

# 왜? 
# - 로컬 개발 테스트 용이 (기본 경로 작동)
# - 서버는 자동으로 fallback (유연성)
```

**교훈**: **일반적인 경우를 우선**으로, 예외를 fallback으로 처리

---

#### 🔴 **원인 5: 경로 디버깅 로그 없음**

```bash
# ❌ 초기 코드: 디버그 정보 부족
if [ ! -f "$auto_discover_script" ]; then
    log_message "WARN" "script not found"  # 무엇이 문제인지 불명확
fi

# ✅ 개선된 코드: 상세한 디버그 로그
echo "[DEBUG] Trying path 1: ${SCRIPT_DIR}/giipscripts/auto-discover-linux.sh" >&2
echo "[DEBUG] Path 1 exists: $([ -f "${SCRIPT_DIR}/giipscripts/auto-discover-linux.sh" ] && echo 'YES' || echo 'NO')" >&2

echo "[DEBUG] Trying path 2: ${SCRIPT_DIR}/lib/giipscripts/auto-discover-linux.sh" >&2
echo "[DEBUG] Path 2 exists: $([ -f "${SCRIPT_DIR}/lib/giipscripts/auto-discover-linux.sh" ] && echo 'YES' || echo 'NO')" >&2

# KVS에 저장할 때 시도한 경로들을 모두 기록
kvs_put "lssn" "${lssn}" "auto_discover_init" \
    "{\"status\":\"failed\",\"reason\":\"script_not_found\",\"tried_paths\":[\"$path1\",\"$path2\"],\"script_dir\":\"${SCRIPT_DIR}\"}"
```

**교훈**: **모든 경로 시도와 결과를 stderr로 출력** + **KVS에는 시도 경로 배열 저장**

---

## 🎯 다음번 빨리 찾기 위한 진단 체크리스트

### Phase 1: 빠른 진단 (1분)

```bash
# 📊 Step 1: 현재 SCRIPT_DIR 확인
echo "SCRIPT_DIR의 실제 값:"
grep 'SCRIPT_DIR=' giipAgent3.sh | head -2

# 📊 Step 2: 코드에서 가정한 경로 확인
echo "코드에서 가정한 경로:"
grep 'auto_discover_script=' giipAgent3.sh

# 📊 Step 3: 서버의 실제 디렉토리 구조 확인
echo "서버 실제 구조:"
ssh shinh@<server> 'find /home/shinh/scripts -name "auto-discover-linux.sh" 2>/dev/null'

# 📊 Step 4: KVS 오류 메시지의 경로 값 분석
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71240 -KFactor "auto_discover_init" -Top 1
# └─ "path" 필드의 값을 자세히 보기
```

**예상 결과**:
```
KVS path: /home/shinh/scripts/infraops01/giipAgentLinux/lib/giipscripts/auto-discover-linux.sh
코드 path: ${SCRIPT_DIR}/giipscripts/auto-discover-linux.sh (또는 ${SCRIPT_DIR}/lib/giipscripts/...)
└─ 다르면 경로 우선순위 조정 필요
```

---

### Phase 2: 근본 원인 파악 (3분)

```bash
# 🔍 각 시나리오별 확인

# 시나리오 1: lib이 중복되는 경우
# "lib/lib/giipscripts" 또는 "lib/lib/..."
# └─ SCRIPT_DIR이 이미 "lib"을 포함
# └─ 수정: SCRIPT_DIR 변수 정의 재확인

# 시나리오 2: 경로가 완전히 다른 경우
# KVS에서 보이는 경로와 코드의 경로가 전혀 다름
# └─ 코드가 다른 환경을 기준으로 작성됨
# └─ 수정: giipAgent3.sh가 설치된 실제 위치 파악

# 시나리오 3: 상대 경로 해석 오류
# "./" 또는 "../" 포함된 경로
# └─ pwd 결과가 다른 값
# └─ 수정: cd 명령 후 pwd 실행
```

---

### Phase 3: 자동 감지 로그 추가

```bash
# 📋 giipAgent3.sh에 추가할 디버그 로그
# (이미 Commit 8f6bbaf에 포함됨)

# 줄 283-293: auto-discover 경로 판정
# ✅ 추가된 로그
# - SCRIPT_DIR의 실제 값
# - 경로 1 존재 여부
# - 경로 2 존재 여부
# - 최종 선택 경로
# - 실패 시 스크립트 디렉토리 값 저장

# 💡 다음 유사 문제 발생 시 이 로그가 핵심!
```

---

## 📚 KVS 로그 분석 패턴

### 패턴 1: 정상 작동

```json
// ✅ auto_discover_init
{
  "status": "starting",
  "script_path": "/home/shinh/scripts/infraops01/giipAgentLinux/lib/giipscripts/auto-discover-linux.sh",
  "lssn": 71240,
  "hostname": "infraops01"
}

// ✅ auto_discover_result
{
  "status": "success",
  "result_size": 2048,
  "os_name": "Linux",
  "hostname": "infraops01"
}
```

### 패턴 2: 경로 오류 (원래 문제)

```json
// ❌ auto_discover_init with "script_not_found"
{
  "status": "failed",
  "reason": "script_not_found",
  "path": "/home/shinh/scripts/infraops01/giipAgentLinux/giipscripts/auto-discover-linux.sh",
  "tried_paths": [
    "/home/shinh/scripts/infraops01/giipAgentLinux/giipscripts/auto-discover-linux.sh",
    "/home/shinh/scripts/infraops01/giipAgentLinux/lib/giipscripts/auto-discover-linux.sh"
  ]
}

// 💡 해석
// 1. 경로 1 시도: 실패 (lokal dev 구조 없음)
// 2. 경로 2 시도: 실패 (?? 뭔가 잘못됨)
// └─ SCRIPT_DIR 값 확인 필요!
```

### 패턴 3: SCRIPT_DIR 오류 (중복)

```json
// ❌ lib이 중복된 경우
{
  "status": "failed",
  "reason": "script_not_found",
  "path": "/home/shinh/scripts/infraops01/giipAgentLinux/lib/lib/giipscripts/auto-discover-linux.sh",
  "script_dir": "/home/shinh/scripts/infraops01/giipAgentLinux/lib"
}

// 💡 해석
// script_dir이 이미 "lib"을 포함!
// └─ giipAgent3.sh가 lib/에서 실행 중인가?
// └─ source 명령 때문인가? (BASH_SOURCE 변경)
// └─ 수정: giipAgent3.sh 실행 위치 확인
```

---

## 🛠️ 코드 템플릿: 경로 디버깅 베스트 프랙티스

### 올바른 구현 (Commit 8f6bbaf)

```bash
#!/bin/bash

# ✅ 1단계: SCRIPT_DIR 정의 (맨 처음)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# ✅ 2단계: DEBUG 출력 (문제 추적용)
echo "[DEBUG] Script location: $0" >&2
echo "[DEBUG] SCRIPT_DIR: $SCRIPT_DIR" >&2

# ✅ 3단계: 여러 경로 시도 (우선순위 명확)
script_path1="${SCRIPT_DIR}/giipscripts/auto-discover-linux.sh"
script_path2="${SCRIPT_DIR}/lib/giipscripts/auto-discover-linux.sh"

echo "[DEBUG] Trying path 1: $script_path1 (exists: $([ -f "$script_path1" ] && echo 'YES' || echo 'NO'))" >&2

if [ -f "$script_path1" ]; then
    final_script="$script_path1"
else
    echo "[DEBUG] Trying path 2: $script_path2 (exists: $([ -f "$script_path2" ] && echo 'YES' || echo 'NO'))" >&2
    final_script="$script_path2"
fi

# ✅ 4단계: 결과 저장 (KVS에 시도 경로 모두 기록)
if [ ! -f "$final_script" ]; then
    kvs_put "lssn" "${lssn}" "auto_discover_init" \
        "{\"status\":\"failed\",\"reason\":\"script_not_found\",\"tried_paths\":[\"$script_path1\",\"$script_path2\"],\"script_dir\":\"${SCRIPT_DIR}\"}"
    exit 1
fi

# ✅ 5단계: 실행
. "$final_script"
```

---

## 📋 이 문제가 다시 발생하는 것을 방지하기 위한 조치

### 1. **자동 감지 규칙 (giipAgent3.sh에 이미 추가됨)**

✅ Commit 8f6bbaf:
```bash
# 경로 1: 로컬 dev 구조
# 경로 2: 서버 lib 구조
# 모두 실패하면 SCRIPT_DIR 값 저장
```

### 2. **문서화**

✅ 이 문서: `PATH_RESOLUTION_DEBUG_GUIDE.md`  
✅ MODULAR_ARCHITECTURE.md에 이미 있는 규칙 강화 필요

### 3. **단위 테스트**

```bash
# 새로 추가할 테스트 (test-path-resolution.sh)
test-path-resolution.sh:
  [ ] giipscripts 경로 존재 확인
  [ ] lib/giipscripts 경로 존재 확인
  [ ] SCRIPT_DIR 출력
  [ ] auto-discover 실행 시뮬레이션
```

### 4. **모니터링**

KVS 쿼리 (수정됨, 2025-11-25):
```powershell
# tried_paths 배열 확인
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71240 -KFactor "auto_discover_init" -Top 3

# 중복 "lib" 감지하면 즉시 알림
```

---

## 🚀 빠른 진단 명령어 (참고용)

### 1. KVS에서 최신 오류 확인

```powershell
# 최신 5개 auto_discover_init 로그
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71240 -KFactor "auto_discover_init" -Hours 0.5 -Top 5
```

### 2. 경로 중복 감지

```powershell
# "lib/lib" 포함된 오류 찾기
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71240 -KFactor "auto_discover_init" -Hours 1 -Top 20 | 
  Select-String "lib/lib"
```

### 3. 서버에서 직접 확인

```bash
# 서버 SSH 접속 후
find /home/shinh/scripts -name "auto-discover-linux.sh" -exec echo "Found: {}" \;
echo "SCRIPT_DIR would be:"
cd /home/shinh/scripts/infraops01/giipAgentLinux
pwd
```

---

## 📝 요약: 이 문제를 못 찾은 핵심 이유 vs 해결책

| 이유 | 해결책 |
|------|--------|
| **가정만 했고 실제 값 확인 안 함** | DEBUG 로그: SCRIPT_DIR 실제 값 출력 |
| **로컬/서버 환경 차이 간과** | Fallback 경로 추가 + 우선순위 명확히 |
| **KVS 오류의 "lib/lib" 신호 못 봄** | "중복" 감지하면 SCRIPT_DIR 재검토 |
| **우선순위 틀림** | 일반 → 예외 순서로 변경 |
| **경로 디버그 정보 없음** | stderr + KVS에 모두 기록 |

---

**다음 유사 문제 발생 시**: 이 문서의 "Phase 1: 빠른 진단"부터 시작하면 **5분 내에 원인 파악 가능**
