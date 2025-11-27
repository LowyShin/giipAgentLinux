# 🔧 Auto-Discover 문제 해결 진행 상황

> ⚠️ **이 문서는 해결 진행 기록입니다.**
>
> 📌 **메인 문서**: [AUTO_DISCOVER_ISSUE_DIAGNOSIS_REPORT.md](./AUTO_DISCOVER_ISSUE_DIAGNOSIS_REPORT.md) ← 최신 진단 결과 확인
>
> 이 문서는 진행 과정의 기록이며, 최신 상태는 메인 문서를 참조하세요.

**마지막 업데이트**: 2025-11-26 13:21:35  
**상태**: ⚠️ **진행 중 - 경로 문제 부분 해결, 데이터 저장 문제 남음**  
**분석 대상**: LSSN 71240

---

## 📋 해결된 문제

### ✅ 1. 경로 중복 문제 (FIXED)
**원인**: 코드에서 `${SCRIPT_DIR}/lib/giipscripts/...`로 접근 → `lib/lib` 중복 발생  
**수정**: 단순 경로 `${SCRIPT_DIR}/giipscripts/...`로 변경  
**커밋**: e5e18e1

### ✅ 2. SCRIPT_DIR lib 포함 처리 (FIXED)
**원인**: 서버에서 `SCRIPT_DIR`이 이미 `lib`을 포함할 수 있음  
**수정**: lib 접미사 감지 및 제거 로직 추가
```bash
if [[ "$auto_discover_base_dir" == */lib ]]; then
    auto_discover_base_dir="${auto_discover_base_dir%/lib}"
fi
```
**커밋**: e5e18e1

### ✅ 3. 변수 초기화 순서 (FIXED)
**원인**: `kvs_put_complete_code` 사용 전 선언 미흡  
**수정**: STEP-7 시작 전 `kvs_put_complete_code=0` 초기화  
**커밋**: c7a936b

### ✅ 4. 중복 코드 정리 (FIXED)
**원인**: 라인 405-420에 중복되고 오염된 코드  
**수정**: 정리 및 정상화  
**커밋**: 1629603

### ✅ 5. Auto-Discover 결과 데이터 KVS 저장 (FIXED)
**원인**: 실제 수집 데이터가 아닌 메타데이터만 저장됨  
**수정**: 
- `auto_discover_result`: 전체 발견 결과 JSON
- `auto_discover_servers`: 서버 목록 (jq 추출)
- `auto_discover_networks`: 네트워크 정보 (jq 추출)
- `auto_discover_services`: 서비스 정보 (jq 추출)

**커밋**: 14e292b

---

## 🔴 현재 문제점

### ❌ 1. 경로 still 불일치
**최신 실행 (13:21:11) KVS 데이터**:
```json
{
  "step": "STEP-2",
  "data": {
    "path": "/home/shinh/scripts/infraops01/giipAgentLinux/giipscripts/auto-discover-linux.sh",
    "exists": false
  }
}
```

**문제**:
- STEP-2: `exists: false` (파일 없음)
- STEP-4: 실행되어 STEP-6까지 진행됨
- **파일이 없는데도 어떻게 실행되었는가?**

**가능한 원인**:
1. 파일이 다른 위치에 실제로 존재함
2. 경로 스트립 로직이 제대로 작동하지 않음
3. 서버의 실제 파일 구조가 예상과 다름

### ❌ 2. 실제 발견 데이터 미저장
**최신 KVS에 없는 것**:
- ❌ `auto_discover_result` (전체 발견 결과)
- ❌ `auto_discover_servers` (서버 목록)
- ❌ `auto_discover_networks` (네트워크)
- ❌ `auto_discover_services` (서비스)

**있는 것**:
- ✅ `auto_discover_step_6_store_resul`: `file_size: 7557` (데이터는 생성됨)

**의미**:
- 스크립트 실행은 성공 (7557 바이트 생성됨)
- 하지만 KVS 저장 단계에서 실패했거나 실행되지 않음

