# 🔧 Auto-Discover 문제 진단 및 해결 보고서

**최종 업데이트**: 2025-11-26 13:21 (KVS 조회 완료)  
**진단 대상**: LSSN 71240  
**현재 상태**: ⚠️ **부분 해결 진행 중 - 경로 고정 완료, 데이터 저장 미확인**

---

## 📋 상태 요약 (한눈에 보기)

| 항목 | 상태 | 설명 |
|------|------|------|
| **경로 오류 (lib/lib)** | ✅ 해결됨 | 코드에 lib 스트립 로직 추가 (커밋 e5e18e1) |
| **STEP-2 파일 확인** | ⚠️ 불일치 | KVS에서 exists=false지만 STEP-4 정상 실행 |
| **STEP-4 스크립트 실행** | ✅ 성공 | 올바른 경로로 실행, result file 7557 bytes |
| **결과 데이터 저장** | ❌ 미확인 | auto_discover_result 키가 KVS에 없음 |
| **구성요소 파싱** | ❌ 미확인 | auto_discover_servers, networks, services 모두 없음 |

---

## 🎯 해결된 것 vs 남은 것

### ✅ 이미 해결된 문제

#### 1. 경로 중복 (lib/lib) - 커밋 e5e18e1
```bash
# ❌ 이전 경로 (잘못됨):
/home/shinh/scripts/infraops01/giipAgentLinux/lib/lib/giipscripts/auto-discover-linux.sh
                                                   ↑↑ 중복!

# ✅ 수정된 로직 (giipAgent3.sh STEP-2):
auto_discover_base_dir="$SCRIPT_DIR"
if [[ "$auto_discover_base_dir" == */lib ]]; then
    auto_discover_base_dir="${auto_discover_base_dir%/lib}"  # /lib 제거
fi
auto_discover_script="${auto_discover_base_dir}/giipscripts/auto-discover-linux.sh"
# 결과: /home/shinh/scripts/infraops01/giipAgentLinux/giipscripts/auto-discover-linux.sh ✅
```

**검증** (2025-11-26 13:16:13):
- STEP-4 실행 시 올바른 경로 확인 ✅
- 결과 파일 생성됨 (7557 바이트) ✅
- exit_code 0 (성공) ✅

#### 2. 변수 초기화 순서 - 커밋 e5e18e1
```bash
# ❌ 이전 (kvs_put_complete_code 사용 전에 선언 안 됨):
if (( kvs_put_complete_code != 0 )); then  # 미선언 변수 사용 ❌
    # ...
fi

# ✅ 수정됨:
kvs_put_complete_code=0  # STEP-7에서 먼저 초기화
if (( kvs_put_complete_code != 0 )); then  # 이제 정상 ✅
    # ...
fi
```

#### 3. 코드 중복 제거 - 커밋 e5e18e1
- 이전에 405-420줄에 malformed overlapping code 있었음
- 정리되어 이제 깔끔한 상태

#### 4. 실제 데이터 저장 로직 추가 - 커밋 14e292b
```bash
# STEP-6에 다음 코드 추가됨:
auto_discover_json=$(cat "$auto_discover_result_file")

if [ -n "$auto_discover_json" ]; then
    # 전체 JSON 저장
    kvs_put "lssn" "${lssn}" "auto_discover_result" "$auto_discover_json"
    
    # jq를 사용하여 구성요소 추출 및 저장
    servers_data=$(echo "$auto_discover_json" | jq '.servers // empty' 2>/dev/null)
    [ -n "$servers_data" ] && kvs_put "lssn" "${lssn}" "auto_discover_servers" "$servers_data"
    
    networks_data=$(echo "$auto_discover_json" | jq '.networks // empty' 2>/dev/null)
    [ -n "$networks_data" ] && kvs_put "lssn" "${lssn}" "auto_discover_networks" "$networks_data"
    
    services_data=$(echo "$auto_discover_json" | jq '.services // empty' 2>/dev/null)
    [ -n "$services_data" ] && kvs_put "lssn" "${lssn}" "auto_discover_services" "$services_data"
fi
```

### ⚠️ 미해결 문제들

