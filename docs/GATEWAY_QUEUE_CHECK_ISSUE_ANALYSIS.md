# Gateway 자신의 큐 체크 미적용 분석

**작성일**: 2025-11-22  
**상태**: 📋 분석 완료 → 해결책 제시

---

## 1. 문제 현상

Gateway 서버(71240)의 LSChkdt가 업데이트되지 않음:
- **예상**: Gateway도 CQEQueueGet API 호출 → pApiCQEQueueGetbySk SP 실행 → LSChkdt 자동 업데이트
- **실제**: Gateway의 LSChkdt 고정 (마지막 업데이트: 2025/11/22 10:30:03)
- **원인**: 코드 추가했지만 실행되지 않음

---

## 2. 근본 원인 분석

### 2.1 코드 추가 위치 (gateway.sh 줄 633-660)
```bash
process_gateway_servers() {
    # [5.3.1] 🟢 Gateway 자신의 큐 처리 로직 추가됨
    if type fetch_queue >/dev/null 2>&1; then
        fetch_queue "$lssn" "$hn" "$os" "$gateway_queue_file"
        # ... 실행 코드 ...
    else
        gateway_log "⚠️ " "[5.3.1-WARN]" "fetch_queue 함수 미로드"
    fi
```

### 2.2 근본 원인 발견

**`fetch_queue()` 함수가 로드되지 않음!**

#### 모듈 로드 체인:
```
giipAgent3.sh (Gateway 모드)
  ├─ . "${LIB_DIR}/db_clients.sh"
  ├─ . "${LIB_DIR}/gateway.sh"  ← gateway.sh 로드됨
  │
  └─ gateway.sh 내부 구조:
      ├─ ssh_connection_logger.sh 로드 ✅
      ├─ remote_ssh_test.sh 로드 ✅
      ├─ kvs.sh 로드 ✅
      │
      └─ ❌ normal.sh 로드 안함!  ← 이게 문제!
```

#### 결과:
- `fetch_queue()` 함수는 **normal.sh에 정의됨**
- gateway.sh는 normal.sh를 로드하지 않음
- `if type fetch_queue >/dev/null 2>&1` 체크 **실패**
- [5.3.1-WARN] 로그만 출력됨 (함수 미로드)
- Gateway 큐 체크 코드 **실행되지 않음**

---

## 3. 증거

### 3.1 gateway.sh 로드 구조 (현재)
```bash
# 줄 8-34: 로드되는 모듈들
. "${SCRIPT_DIR_GATEWAY_SSH}/ssh_connection_logger.sh"
. "${SCRIPT_DIR_GATEWAY_SSH}/remote_ssh_test.sh"
. "${SCRIPT_DIR_GATEWAY_SSH}/kvs.sh"

# 👀 normal.sh 로드 명령 없음!
```

### 3.2 fetch_queue() 정의 위치
```
normal.sh 줄 14: fetch_queue() 정의
  ├─ CQEQueueGet API 호출
  ├─ pApiCQEQueueGetbySk SP 트리거 (LSChkdt 업데이트)
  └─ 응답 처리
```

### 3.3 실행 흐름 비교

**Normal Mode (정상 작동)**:
```
giipAgent3.sh (Normal Mode)
  ├─ . "${LIB_DIR}/normal.sh"  ✅ 명시적 로드
  └─ fetch_queue() 호출 성공
      ├─ CQEQueueGet API 호출
      └─ LSChkdt = GETDATE() 자동 업데이트 ✅
```

**Gateway Mode (현재, 미작동)**:
```
giipAgent3.sh (Gateway Mode)
  ├─ . "${LIB_DIR}/gateway.sh"  로드
  │   ├─ ssh_connection_logger.sh 로드
  │   ├─ remote_ssh_test.sh 로드
  │   └─ kvs.sh 로드
  │       (normal.sh 로드 안함 ❌)
  │
  └─ process_gateway_servers()
      ├─ if type fetch_queue ... (실패)
      ├─ else: [5.3.1-WARN] "fetch_queue 함수 미로드"
      └─ Gateway 큐 체크 스킵 ❌
```

---

## 4. 해결 방법

### 4.1 솔루션: gateway.sh에 normal.sh 모듈 로드 추가

**위치**: gateway.sh 줄 34 (kvs.sh 로드 직후)

**추가할 코드**:
```bash
# Load normal mode queue fetching module (for Gateway self-queue processing)
if [ -f "${SCRIPT_DIR_GATEWAY_SSH}/normal.sh" ]; then
    . "${SCRIPT_DIR_GATEWAY_SSH}/normal.sh"
else
    echo "[gateway.sh] ⚠️  Warning: normal.sh not found" >&2
    # Define stub function to prevent errors
    fetch_queue() {
        echo "[gateway.sh] ⚠️  WARNING: fetch_queue stub called (normal.sh not loaded)" >&2
        return 1
    }
fi
```

### 4.2 왜 이 방법이 필요한가?

1. **모듈화 원칙 준수**: 
   - 필요한 함수는 선언적으로 로드해야 함
   - `type ... >/dev/null 2>&1` 체크만으로는 부족

2. **Gateway 모드의 이중 책임**:
   - 원래: 원격 서버 관리 (RemoteServerSSHTest)
   - 추가: 자신의 큐도 처리 (CQEQueueGet)
   - 두 기능 모두 필요 → 두 라이브러리 모두 로드해야 함

3. **일관성 유지**:
   - Normal Mode: normal.sh 로드 → fetch_queue() 사용
   - Gateway Mode: 이제 gateway.sh + normal.sh 모두 로드 → 동일한 fetch_queue() 사용

### 4.3 기대 효과

수정 후:
```
Gateway 서버 (71240)
  ├─ process_gateway_servers() 시작
  ├─ [5.3.1] fetch_queue() 호출 성공 ✅
  │  └─ CQEQueueGet API → LSChkdt 업데이트 ✅
  ├─ [5.5] 원격 서버 목록 조회
  ├─ [5.6~5.11] 각 원격 서버 처리 (SSH Test)
  └─ [5.12~5.13] 사이클 완료

결과: Gateway LSChkdt = GETDATE() (실시간 업데이트) ✅
```

---

## 5. 근거 자료

### 파일 참조
- **gateway.sh**: 줄 8-34 (모듈 로드 섹션)
- **gateway.sh**: 줄 633-660 (process_gateway_servers 함수에 추가된 [5.3.1] 코드)
- **normal.sh**: 줄 14 (fetch_queue 함수 정의)
- **giipAgent3.sh**: 줄 220-280 (Gateway Mode 진입점)

### 데이터베이스 증거
- **pApiCQEQueueGetbySk.sql**: 줄 30-32
  ```sql
  UPDATE tLSvr SET LSChkdt = GETDATE() WHERE LSSN = @lssn AND is_gateway = 0
  ```
  → fetch_queue() 호출 시 자동 실행됨

### 실행 로그 증거
- Gateway stderr: `[5.3.1-WARN] "fetch_queue 함수 미로드"` 
  → fetch_queue 타입 체크 실패 명확히 표시

---

## 6. 결론

| 항목 | 설명 |
|------|------|
| **왜 안되는가?** | normal.sh 미로드 → fetch_queue() 존재하지 않음 |
| **어디서 안되는가?** | gateway.sh 줄 645: `if type fetch_queue ...` 실패 |
| **어떻게 고치는가?** | gateway.sh 줄 34에 normal.sh 로드 명령 추가 |
| **효과** | Gateway도 CQEQueueGet API 호출 → LSChkdt 자동 업데이트 |

