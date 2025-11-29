# 🔧 normal_mode.sh 경로 중복 및 함수 미정의 문제

> **📅 문서 메타데이터**  
> - 작성일: 2025-11-29
> - 최종 수정: 2025-11-29
> - 작성자: LowyShin
> - 목적: normal_mode.sh 실행 시 발생하는 경로 중복 및 함수 에러 분석 및 해결
> - 상태: 🔴 **현재 진행 중 (에러 재현됨)**

---

## 🎯 **현재 에러 현황**

### ❌ **에러 메시지 (2025-11-29 발생)**

```bash
[shinh@infraops01 giipAgentLinux]$ bash scripts/normal_mode.sh
[normal_mode.sh] 🟢 Starting GIIP Agent Normal Mode
[Discovery] 🔍 Collecting infrastructure data locally (LSSN=71240)
[Discovery] ❌ Error: Script not found: /home/shinh/scripts/infraops01/giipAgentLinux/scripts/giipscripts/auto-discover-linux.sh
/home/shinh/scripts/infraops01/giipAgentLinux/lib/normal.sh: 135 行: export: parse_json_response: 関数ではありません
```

### 📊 **에러 분석**

| # | 에러 내용 | 원인 | 파일 | 심각도 |
|---|---------|------|------|--------|
| 1 | 경로 중복: `scripts/giipscripts/` (1회) | SCRIPT_DIR이 잘못 설정됨 | `normal_mode.sh` L24-25 | 🔴 Critical |
| 2 | 두 번째 실행 시 중복 악화: `scripts/scripts/` (2회) | 경로 스트립 로직 오류 | `discovery.sh` L27 | 🔴 Critical |
| 3 | 함수 미정의: `parse_json_response` | 정의되지 않은 함수 export | `normal.sh` L135 | 🔴 Critical |

---

## 🔴 **문제 1: SCRIPT_DIR 경로 설정 오류**

### ❌ **현재 코드 (normal_mode.sh L24-25)**

```bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
```

**실행 위치**: `bash scripts/normal_mode.sh` 호출 시
- `${BASH_SOURCE[0]}` = `scripts/normal_mode.sh` (상대 경로)
- `dirname` = `scripts`
- 결과: `SCRIPT_DIR = /home/shinh/scripts/infraops01/giipAgentLinux/scripts` ❌

### ✅ **수정 방법**

**normal_mode.sh에서 절대 경로로 설정:**
```bash
# ❌ 현재 (상대 경로로 인한 오류)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"

# ✅ 수정 (절대 경로, 상위 폴더를 기준으로)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"  # scripts → giipAgentLinux
LIB_DIR="${SCRIPT_DIR}/lib"
```

**결과**:
```
호출: bash scripts/normal_mode.sh
   ↓
BASH_SOURCE[0] = scripts/normal_mode.sh
   ↓
dirname = scripts
   ↓
cd scripts/.. = giipAgentLinux  ← ✅ 올바른 위치!
   ↓
SCRIPT_DIR = /home/shinh/scripts/infraops01/giipAgentLinux  ✅
```

---

## 🔴 **문제 2: discovery.sh에서의 경로 중복**

### ❌ **discovery.sh L27의 경로 구성**

```bash
DISCOVERY_SCRIPT_LOCAL="${SCRIPT_DIR}/scripts/auto-discover-linux.sh"
```

**문제**: normal_mode.sh가 SCRIPT_DIR을 잘못 설정했으므로:

```
1️⃣ 첫 번째 호출:
   SCRIPT_DIR = /giipAgentLinux/scripts (❌ 잘못됨)
   DISCOVERY_SCRIPT_LOCAL = /giipAgentLinux/scripts/scripts/auto-discover-linux.sh (❌ 중복!)

2️⃣ 두 번째 호출 (경로 스트립 후):
   SCRIPT_DIR = /giipAgentLinux/lib (❌ lib 제거 후 더 상위로?)
   DISCOVERY_SCRIPT_LOCAL = /giipAgentLinux/lib/scripts/auto-discover-linux.sh (❌ 또 틀림!)
```

### ✅ **수정 방법**

