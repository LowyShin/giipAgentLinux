# ✅ Auto-Discover 멈춘 지점 확인 보고서

**진단 날짜**: 2025-11-26  
**진단 대상**: LSSN 71240  
**진단 방법**: KVS 데이터 실제 조회 및 분석  
**결론**: **STEP-2에서 멈춤 → auto-discover 스크립트를 찾지 못함**

---

## 📊 KVS 데이터 흐름 분석

### ✅ 정상 진행된 단계

```
STEP-1: Configuration Check ✅
├─ 타임스탬프: 2025-11-26 12:15:04 (UTC+9)
├─ sk_length: 32 (✅ 설정됨)
└─ apiaddrv2_set: true (✅ 설정됨)
   → 결론: 필수 변수가 모두 설정됨

        ↓

STEP-2: Script Path Check ❌ (첫번째 멈춤 지점)
├─ 타임스탬프: 2025-11-26 12:15:04
├─ path: /home/shinh/scripts/infraops01/giipAgentLinux/lib/lib/giipscripts/auto-discover-linux.sh
├─ exists: false ❌ (파일 없음)
└─ 오류 로그: "auto-discover script not found"
   → 문제: 경로 오류 (lib가 2번 들어감!)

        ↓

STEP-3: Initialize KVS Records ✅
├─ 타임스탐프: 2025-11-26 12:15:05
└─ action: storing_init_marker
   → 결론: 에러가 있어도 계속 진행 (에러 처리가 제대로 안 됨)

        ↓

STEP-4: Execute Auto-Discover Script ❌ (두번째 멈춤 지점)
├─ 타임스탐프: 2025-11-26 12:15:05
├─ script: /home/shinh/scripts/infraops01/giipAgentLinux/lib/lib/giipscripts/auto-discover-linux.sh
├─ exit_code: 127 ❌ (127 = "command not found")
└─ error_log: "" (에러 로그 없음)
   → 문제: 스크립트를 실행하려고 했으나 파일을 찾지 못함

        ↓

STEP-5: Validate Result File ❌ (세번째 멈춤 지점)
├─ 타임스탐프: 2025-11-26 12:15:06
├─ result_file: /tmp/auto_discover_result_8074.json
└─ 오류: "Result file is empty or does not exist"
   → 문제: STEP-4가 실패했으므로 결과 파일 생성 안 됨

        ↓

STEP-6: Store Result to KVS ❌
├─ 타임스탐프: 2025-11-26 12:15:07
└─ file_size: 0 (결과 없음)
   → 문제: 저장할 데이터 없음

        ↓

STEP-7: Store Complete Marker ✅
├─ 타임스탐프: 2025-11-26 12:15:08
└─ status: completed
   → 결론: 완료 마커는 저장됨 (문제: 실제로 완료되지 않았는데!)

        ↓

COMPLETE: Auto-Discover Phase Complete ✅
└─ all_steps: "PASSED" ⚠️ (거짓 상태!)
   → 문제: 실패했는데 PASSED로 표시됨
```

---

## 🔴 **핵심 원인: 파일 경로 오류**

### 잘못된 경로 분석

**현재 저장되는 경로**:
```
/home/shinh/scripts/infraops01/giipAgentLinux/lib/lib/giipscripts/auto-discover-linux.sh
                                                      ↑↑
                                                   lib 중복!
```

**경로 분해**:
- `/home/shinh/scripts/infraops01/` = 기본 경로
- `giipAgentLinux/` = 프로젝트 폴더
- `lib/` = 첫 번째 lib 폴더 (정상)
- `lib/` = **두 번째 lib 폴더 (오류!)** ❌
- `giipscripts/` = 스크립트 폴더
- `auto-discover-linux.sh` = 파일명

### 정상 경로 (예상)

```bash
# 옵션 1: 직접 경로
/home/shinh/scripts/infraops01/giipAgentLinux/giipscripts/auto-discover-linux.sh

# 옵션 2: lib 경로 사용
/home/shinh/scripts/infraops01/giipAgentLinux/lib/giipscripts/auto-discover-linux.sh
```

---

## 📈 반복되는 패턴 확인

### 최근 3회 실행 모두 동일한 오류

| 실행 시간 | STEP-1 | STEP-2 | STEP-3 | STEP-4 | STEP-5 | STEP-6 | STEP-7 |
|-----------|--------|--------|--------|--------|--------|--------|--------|
| 12:15:04 | ✅ | ❌ | ⚠️ | ❌ | ❌ | ⚠️ | ✅ |
| 12:10:04 | ✅ | ❌ | ⚠️ | ❌ | ❌ | ⚠️ | ✅ |
| 12:05:04 | ✅ | ❌ | ⚠️ | ❌ | ❌ | ⚠️ | ✅ |

**패턴 해석**:
- ✅ STEP-1: 설정 정상 (변수 설정 OK)
- ❌ STEP-2: **항상 파일 찾지 못함** (경로 고정된 오류)
- ⚠️ STEP-3: 에러가 있어도 계속 진행 (오류 처리 미흡)
- ❌ STEP-4: STEP-2의 오류로 인해 스크립트 실행 실패
- ❌ STEP-5-6: STEP-4 실패의 연쇄 결과
- ✅ STEP-7: 마지막 마커만 저장 (상태 표시 오류)

---

## 🎯 **결론: DB에 저장된 것 vs 저장되지 않은 것**

### ✅ KVS에 저장된 데이터

