# Shell Component Specification (lib/*.sh 표준화 규칙)

**작성일**: 2025-11-23  
**버전**: 1.0  
**상태**: 🟢 Active  
**목적**: giipAgent3.sh와 호환되는 lib/*.sh 모듈의 개발 표준

---

## 📚 상위 문서 (Parent Documents)

이 문서는 다음 상위 문서의 **상세 표준화 규칙**입니다:

- **[MODULAR_ARCHITECTURE.md](MODULAR_ARCHITECTURE.md)** - 전체 모듈 아키텍처 및 lib/*.sh 개요
- **[AUTO_DISCOVERY_ARCHITECTURE.md](AUTO_DISCOVERY_ARCHITECTURE.md)** - Discovery 모듈 설계 (Separation of Concerns)
- **[GIIPAGENT3_SPECIFICATION.md](GIIPAGENT3_SPECIFICATION.md)** - giipAgent3.sh 전체 사양
- **[GATEWAY_HANG_DIAGNOSIS.md](GATEWAY_HANG_DIAGNOSIS.md)** - 모듈 통합 문제 진단 및 해결책

> ⚠️ **필수**: 이 문서를 읽기 전에 위 상위 문서들의 개요 섹션을 먼저 읽어주세요.

---

## 📌 핵심 원칙

### 1. Function Definition Policy (함수 정의 정책)

#### ✅ 반드시 lib/*.sh에 정의해야 할 함수

모든 lib/*.sh 파일에서 정의하는 함수는:
- **giipAgent3.sh에서 절대 중복 정의하면 안됨**
- 다른 lib/*.sh 파일에서 재정의해서도 안됨
- 구현 로직과 오케스트레이션 로직을 분리

**예시:**
```bash
# lib/discovery.sh - 구현 로직 (Data Collector)
collect_infrastructure_data() {
    # 실제 데이터 수집 로직
}

# lib/gateway.sh - 구현 로직 (Gateway 처리)
process_gateway_servers() {
    # 실제 Gateway 서버 처리
}

# giipAgent3.sh에서는 호출만 함 (Orchestrator)
if should_run_discovery "$lssn"; then
    collect_infrastructure_data "$lssn"
fi
```

#### ❌ 절대 하면 안 되는 패턴

```bash
# 잘못된 설계: 같은 함수를 여러 곳에 정의
# giipAgent3.sh에 정의
should_run_discovery() { ... }

# lib/discovery.sh에도 정의
should_run_discovery() { ... }  # ❌ 중복 정의!
```

---

### 2. Error Handling Policy (에러 처리 정책)

#### ✅ lib/*.sh 내부에서의 에러 처리

**Rule 1: `set -euo pipefail` 사용 금지**

lib/*.sh 파일은 `set -euo pipefail`을 **절대 사용하면 안됨**:

```bash
# ❌ 절대 금지
set -euo pipefail

collect_infrastructure_data() {
    # 이 함수 실행 중 에러 발생 시
    # 부모 스크립트(giipAgent3.sh)까지 전체 종료됨!
}
```

**이유**: 로드된 모듈의 설정이 부모 프로세스에 상속되어, 모듈의 에러가 부모 전체를 죽임

**Rule 2: 명시적 에러 처리 사용**

대신 각 함수에서 명시적으로 에러 처리:

```bash
# ✅ 올바른 패턴
collect_infrastructure_data() {
    local lssn="$1"
    
    # 각 단계에서 에러 체크
    _log_to_kvs "DISCOVERY_START" ... || return 1
    _collect_local_data "$lssn" || return 1
    _save_discovery_to_db ... || return 1
    
    return 0
}

# giipAgent3.sh에서 호출할 때 에러 처리
if collect_infrastructure_data "$lssn"; then
    log_message "INFO" "Discovery completed successfully"
else
    log_message "WARN" "Discovery failed, continuing without data"
fi
```

#### ✅ 호출 측(giipAgent3.sh)에서의 에러 처리

**Rule 3: 모듈 함수 호출 시 반드시 에러 처리**

```bash
# giipAgent3.sh에서

# ❌ 잘못된 방식: 에러 처리 없음
collect_infrastructure_data "$lssn"

# ✅ 올바른 방식: if 구문으로 처리
if collect_infrastructure_data "$lssn"; then
    # 성공
else
    # 실패 (하지만 프로세스는 계속 진행)
fi

# ✅ 또 다른 올바른 방식: && || 로 처리
collect_infrastructure_data "$lssn" && \
    log_message "INFO" "Discovery OK" || \
    log_message "WARN" "Discovery failed, continuing"
```

**Rule 4: Timeout 설정 필수**

장시간 블로킹될 수 있는 함수는 timeout 설정:

```bash
# lib/discovery.sh의 collect_infrastructure_data 내부
_collect_local_data() {
    local lssn="$1"
    
    # 30초 제한 설정
    timeout 30 bash "$DISCOVERY_SCRIPT" || {
        log_message "ERROR" "Discovery script timed out"
        return 1
    }
}
```

---

### 3. Global Variable Policy (전역 변수 정책)

#### ✅ 허용되는 전역 변수

lib/*.sh에서 정의해도 되는 전역 변수:

```bash
# ✅ 상수 정의 (대문자)
readonly LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DISCOVERY_SCRIPT="${LIB_DIR}/../giipscripts/auto-discover-linux.sh"

# ✅ 설정값 (소문자로 시작)
local_hostname="$(hostname)"
local_kernel_version="$(uname -r)"

# ✅ 모듈 내부 전용 함수 (언더스코어로 시작)
_log_to_kvs() { ... }
_collect_local_data() { ... }
_save_discovery_to_db() { ... }
```

#### ❌ 절대 금지되는 전역 변수

```bash
# ❌ 절대 금지: 부모 스크립트 변수 덮어쓰기
export KVS_LSSN="$lssn"  # 부모의 KVS_LSSN 덮어씀!
export lssn="new_value"  # 부모의 lssn 변경!

# ❌ 절대 금지: 암묵적 전역 변수 (선언 없이)
discovery_json="..."     # local 선언 없음 (전역으로 누출)
temp_file="/tmp/xxx"     # 전역 변수 사용 (이름 충돌 가능)
```

#### ✅ 올바른 변수 사용

```bash
# ✅ 항상 local로 선언
collect_infrastructure_data() {
    local lssn="$1"                    # 함수 인자
    local discovery_json               # 로컬 변수
    local temp_file="/tmp/disc_$$_$RANDOM"  # 유니크한 이름
    
    # 로컬 변수만 사용
    discovery_json=$(bash "$DISCOVERY_SCRIPT" 2>&1)
    
    # 부모 변수는 읽기 전용 (KVS_LSSN, lssn 등)
    log_message "INFO" "Processing LSSN=$KVS_LSSN"
}
```

---

### 4. Function Isolation Policy (함수 격리 정책)

#### ✅ 공개 함수 vs 비공개 함수 명확히

```bash
# lib/discovery.sh

# ✅ 공개 함수 (giipAgent3.sh에서 호출 가능)
# - 언더스코어 없음
# - 문서화 필수
collect_infrastructure_data() {
    # ...
}

# ✅ 비공개 함수 (lib/*.sh 내부용)
# - 언더스코어로 시작
# - 다른 모듈에서 호출 금지
_collect_local_data() {
    # ...
}

_save_discovery_to_db() {
    # ...
}

_log_to_kvs() {
    # ...
}
```

---

### 5. Logging Policy (로깅 정책)

#### ✅ 필수 로깅 포인트

lib/*.sh 함수는 다음 포인트에서 반드시 로깅:

```bash
collect_infrastructure_data() {
    local lssn="$1"
    
    # 1️⃣ 시작 로깅
    log_message "INFO" "Starting discovery for LSSN=$lssn"
    
    # 2️⃣ 주요 단계별 로깅
    log_message "DEBUG" "Collecting local infrastructure data"
    if _collect_local_data "$lssn"; then
        log_message "INFO" "Local data collection completed"
    else
        log_message "ERROR" "Local data collection failed"
        return 1
    fi
    
    # 3️⃣ 종료 로깅
    log_message "INFO" "Discovery completed successfully"
    return 0
}
```

#### ✅ KVS 로깅 사용

```bash
# lib/discovery.sh - KVS 로깅 예시
_log_to_kvs() {
    local kfactor="$1"
    local kvalue="$2"
    
    # kvsput으로 KVS 테이블에 기록
    kvsput \
        --lssn "$KVS_LSSN" \
        --kfactor "$kfactor" \
        --kvalue "$kvalue" \
        --token "$sk"
}

# 사용
_log_to_kvs "DISCOVERY_START" "$(json_encode '{"status":"starting","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}')"
```

---

### 6. Subshell Safety Policy (서브셸 안전 정책)

#### ✅ 프로세스 격리 필요한 경우

복잡한 모듈을 독립 프로세스로 실행:

```bash
# giipAgent3.sh에서

# 옵션 1: Subshell로 격리 (권장)
(
    . "${LIB_DIR}/discovery.sh"
    collect_infrastructure_data "$lssn"
) || log_message "WARN" "Discovery failed, continuing"

# 옵션 2: Background 프로세스
collect_infrastructure_data "$lssn" &
discovery_pid=$!

# Timeout 설정
( sleep 60; kill $discovery_pid 2>/dev/null ) &
wait $discovery_pid 2>/dev/null || true

# 옵션 3: 독립 스크립트로 실행
bash giip-auto-discover.sh || log_message "WARN" "Auto-discover failed"
```

---

### 7. Testing Policy (테스트 정책)

#### ✅ lib/*.sh 테스트 체크리스트

모든 lib/*.sh 파일은 다음과 같이 테스트:

```bash
# 1️⃣ 단독 테스트 (함수 내부 확인)
bash lib/discovery.sh
# 또는
. lib/discovery.sh && collect_infrastructure_data "$test_lssn"

# 2️⃣ 통합 테스트 (giipAgent3.sh에 로드되었을 때)
bash giipAgent3.sh
# KVS 로그 확인
pwsh -c "cd ../giipdb; ./mgmt/query-kvs.ps1"

# 3️⃣ 에러 케이스 테스트
# - 잘못된 인자 전달
# - 네트워크 실패 상황
# - 타임아웃 상황
```

---

## 📋 lib/*.sh 파일 생성 체크리스트

새로운 lib/*.sh 파일을 생성할 때 확인사항:

### 1. 구조

- [ ] ✅ `#!/bin/bash` 선언
- [ ] ❌ `set -euo pipefail` **절대 금지**
- [ ] ✅ 파일 헤더 주석 (역할, 기능 설명)
- [ ] ✅ 함수별 주석 (파라미터, 반환값)

### 2. 함수

- [ ] ✅ 공개 함수 (언더스코어 없음)
- [ ] ✅ 비공개 함수 (언더스코어 시작)
- [ ] ✅ 각 함수에서 `local` 변수 사용
- [ ] ✅ 각 함수에서 `|| return 1` 에러 처리

### 3. 에러 처리

- [ ] ✅ 각 단계에서 `|| return 1` 추가
- [ ] ✅ 외부 명령어 실행 시 에러 체크
- [ ] ✅ 호출 측에서 반환값 확인 (if 구문)

### 4. 로깅

- [ ] ✅ 시작/종료 로깅
- [ ] ✅ 주요 단계별 로깅
- [ ] ✅ 에러 발생 시 로깅
- [ ] ✅ KVS 로깅 (필요시)

### 5. 변수

- [ ] ✅ 전역 변수 최소화
- [ ] ✅ 모든 변수에 `local` 선언
- [ ] ✅ 상수는 `readonly` 선언
- [ ] ✅ 임시 파일은 `$$_$RANDOM` 패턴

### 6. 독립성

- [ ] ✅ 단독으로 테스트 가능
- [ ] ✅ 다른 lib/*.sh와 겹치지 않음
- [ ] ✅ giipAgent3.sh 변수 오염 없음

### 7. 문서화

- [ ] ✅ README 파일에 역할 설명
- [ ] ✅ 함수별 주석 작성
- [ ] ✅ 사용 예시 제공

---

## 📚 참고 문서

| 문서 | 용도 |
|------|------|
| [MODULAR_ARCHITECTURE.md](MODULAR_ARCHITECTURE.md) | 전체 모듈 아키텍처 |
| [GIIPAGENT3_SPECIFICATION.md](GIIPAGENT3_SPECIFICATION.md) | giipAgent3.sh 사양 |
| [KVS_STANDARD_USAGE.md](KVS_STANDARD_USAGE.md) | KVS 로깅 표준 |
| [GATEWAY_IMPLEMENTATION_SUMMARY.md](GATEWAY_IMPLEMENTATION_SUMMARY.md) | Gateway 구현 |

---

## 🔗 실제 구현 예시

### 좋은 예시: lib/gateway.sh

```bash
#!/bin/bash
# Gateway 처리 모듈
# 역할: 원격 서버 Gateway 큐 처리

# 공개 함수
process_gateway_servers() {
    local tmpdir="/tmp/giipAgent_gateway_$$"
    
    # ✅ 에러 처리
    mkdir -p "$tmpdir" || return 1
    
    # ✅ 로깅
    gateway_log "🟢" "[5]" "Gateway 처리 시작"
    
    # ✅ 주요 로직
    local server_list_file=$(get_gateway_servers)
    [ -s "$server_list_file" ] || return 1
    
    # ✅ 정리
    rm -f "$server_list_file"
    gateway_log "🟢" "[5.12]" "Gateway 처리 완료"
}

# 비공개 함수
_validate_server_params() {
    local params="$1"
    [[ "$params" =~ "hostname" ]] || return 1
}
```

### 나쁜 예시: lib/discovery_broken.sh

```bash
#!/bin/bash
# ❌ 문제: set -euo pipefail 사용
set -euo pipefail

# ❌ 문제: 전역 변수 export
export KVS_LSSN="$1"

collect_infrastructure_data() {
    # ❌ 문제: 에러 처리 없음
    bash auto-discover-linux.sh
    
    # ❌ 문제: 부모 변수 변경
    lssn="new_value"
    
    # ❌ 문제: 로깅 없음
}
```

---

**작성자**: GitHub Copilot  
**버전**: 1.0  
**마지막 업데이트**: 2025-11-23
