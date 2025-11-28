# Queue Get 시스템 전반적인 문제 분석

## 현재 상황
- ✅ 설정 파일 경로 수정 완료
- ✅ 환경 변수 export 완료
- ⚠️ **다른 잠재적 문제들이 존재**

---

## 📋 발견된 문제들

### 1️⃣ **API 응답 파싱 문제 (높은 위험도)**

#### 문제 코드 (cqe.sh)
```bash
# jq parsing
local script=$(jq -r '.data[0].ms_body // .ms_body // empty' "$temp_response" 2>/dev/null)

# sed/grep parsing fallback
local script=$(echo "$normalized" | sed -n 's/.*"ms_body"\s*:\s*"\([^"]*\)".*/\1/p' | head -1)
echo "$script" | sed 's/\\n/\n/g' > "$output_file"
```

#### 문제점
- **JSON 키 위치 불명확**: `.data[0].ms_body` vs `.ms_body` 중 어느 것이 맞는지?
- **실제 API 응답 형식을 모름**: API가 어떤 JSON 구조를 반환하는가?
- **Sed 파싱 너무 단순**: 특수문자나 개행 있으면 실패
- **이스케이프 처리**: `\\n` → `\n` 변환이 정말 필요한가?

#### 테스트 필요
```bash
# API 응답을 실제로 받아서 확인
curl -s -X POST "https://giipfaw.azurewebsites.net/api/giipApiSk2?code=..." \
  -d "..." | jq .
```

---

### 2️⃣ **Temp 파일 정리 문제 (보안/성능)**

#### 문제 코드
```bash
# cqe.sh에서
local temp_response="/tmp/queue_response_$$.json"
rm -f /tmp/queue_response_* 2>/dev/null  # 모든 queue_response 파일 삭제!

# test-queue-get.sh에서
local wrapper_script="/tmp/queue_wrapper_$$.sh"
rm -f "$wrapper_script"  # 스크립트 삭제는 되지만 동시 실행 시 충돌 가능
```

#### 위험성
- `rm -f /tmp/queue_response_*` **현재 진행 중인 다른 프로세스의 파일도 삭제 가능!**
- 예: 프로세스 A가 파일 읽는 중 → 프로세스 B가 `rm -f` 실행 → A 오류 발생
- Temp 파일 충돌: 동시에 여러 queue_get 실행 시 PID가 같을 수 있음

#### 개선 필요
```bash
# 개선: 자신의 파일만 삭제
rm -f "/tmp/queue_response_$$.json"  # 정확한 파일명만

# 더 안전: umask 설정으로 소유권 보호
# 또는 사용자별 임시 폴더 사용: /tmp/$USER/giipagent/
```

---

### 3️⃣ **출력 파일 권한 문제**

#### 문제
```bash
echo "$script" > "$output_file"  # 기본 권한으로 파일 생성
```

- Queue 스크립트는 민감한 정보 포함 가능
- 기본 umask로 생성되면 다른 사용자도 읽을 수 있음
- 세큐어 프로세싱 요구사항 충족 안 됨

#### 개선
```bash
# 파일 생성 후 권한 설정
echo "$script" > "$output_file"
chmod 600 "$output_file"  # 소유자만 읽기 가능
```

---

### 4️⃣ **Timeout 처리 문제**

#### 문제 코드 (test-queue-get.sh)
```bash
timeout 30 bash "$wrapper_script" ... 2>&1
local exit_code=$?
```

#### 문제점
- **Exit code 127**: timeout 실패도 127 (wrapper도 127)
- **구분 불가**: timeout 초과인지 wrapper 실패인지 알 수 없음
- **에러 로그 섞임**: stderr 혼합으로 에러 원인 파악 어려움

#### 개선
```bash
local timeout_file="/tmp/queue_timeout_$$.txt"
rm -f "$timeout_file"

timeout 30 bash "$wrapper_script" ... 2>"${timeout_file}.err"
local exit_code=$?

if [ $exit_code -eq 124 ]; then
    echo "❌ TIMEOUT: queue_get took more than 30 seconds"
    exit 124
elif [ $exit_code -ne 0 ]; then
    cat "${timeout_file}.err"
    exit $exit_code
fi

rm -f "${timeout_file}.err"
```

---

### 5️⃣ **환경 변수 누출 (보안)**

#### 문제
```bash
export sk apiaddrv2 apiaddrcode lssn  # 환경 변수로 내보냄
```

- `ps aux | grep queue_get` 실행 시 명령줄에 API 키 노출
- 다른 사용자가 프로세스 정보로 키 확인 가능
- Log 파일에 전체 URL이 기록될 수 있음

#### 개선
```bash
# 환경 변수 대신 설정 파일 경로만 전달
# 또는 wrapper에서만 직접 파일 로드 (export 불필요)
unset sk apiaddrv2 apiaddrcode  # 테스트 후 정리
```

---

### 6️⃣ **에러 메시지 일관성**

#### 문제
```bash
# 다양한 형식의 에러 메시지
echo "[queue_get] ⚠️  Missing required..."
echo "[wrapper] ❌ FAILED: ..."
echo "❌ Config file not found..."
```

- 일관된 형식 없음
- 프로그래밍 방식 파싱 어려움 (stderr에서 자동 감지)
- 문제 추적이 어려움

#### 개선
```bash
# 통일된 형식: [LEVEL] [COMPONENT] message
echo "[ERROR] [cqe.queue_get] Missing required parameters" >&2
echo "[WARN] [test] jq not found" >&2
echo "[INFO] [cqe] API response received" >&2
```

---

## 🎯 우선순위별 해결책

### P0 (긴급)
1. **API 응답 형식 확인**: 실제 API 응답을 받아서 JSON 구조 확인
2. **Temp 파일 안전성**: `rm -f /tmp/queue_response_*` 개선

### P1 (중요)
3. **출력 파일 권한**: chmod 600 추가
4. **Timeout 에러 구분**: Exit code 처리 개선
5. **환경 변수 보안**: export 대신 파일 기반 전달

### P2 (개선)
6. **에러 메시지 통일**: 형식 표준화
7. **디버그 모드**: `DEBUG=1` 플래그 추가

---

## 다음 단계

1. **즉시**: API 응답 형식 확인
   ```bash
   bash ./tests/test-queue-get.sh 71221 p-cnsldb01m Linux
   # 성공/실패 상관없이 디버그 출력 확인
   ```

2. **수정**: P0, P1 항목들 한 번에 해결

3. **테스트**: 동시 실행 테스트
   ```bash
   for i in {1..5}; do 
     ./tests/test-queue-get.sh 71221 p-cnsldb01m Linux &
   done
   wait
   ```