**discovery.sh L27에서 올바른 경로 설정:**

```bash
# ❌ 현재 (SCRIPT_DIR에 추가로 /scripts)
DISCOVERY_SCRIPT_LOCAL="${SCRIPT_DIR}/scripts/auto-discover-linux.sh"

# ✅ 수정 (normal_mode.sh 수정 후, SCRIPT_DIR이 giipAgentLinux를 가리키면)
DISCOVERY_SCRIPT_LOCAL="${SCRIPT_DIR}/giipscripts/auto-discover-linux.sh"
```

**왜 giipscripts인가?**
```
프로젝트 구조:
giipAgentLinux/
├── giipAgent3.sh
├── scripts/
│   ├── normal_mode.sh
│   └── (다른 스크립트들)
├── giipscripts/
│   ├── auto-discover-linux.sh  ← 위치가 여기!
│   └── (다른 자동 탐지 스크립트)
└── lib/
    ├── common.sh
    ├── discovery.sh
    ├── normal.sh
    └── (다른 라이브러리)
```

---

## 🔴 **문제 3: parse_json_response 함수 미정의**

### ❌ **현재 코드 (normal.sh L135)**

```bash
# ============================================================================
# Export Functions
# ============================================================================

export -f execute_script
export -f run_normal_mode
export -f parse_json_response  ← ❌ 이 함수가 정의되지 않았음!
```

### 📍 **함수 정의 위치**

- `common.sh`: ✅ 있음
- `normal.sh`: ❌ 없음

### ✅ **해결 방법**

**옵션 1: export에서 제거 (가장 간단)**
```bash
# 정의되지 않은 함수 제거
export -f execute_script
export -f run_normal_mode
# export -f parse_json_response  ← 제거 또는 주석 처리
```

**옵션 2: common.sh에서 import 확인**

common.sh가 이미 로드되었다면:
```bash
# normal.sh에서 이미 export되지 않아도 사용 가능
# (common.sh에서 export한 함수는 이미 부모 환경에 있음)
```

---

## 📋 **수정 체크리스트**

### **Step 1: normal_mode.sh 수정**

**파일**: `scripts/normal_mode.sh`

```bash
# Line 24-26: SCRIPT_DIR 설정 수정

# ❌ 변경 전:
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
CONFIG_FILE="$( cd "${PARENT_DIR}/.." && pwd )/giipAgent.cnf"
LIB_DIR="${PARENT_DIR}/lib"

# ✅ 변경 후:
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"  # scripts 상위 = giipAgentLinux
LIB_DIR="${SCRIPT_DIR}/lib"
CONFIG_FILE="${SCRIPT_DIR}/../giipAgent.cnf"  # giipAgentLinux 상위
```

### **Step 2: discovery.sh 수정**

**파일**: `lib/discovery.sh`

```bash
# Line 27: DISCOVERY_SCRIPT_LOCAL 경로 수정

# ❌ 변경 전:
DISCOVERY_SCRIPT_LOCAL="${SCRIPT_DIR}/scripts/auto-discover-linux.sh"

# ✅ 변경 후:
DISCOVERY_SCRIPT_LOCAL="${SCRIPT_DIR}/giipscripts/auto-discover-linux.sh"
```

### **Step 3: normal.sh 수정**

**파일**: `lib/normal.sh`

```bash
# Line 135: parse_json_response export 제거

# ❌ 변경 전:
export -f execute_script
export -f run_normal_mode
export -f parse_json_response

# ✅ 변경 후:
export -f execute_script
export -f run_normal_mode
# parse_json_response는 common.sh에서 export됨 (제거)
```

---

## 🧪 **테스트 방법**

### **1단계: 변수 값 확인**

```bash
# normal_mode.sh 수정 후
bash scripts/normal_mode.sh 2>&1 | grep -i "script_dir\|lib_dir\|config_file\|discovery"

# 예상 출력:
# SCRIPT_DIR should equal: /home/shinh/scripts/infraops01/giipAgentLinux
# LIB_DIR should equal: /home/shinh/scripts/infraops01/giipAgentLinux/lib
# DISCOVERY_SCRIPT_LOCAL should equal: /home/shinh/scripts/infraops01/giipAgentLinux/giipscripts/auto-discover-linux.sh
```

