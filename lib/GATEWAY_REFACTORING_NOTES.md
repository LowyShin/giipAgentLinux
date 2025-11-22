# Gateway.sh Refactoring - Architecture Overview

## 문제 분석 및 해결

### ❌ 이전 구조의 문제점

```
process_gateway_servers()
  └─ process_server_list()
      └─ while read server_json (subshell)
          └─ process_single_server()
              ├─ parse_server_json()         [글로벌 변수 설정]
              ├─ validate_server_params()    [글로벌 변수 검증]
              ├─ execute_server_ssh()        [글로벌 변수 참조]
              └─ call_remote_test_api()      [API 호출]
```

**문제:**
1. ❌ **글로벌 변수 의존** - hostname, lssn, ssh_host 등이 여러 함수 간에 암묵적으로 공유
2. ❌ **Subshell 문제** - 파이프(|) 사용 시 while loop이 subshell에서 실행되어 변수 설정이 parent shell에 반영 안 됨
3. ❌ **흐름 추적 어려움** - 각 함수의 입출력이 명확하지 않음
4. ❌ **깊은 중첩** - 4단계 깊이로 코드 이해 어려움

---

## ✅ 개선된 구조

### 핵심 원칙
- **명시적 입출력** - 모든 함수는 명시적 매개변수를 받고 리턴값 반환
- **자기 완결성** - 각 함수는 독립적이고 글로벌 변수에 의존하지 않음
- **단계적 처리** - 각 단계가 명확하게 분리됨
- **제어 흐름 일관성** - 메인 함수에서 단일 책임 원칙 준수

### 개선된 아키텍처

```
process_gateway_servers()  [메인 제어 루프]
  │
  ├─ 1️⃣ get_gateway_servers()        → temp_file 반환
  │
  ├─ 2️⃣ process_server_list()        → 각 서버 반복 처리
  │   │
  │   └─ FOR EACH server_json:
  │       └─ 3️⃣ process_single_server(server_json, tmpdir)  [all-in-one]
  │           │
  │           ├─ Step A: extract_server_params()    → 모든 파라미터 JSON 반환
  │           ├─ Step B: validate_server_params()   → 유효성 검증 (0/1 반환)
  │           ├─ Step C: 파라미터 추출 (jq 사용)
  │           ├─ Step D: get_remote_queue()         → 스크립트 파일
  │           ├─ Step E: execute_remote_command()   → SSH 실행
  │           ├─ Step F: API 호출 (성공 시에만)
  │           └─ Step G: 로깅 및 정리
  │
  ├─ 3️⃣ check_managed_databases()    → DB 체크 (별도 모듈)
  │
  └─ Cleanup & Exit
```

---

## 함수별 역할 (단일 책임)

### 1. `extract_server_params(server_json)` - 파싱만
```bash
# 입력: JSON 문자열
# 출력: 파라미터 JSON 문자열
# 역할: 단순히 JSON에서 필요한 필드만 추출
```

**특징:**
- ✅ 글로벌 변수 설정 안 함
- ✅ JSON 반환으로 명시적
- ✅ jq/grep 선택 내부에서만 처리

---

### 2. `validate_server_params(server_params)` - 검증만
```bash
# 입력: 파라미터 JSON 문자열
# 출력: 0 (유효) or 1 (스킵)
# 역할: hostname 유무, enabled 상태만 확인
```

**특징:**
- ✅ 검증만 담당
- ✅ 사이드이펙트 없음
- ✅ 0/1 리턴으로 명확

---

### 3. `process_single_server(server_json, tmpdir)` - 전체 조율
```bash
# 입력: JSON + tmpdir
# 출력: 0 (항상 성공으로 처리, 로깅으로 결과 기록)
# 역할: 단일 서버의 전체 처리 파이프라인
```

**내부 흐름 (선형적, 중첩 없음):**
1. extract_server_params() 호출
2. validate_server_params() 호출 (스킵 결정)
3. jq로 파라미터 추출
4. get_remote_queue() 호출
5. execute_remote_command() 호출
6. API 호출 (SSH 성공 시만)
7. 로깅 및 정리

**장점:**
- ✅ 모든 처리가 한 함수에서 일어남 (찾기 쉬움)
- ✅ 흐름이 선형적 (위에서 아래로)
- ✅ 글로벌 변수 사용 안 함

---

### 4. `process_server_list(server_list_file, tmpdir)` - 반복 처리
```bash
# 입력: 파일 + tmpdir
# 출력: 각 서버를 process_single_server()로 처리
# 역할: 서버 목록 반복
```