---

## 📊 타임라인 비교

| 버전 | 시간 | 경로 | 파일 exists | STEP-4 상태 | STEP-6 file_size | auto_discover_result |
|------|------|------|-------------|-------------|-----------------|----------------------|
| v1 (12:15) | 구 버전 | `lib/lib/giipscripts` | false ❌ | exit 127 ❌ | 0 | ❌ |
| v2 (13:16) | 수정 후 첫 실행 | `giipscripts` (정상!) | false ⚠️ | 기록 안 됨 | 7557 ✅ | ❌ |
| v3 (13:20-21) | 최신 2회 | `giipscripts` (정상!) | false ⚠️ | 기록 안 됨 | 7557 ✅ | ❌ |

---

## 🔍 근본 원인 분석

### 문제 1: 파일이 없는데도 실행됨?

**코드 흐름**:
```bash
# STEP-2: 파일 체크
if [ ! -f "$auto_discover_script" ]; then
    log_auto_discover_error ...
    return 1  # ← 여기서 return되어야 함
fi

# STEP-4: 실행
timeout 60 bash "$auto_discover_script" ...
```

**가능한 이유**:
1. `STEP-2`의 경로 스트립이 제대로 작동하지 않음
2. 파일이 실제로 다른 위치에 존재함
3. 디버그 로그 (`"exists": false`)가 잘못된 경로를 기반으로 기록됨

### 문제 2: 데이터가 KVS에 저장되지 않음

**코드 (최신)**:
```bash
auto_discover_json=$(cat "$auto_discover_result_file")

if [ -n "$auto_discover_json" ]; then
    kvs_put "lssn" "${lssn}" "auto_discover_result" "$auto_discover_json"
    kvs_put_result_code=$?
```

**가능한 이유**:
1. `auto_discover_json` 변수가 비어있음 (파일은 있지만 내용 없음)
2. `kvs_put` 함수 자체가 실패 (네트워크, 권한 등)
3. jq 명령어 오류로 서브 데이터 저장 실패

---

## 🛠️ 다음 해결 단계

### STEP A: 경로 검증 추가 (즉시 필요)

giipAgent3.sh의 STEP-2를 다음과 같이 수정:

```bash
# STEP-2 개선
auto_discover_base_dir="$SCRIPT_DIR"
if [[ "$auto_discover_base_dir" == */lib ]]; then
    auto_discover_base_dir="${auto_discover_base_dir%/lib}"
fi

auto_discover_script="${auto_discover_base_dir}/giipscripts/auto-discover-linux.sh"

# ✅ 디버그: 경로와 존재 여부 기록
echo "[DEBUG] auto_discover_base_dir=$auto_discover_base_dir" >&2
echo "[DEBUG] auto_discover_script=$auto_discover_script" >&2
echo "[DEBUG] file exists=$([ -f "$auto_discover_script" ] && echo YES || echo NO)" >&2

# KVS에 경로 정보 저장 (디버깅용)
kvs_put "lssn" "${lssn}" "auto_discover_debug_paths" "{\"script_dir\":\"$SCRIPT_DIR\",\"base_dir\":\"$auto_discover_base_dir\",\"script\":\"$auto_discover_script\",\"exists\":$([ -f \"$auto_discover_script\" ] && echo 'true' || echo 'false')}"

# 파일 존재 확인
if [ ! -f "$auto_discover_script" ]; then
    log_auto_discover_error "STEP-2" "SCRIPT_NOT_FOUND" "auto-discover script not found" "{\"searched_path\":\"${auto_discover_script}\",\"base_dir\":\"${auto_discover_base_dir}\"}"
    return 1
fi
```

### STEP B: 데이터 저장 검증 (필수)

STEP-6에 다음 추가:

```bash
# STEP-6 개선
echo "[DEBUG] auto_discover_json first 100 chars: ${auto_discover_json:0:100}" >&2
echo "[DEBUG] auto_discover_json length: ${#auto_discover_json}" >&2

if [ -z "$auto_discover_json" ]; then
    # 파일은 있지만 내용이 없음
    kvs_put "lssn" "${lssn}" "auto_discover_result" "{\"status\":\"error\",\"message\":\"Result file is empty after read\",\"file\":\"$auto_discover_result_file\"}"
    return 1
fi

# 실제 데이터 저장
kvs_put "lssn" "${lssn}" "auto_discover_result" "$auto_discover_json"
kvs_put_result_code=$?

if [ $kvs_put_result_code -ne 0 ]; then
    # KVS 저장 실패 원인 기록
    kvs_put "lssn" "${lssn}" "auto_discover_error_log" "{\"step\":\"STEP-6\",\"type\":\"KVS_PUT_FAILED\",\"message\":\"Failed to store result to KVS\",\"exit_code\":${kvs_put_result_code},\"result_size\":${#auto_discover_json}}"
fi
```

### STEP C: 서버에서 실제 파일 위치 확인 (필수)

서버에서 실행:
```bash
# 1. 실제 파일 위치 확인
find /home/shinh/scripts/infraops01 -name "auto-discover-linux.sh" -type f

# 2. SCRIPT_DIR 확인
bash -c 'SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"; echo "SCRIPT_DIR=$SCRIPT_DIR"' < /home/shinh/scripts/infraops01/giipAgentLinux/giipAgent3.sh

# 3. 실제 KVS 저장 로그 확인
cat /tmp/kvs_put_result_*.log
cat /tmp/kvs_put_servers_*.log
cat /tmp/kvs_put_networks_*.log
```

---

## 📝 최종 체크리스트

- [ ] **STEP A 실행**: 경로 검증 및 디버그 정보 KVS 저장
- [ ] **STEP B 실행**: 데이터 저장 검증 강화
- [ ] **STEP C 실행**: 서버에서 실제 파일 위치 확인
- [ ] **서버 재실행**: 수정된 코드 테스트
- [ ] **KVS 확인**: `auto_discover_debug_paths` 데이터 확인
- [ ] **분석**: 경로와 파일 위치 검증
- [ ] **최종 확인**: `auto_discover_result`, `auto_discover_servers` 등 데이터 저장 확인

---

## 🎯 예상 결과 (STEP A-C 완료 후)

**성공 시나리오**:
```
✅ STEP-2: auto_discover_debug_paths 저장 (경로 정보)
✅ STEP-4: 스크립트 실행 성공 (exit_code 0)
✅ STEP-6: auto_discover_result 저장 (7557 바이트 데이터)
✅ STEP-6: auto_discover_servers 저장 (파싱된 서버 목록)
✅ STEP-6: auto_discover_networks 저장 (파싱된 네트워크)
✅ STEP-7: auto_discover_complete 저장 (완료 표시)
```

**실패 시나리오 진단**:
- `auto_discover_debug_paths`가 없으면 → STEP-2 코드 미적용
- `auto_discover_debug_paths.exists=false` → 경로 여전히 잘못됨
- `auto_discover_result`가 없으면 → STEP-6 KVS 저장 실패

---

## 🔗 관련 커밋

- `1629603`: 경로 중복 제거, 변수 초기화 순서, 중복 코드 정리
- `0510ac2`: SCRIPT_DIR 초기화 시도 (나중에 원복)
- `e5e18e1`: SCRIPT_DIR lib 포함 처리 추가
- `14e292b`: 실제 발견 데이터 KVS 저장 추가

---

## 📌 핵심 발견

1. **경로 문제는 부분적으로 해결됨** (코드상으로는 정상)
2. **실제 데이터 저장은 여전히 미구현** (메타데이터만 저장)
3. **서버의 실제 환경 검증 필수** (파일 위치, 권한 등)
4. **더 상세한 디버그 정보 필요** (KVS에 기록하여 추적)