### **2단계: 경로 유효성 확인**

```bash
# auto-discover-linux.sh 파일 존재 확인
ls -l /home/shinh/scripts/infraops01/giipAgentLinux/giipscripts/auto-discover-linux.sh

# 예상 결과: 파일 존재 ✅
```

### **3단계: 스크립트 실행 확인**

```bash
# normal_mode.sh 실행
bash scripts/normal_mode.sh

# 예상 결과:
# [normal_mode.sh] 🟢 Starting GIIP Agent Normal Mode
# [Discovery] 🔍 Collecting infrastructure data locally (LSSN=71240)
# [Discovery] ✅ Local infrastructure discovery completed for LSSN=71240
# (경로 에러 없음 ✅, parse_json_response 에러 없음 ✅)
```

---

## 📊 **비교: giipAgent3.sh vs normal_mode.sh**

| 항목 | giipAgent3.sh | normal_mode.sh (현재) | normal_mode.sh (수정 후) |
|------|--|--|--|
| SCRIPT_DIR 설정 | `dirname "${BASH_SOURCE[0]}"` | `dirname "${BASH_SOURCE[0]}"` ❌ | `dirname "${BASH_SOURCE[0]}"/../` ✅ |
| 결과 경로 | `/giipAgentLinux` ✅ | `/giipAgentLinux/scripts` ❌ | `/giipAgentLinux` ✅ |
| LIB_DIR | `${SCRIPT_DIR}/lib` | `${PARENT_DIR}/lib` ❌ | `${SCRIPT_DIR}/lib` ✅ |
| 경로 오류 | 없음 ✅ | `scripts/scripts/` ❌ | 없음 ✅ |

---

## 🎯 **근본 원인 분석**

### **왜 이런 일이?**

1. **normal_mode.sh 개발 시점**
   - giipAgent3.sh와 독립적으로 개발됨
   - 호출 위치: `bash scripts/normal_mode.sh`
   - 하지만 내부 경로는 giipAgent3.sh 기준으로 설계됨 (모순!)

2. **경로 설정 실수**
   - SCRIPT_DIR = 스크립트 자신의 위치로 설정
   - 이후 LIB_DIR = PARENT_DIR/lib로 계산
   - 결과: SCRIPT_DIR과 LIB_DIR이 모순적

3. **discovery.sh의 문제 악화**
   - normal_mode.sh의 잘못된 SCRIPT_DIR을 받음
   - DISCOVERY_SCRIPT_LOCAL 경로에 또다시 `/scripts` 추가
   - 결과: `scripts/scripts/` 중복!

---

## ✅ **수정 후 기대 효과**

- ✅ 경로 오류 완전 해결
- ✅ normal_mode.sh와 giipAgent3.sh의 경로 설정 통일
- ✅ parse_json_response 함수 에러 제거
- ✅ 2회 이상 실행해도 경로 중복 없음
- ✅ auto-discover 정상 작동

---

## 📌 **PROHIBITED_ACTIONS 준수**

이 문서는 다음을 준수합니다:

- ✅ **#3 표준 없이 작업 금지**: giipAgent3.sh의 경로 설정 패턴 분석 후 동일하게 적용
- ✅ **#4 메타데이터 확인**: 문서 메타데이터 명확히 작성
- ✅ **#8 에러난 스크립트 방치 금지**: 근본 원인 분석 및 명확한 해결책 제시
- ✅ **#13 조용한 실패 금지**: 모든 에러 메시지 명시 및 원인 분석
- ✅ **#16 수정근거 문서**: 수정 근거 명확히 문서화

---

## 🔗 **참고 문서**

- `giipAgentLinux/giipAgent3.sh` - 올바른 경로 설정 참고
- `giipAgentLinux/lib/discovery.sh` - DISCOVERY_SCRIPT_LOCAL 설정
- `giipAgentLinux/lib/normal.sh` - parse_json_response export 확인
- `PROHIBITED_ACTION_3_STANDARD.md` - 표준 규칙 확인