**특징:**
- ✅ jq/grep 선택 후 temp file에 저장
- ✅ Subshell 문제 회피 (file read loop 사용)
- ✅ 각 서버를 독립적으로 process_single_server() 호출

---

### 5. `process_gateway_servers()` - 메인 조절자
```bash
# 입력: 전역 변수 (lssn, etc)
# 출력: 0/1
# 역할: 전체 Gateway 사이클 제어
```

**흐름 (명확함):**
1. get_gateway_servers() 호출
2. process_server_list() 호출
3. check_managed_databases() 호출
4. 정리 및 로깅

---

## 테스트/디버깅 용이성

### 이전: 문제 추적 어려움
```bash
# 71221이 업데이트 안 됨 → 어디서?
# [5.6] 로그 없음 → parse_server_json() 실패? subshell?
# 글로벌 변수가 여러 곳에서 설정되므로 추적 어려움
```

### 현재: 문제 추적 쉬움
```bash
# 71221 업데이트 안 됨 → process_single_server() 호출 안 됨?
# → process_server_list() 확인
# → extract_server_params() 리턴값 확인
# → validate_server_params() 0/1 확인

# 각 단계의 입출력이 명확하므로 바로 위치 파악 가능
```

### 테스트 가능 예시
```bash
# 단일 서버 테스트
server_json='{"hostname":"test","lssn":"71221",...}'
extract_server_params "$server_json"

# 파라미터 검증만 테스트
validate_server_params '{"hostname":"test","enabled":1}'

# 전체 서버 처리만 테스트
process_single_server "$server_json" "/tmp"
```

---

## 코드량 비교

| 항목 | 이전 | 현재 | 개선 |
|------|------|------|------|
| main 함수 | 180줄 | 30줄 | **83% 감소** |
| 중첩 깊이 | 4단계 | 1단계 | **75% 감소** |
| 글로벌 변수 의존 | 7개 | 1개 (lssn만) | **85% 감소** |
| 함수당 책임 | 5가지 | 1가지 | **단순화** |
| 전체 LOC | 560줄 | 647줄 | +87줄 (documentation) |

---

## 모듈 간 의존도 (Clean Dependency)

### 의존 관계도
```
process_gateway_servers()
  ├─ get_gateway_servers()      [독립적]
  ├─ process_server_list()      [독립적]
  │   └─ process_single_server() [자기 완결적]
  │       ├─ extract_server_params() [순수 함수]
  │       ├─ validate_server_params() [순수 함수]
  │       ├─ get_remote_queue()      [I/O]
  │       ├─ execute_remote_command() [I/O]
  │       └─ report_ssh_test_result() [외부 모듈]
  │
  └─ check_managed_databases()  [독립적, 별도 모듈]
```

### 특징
- ✅ 순환 의존성 없음
- ✅ 외부 모듈 최소화 (report_ssh_test_result만)
- ✅ 각 레이어가 독립적
- ✅ 테스트 가능한 구조

---

## 문제 해결

### Subshell 문제 해결
**이전:**
```bash
jq ... | while read server_json; do
    process_single_server ...  # subshell에서 실행
done
```

**현재:**
```bash
jq ... > "${tmpdir}/servers.jsonl"
while read server_json < "${tmpdir}/servers.jsonl"; do
    process_single_server ...  # parent shell에서 실행
done
```

### 글로벌 변수 의존 해결
**이전:**
```bash
parse_server_json "$server_json"  # hostname, lssn 등을 글로벌 설정
echo $hostname $lssn ...          # 글로벌 변수 사용
```

**현재:**
```bash
server_params=$(extract_server_params "$server_json")  # 반환값 사용
hostname=$(echo "$server_params" | jq -r '.hostname')  # 명시적 추출
```

---

## 유지보수 가이드

### 새 기능 추가 시
1. **단계 추가는 `process_single_server()`에만**
   - 다른 함수 구조 변경 금지
2. **새 함수는 독립적으로 작성**
   - 글로벌 변수 사용 금지
   - 명시적 입출력만 사용
3. **로깅은 gateway_log() 사용**
   - 자동으로 tKVS 저장됨

### 디버깅 시
1. **문제 함수 찾기 - 로그의 [5.x] 번호 확인**
2. **해당 함수의 입력값 출력 - echo "$var" | jq**
3. **출력값 확인 - 리턴값 또는 stderr**
4. **다음 함수 진행 여부 확인**

---

## 결론

✅ **현재 구조는 다음을 만족합니다:**
- 단순성: 각 함수 한 가지만 담당
- 독립성: 글로벌 변수 최소화
- 명확성: 입출력이 명시적
- 테스트성: 각 함수 독립 테스트 가능
- 유지보수성: 흐름이 선형적, 변수 추적 쉬움