```
STEP-1: auto_discover_step_1_config ✅ 저장됨
        └─ Configuration Check 정보 포함

STEP-2: auto_discover_step_2_scriptpath ✅ 저장됨
        └─ 잘못된 경로 + exists: false 기록됨

STEP-3: auto_discover_step_3_init ✅ 저장됨
        └─ Initialize KVS Records 정보 포함

STEP-4: auto_discover_step_4_execution ✅ 저장됨
        └─ 스크립트 경로 (잘못된 경로) 기록됨

STEP-5: auto_discover_step_5_validation ✅ 저장됨
        auto_discover_error_log ✅ 저장됨
        └─ "Result file is empty" 오류 메시지

STEP-6: auto_discover_step_6_store_resul ✅ 저장됨
        └─ file_size: 0 (데이터 없음)

STEP-7: auto_discover_step_7_complete ✅ 저장됨
        auto_discover_complete ✅ 저장됨
        └─ all_steps: "PASSED" (거짓!)
```

### ❌ DB에 저장되지 않은 데이터

```
auto_discover_init ❌
├─ 의도: 발견 프로세스 시작
└─ 현재: 저장되지 않음 (또는 다른 이름으로 저장됨)

auto_discover_result ❌
├─ 의도: 최종 발견 결과 (수집한 정보)
└─ 현재: 저장되지 않음 (결과 파일이 없기 때문)

auto_discover_full_result ❌
├─ 의도: 전체 발견 결과 상세 데이터
└─ 현재: 저장되지 않음
```

---

## 🔧 **즉시 해결 방법**

### 근본 원인: 경로 중복 (lib 2번)

**파일 위치 확인 필요**:
```bash
# 서버에서 실행
find /home/shinh/scripts/infraops01 -name "auto-discover-linux.sh" -type f

# 실제 경로 출력 예시:
# /home/shinh/scripts/infraops01/giipAgentLinux/giipscripts/auto-discover-linux.sh
# /home/shinh/scripts/infraops01/giipAgentLinux/lib/giipscripts/auto-discover-linux.sh
```

**해결책**:
1. **STEP-2에서 경로 결정 로직 확인** (어디서 "lib/lib" 패턴이 생기는지)
2. **정확한 경로로 수정**
3. **STEP-4 실행 성공 확인** → 결과 파일 생성 확인
4. **STEP-6에서 데이터가 KVS에 저장되는지 확인**

---

## 📋 상태 요약 테이블

| 항목 | 현재 상태 | 원인 | 영향 |
|------|----------|------|------|
| **데이터 수집** | ✅ 완료됨 (코드는 정상) | N/A | 안 들어남 |
| **데이터 저장** | ❌ DB에 저장 실패 | 경로 오류 → 스크립트 미실행 | **서버 정보 없음** |
| **에러 로깅** | ⚠️ 부분 저장됨 | STEP-2부터 오류 기록됨 | 원인 파악 가능 |
| **완료 표시** | ❌ 거짓 상태 | STEP-7에서 무조건 PASSED | 사용자 혼란 야기 |

---

## 🔗 관련 KVS 필드

**오류 정보가 저장된 곳**:
- `auto_discover_step_2_scriptpath`: 파일 존재 여부 (false)
- `auto_discover_error_log` (STEP-2): "auto-discover script not found"
- `auto_discover_error_log` (STEP-4): "Script failed with non-zero exit code" (exit_code: 127)
- `auto_discover_error_log` (STEP-5): "Result file is empty or does not exist"

**실제 데이터가 없는 이유**:
- STEP-4가 실패 → 결과 파일 생성 안 됨
- STEP-6이 실행되지만 결과 파일이 없으므로 저장할 데이터 없음

---

## 📌 다음 단계

### 1️⃣ 즉시 조치
```bash
# 서버에서 확인
find /home/shinh/scripts/infraops01 -name "auto-discover-linux.sh"

# 경로 수정 (giipAgent3.sh 또는 관련 스크립트 수정)
# "lib/lib" → "lib" 또는 정확한 경로 설정
```

### 2️⃣ 검증
```bash
# 수정 후 STEP-4 exit_code가 0이 되는지 확인
pwsh .\mgmt\check-latest.ps1 -Lssn 71240 -Minutes 1
# auto_discover_step_4_execution 확인 → exit_code 변화
```

### 3️⃣ 최종 확인
```bash
# 데이터가 저장되는지 확인
pwsh .\mgmt\query-kvs.ps1 -KFactor "auto_discover_result" -KKey "71240"
# 또는
pwsh .\mgmt\query-kvs.ps1 -KFactor "auto_discover_*" -KKey "71240"
```

---

## 📝 핵심 발견사항 요약

| # | 발견사항 | 상태 | 메모 |
|----|----------|------|------|
| 1 | **auto-discover 스크립트 찾지 못함** | 🔴 중대 | 경로 오류 (lib 중복) |
| 2 | 필수 변수 설정 됨 | 🟢 정상 | sk, apiaddrv2 모두 O |
| 3 | 데이터 수집 코드 | 🟢 정상 | STEP-4 실패할 때까지 스크립트 도달 가능 |
| 4 | DB 저장 메커니즘 | 🟢 정상 | 다른 STEP 데이터는 잘 저장됨 |
| 5 | 오류 정보 기록 | 🟢 정상 | 각 STEP에서 오류 메시지 저장 |
| 6 | **완료 상태 표시 오류** | 🟠 경고 | STEP-7에서 무조건 PASSED 표시 |