#### 1. STEP-2 파일 확인 불일치
```
현재 상황:
- STEP-2 KVS: exists=false
- STEP-4 실행: 올바른 경로로 성공 ✅
- 명백한 모순: 파일이 없다고 했는데 STEP-4에서 실행됨?

의심 원인:
1. STEP-2의 파일 확인 로직이 다른 경로 사용
2. 경로 스트립 후 조건문이 경로 확인 전에 실행
3. 파일 권한 또는 접근성 문제
```

**다음 디버깅 단계**:
1. STEP-2에 상세 DEBUG 로깅 추가
   ```bash
   echo "DEBUG STEP-2: auto_discover_base_dir='$auto_discover_base_dir'" | tee -a "$log_file"
   echo "DEBUG STEP-2: auto_discover_script='$auto_discover_script'" | tee -a "$log_file"
   [ -f "$auto_discover_script" ] && echo "DEBUG: File exists" || echo "DEBUG: File NOT found"
   ```
2. 서버에서 직접 경로 확인
   ```bash
   [ -f /home/shinh/scripts/infraops01/giipAgentLinux/giipscripts/auto-discover-linux.sh ] && echo "EXISTS" || echo "NOT FOUND"
   ```

#### 2. 실제 발견 데이터가 KVS에 저장되지 않음
```
KVS 조회 결과 (13:21:11):
- auto_discover_result: ❌ 없음
- auto_discover_servers: ❌ 없음
- auto_discover_networks: ❌ 없음
- auto_discover_services: ❌ 없음

하지만:
- auto_discover_step_6_store_resul: file_size=7557 ✅ (메타데이터는 있음)

의심 원인들 (우선순위 순):
1. $auto_discover_json 변수가 비어있음
   → /tmp/auto_discover_result_XXXXX.json 파일은 생성되었지만 내용이 비어있을 수 있음
   
2. jq 명령어가 서버에 미설치
   → jq에 의존한 파싱이 실패하면서 에러 무시됨
   
3. kvs_put() 함수 호출 실패
   → 에러가 발생했지만 로깅되지 않음
   
4. 파일 읽기 권한 문제
   → /tmp 파일 접근 불가능
```

**다음 디버깅 단계**:
1. jq 설치 확인
   ```bash
   command -v jq || echo "jq NOT installed"
   ```

2. 결과 파일 내용 확인 (STEP-6에서)
   ```bash
   echo "DEBUG STEP-6: File size=$(wc -c < "$auto_discover_result_file")" | tee -a "$log_file"
   echo "DEBUG STEP-6: File content (first 200 chars):" | tee -a "$log_file"
   head -c 200 "$auto_discover_result_file" | tee -a "$log_file"
   ```

3. kvs_put 명령어 출력 확인
   ```bash
   kvs_result=$(kvs_put "lssn" "${lssn}" "auto_discover_result" "$auto_discover_json")
   echo "DEBUG STEP-6: kvs_put result code=$?" | tee -a "$log_file"
   echo "DEBUG STEP-6: kvs_put output: $kvs_result" | tee -a "$log_file"
   ```

---

## 📊 최근 KVS 데이터 (13:21:11 조회)

### STEP 진행 상황
| STEP | 상태 | 메모 |
|------|------|------|
| STEP-1 | ✅ | sk_length=32, apiaddrv2_set=true |
| STEP-2 | ⚠️ | path set, but exists=false (모순) |
| STEP-3 | ✅ | action=storing_init_marker |
| STEP-4 | ✅ | script path correct, 정상 실행 |
| STEP-5 | ✅ | result_file=/tmp/auto_discover_result_XXXXX.json |
| STEP-6 | ✅ | file_size=7557 (메타데이터만) |
| STEP-7 | ✅ | status=completed |

### 저장된 데이터
- ✅ STEP 메타데이터: 모두 저장됨
- ❌ 실제 발견 데이터: 없음
- ❌ 구성요소 데이터: 없음

---

## 🔧 현재 코드 상태

### giipAgent3.sh 변경사항

**STEP-2 (경로 확인) - 라인 295-309**:
```bash
local auto_discover_base_dir="$SCRIPT_DIR"
if [[ "$auto_discover_base_dir" == */lib ]]; then
    auto_discover_base_dir="${auto_discover_base_dir%/lib}"
fi
local auto_discover_script="${auto_discover_base_dir}/giipscripts/auto-discover-linux.sh"

if [ -f "$auto_discover_script" ]; then
    kvs_put "lssn" "${lssn}" "auto_discover_step_2_scriptpath" \
        "{\"path\": \"$auto_discover_script\", \"exists\": true}"
else
    kvs_put "lssn" "${lssn}" "auto_discover_step_2_scriptpath" \
        "{\"path\": \"$auto_discover_script\", \"exists\": false}"
    log_auto_discover_error "auto-discover script not found at: $auto_discover_script"
fi
```

**STEP-6 (결과 저장) - 라인 360-400**:
```bash
if [ -f "$auto_discover_result_file" ]; then
    # 파일 크기 기록
    local file_size=$(wc -c < "$auto_discover_result_file")
    kvs_put "lssn" "${lssn}" "auto_discover_step_6_store_resul" \
        "{\"action\": \"storing_results\", \"file_size\": $file_size, \"timestamp\": \"$timestamp\"}"
    
    # 실제 JSON 데이터 저장 (커밋 14e292b)
    local auto_discover_json=$(cat "$auto_discover_result_file")
    if [ -n "$auto_discover_json" ]; then
        kvs_put "lssn" "${lssn}" "auto_discover_result" "$auto_discover_json"
        
        # jq를 사용하여 구성요소 파싱
        servers_data=$(echo "$auto_discover_json" | jq '.servers // empty' 2>/dev/null)
        [ -n "$servers_data" ] && kvs_put "lssn" "${lssn}" "auto_discover_servers" "$servers_data"
        
        networks_data=$(echo "$auto_discover_json" | jq '.networks // empty' 2>/dev/null)
        [ -n "$networks_data" ] && kvs_put "lssn" "${lssn}" "auto_discover_networks" "$networks_data"
        
        services_data=$(echo "$auto_discover_json" | jq '.services // empty' 2>/dev/null)
        [ -n "$services_data" ] && kvs_put "lssn" "${lssn}" "auto_discover_services" "$services_data"
    fi
fi
```

**STEP-7 (초기화 수정) - 라인 376**:
```bash
# ✅ kvs_put_complete_code 이제 먼저 초기화됨
kvs_put_complete_code=0

if (( kvs_put_complete_code != 0 )); then
    # ...
fi
```

---

## 🎬 다음 실행 계획

### Phase 1: 디버깅 (우선순위 높음)
1. **jq 설치 확인**
   ```bash
   ssh shinh@infraops01 'command -v jq || echo "NOT INSTALLED"'
   ```

2. **결과 파일 내용 확인**
   - STEP-6에 DEBUG 로깅 추가
   - 다음 실행 시 `/tmp/auto_discover_result_*.json` 파일 내용 확인

3. **kvs_put 에러 로깅**
   - STEP-6에서 kvs_put의 반환값 캡처
   - 실패 여부 로깅

### Phase 2: 검증 (우선순위 중간)
1. STEP-2 파일 확인 로직 재검토
2. 경로 스트립 로직 재검증

### Phase 3: 최종 확인 (우선순위 낮음)
1. 전체 데이터 흐름 재검증
2. 에러 핸들링 개선

---

## 📝 커밋 히스토리

| 커밋 | 내용 | 상태 |
|------|------|------|
| e5e18e1 | lib 스트립 로직 추가, 변수 초기화 순서 정정, 코드 정리 | ✅ 배포됨 |
| 14e292b | 실제 JSON 데이터 저장, jq 파싱 추가 | ✅ 배포됨 |

---

## 💡 핵심 통찰

1. **경로 문제는 해결됨**: lib 중복 제거 후 스크립트 실행 성공
2. **데이터 수집도 진행 중**: 7557바이트 결과 파일 생성됨
3. **실제 저장은 미확인**: JSON이 KVS에 기록되지 않은 이유를 파악해야 함
4. **다음 실행에서 진실이 나옴**: DEBUG 로깅으로 정확한 문제 지점 파악 가능

---

## 📌 상태 추적

**최종 목표**: 
✅ 경로 오류 해결 → ✅ 스크립트 실행 → ⏳ **데이터 저장 확인** ← 현재 위치 → 전체 검증

**현재 진행률**: ~60% (경로 고정 후 데이터 저장 단계 디버깅 중)

**예상 완료**: 다음 서버 실행 후 DEBUG 로그 분석 시 파악 가능
