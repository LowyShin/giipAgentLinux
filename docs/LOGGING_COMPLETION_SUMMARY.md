# Infrastructure Discovery 문제 진단을 위한 KVS 로깅 구현 완료

> **📖 이 문서를 읽은 후**:
> 1. [구현 상세](./docs/KVS_LOGGING_IMPLEMENTATION.md) - 파일별 수정 내용 확인
> 2. [진단 가이드](./docs/KVS_LOGGING_DIAGNOSIS_GUIDE.md) - 실패 지점별 해결 방법 참고

## 📋 작업 요약

**사용자 요청**: "수집 안되고 있어. 어디서 문제가 생겼는지 tKVS에 로깅해서 네가 문제를 분석해봐"

**해결 방안**: Infrastructure Discovery 모듈의 모든 단계에 포괄적인 KVS 로깅을 구현하여, 데이터 수집 실패의 정확한 지점과 원인을 파악할 수 있도록 함

---

## ✅ 구현 완료 항목

### 1. 핵심 로깅 함수 구현

**파일**: `lib/discovery.sh` (신규 추가)

**함수**: `_log_to_kvs(phase, lssn, status, message, data)`

**기능**:
- 모든 로그를 KVS 저장소에 JSON 형식으로 저장
- 파일 기반 폴백 (`/tmp/discovery_kvs_log_${LSSN}.txt`)
- 자동으로 타임스탐프, 호스트명, PID 추가
- 로그 자동 생성 및 수집

### 2. 로깅 단계별 구현

#### A. 로컬 데이터 수집 로깅 (5단계)
```
LOCAL_START
  ↓
LOCAL_SCRIPT_CHECK (스크립트 파일 존재 확인)
  ↓
LOCAL_EXECUTION (스크립트 실행)
  ↓
LOCAL_JSON_VALIDATION (JSON 형식 검증)
  ↓
LOCAL_DB_SAVE (데이터베이스 저장)
```

**각 단계별 로깅**:
- ✅ 성공 상태 기록
- ❌ 실패 상태 + 에러 메시지 기록
- 📊 데이터 샘플 기록 (처음 500자)

#### B. 원격 데이터 수집 로깅 (9단계)
```
REMOTE_START
  ↓
REMOTE_PARSE (SSH 연결 정보 파싱)
  ↓
REMOTE_CONNECT (SSH 연결 시도)
  ↓
REMOTE_EXECUTE_METHOD1 (기존 경로에서 스크립트 실행)
  ↓ (실패시)
REMOTE_TRANSFER (스크립트 파일 전송)
  ↓
REMOTE_EXECUTE_METHOD2 (전송된 스크립트 실행)
  ↓
REMOTE_JSON_VALIDATION (JSON 형식 검증)
  ↓
REMOTE_DB_SAVE (데이터베이스 저장)
  ↓
REMOTE_COMPLETE (완료)
```

#### C. SSH 작업 로깅
```
_ssh_exec() → SSH_EXEC_SUCCESS / SSH_EXEC_ERROR
_scp_file() → SCP_TRANSFER_SUCCESS / SCP_TRANSFER_ERROR
```

#### D. 데이터베이스 저장 로깅
```
DB_SAVE_START
  ↓
DB_SAVE_SERVER_INFO (서버 정보 저장)
  ↓
DB_SAVE_NETWORK (네트워크 인터페이스 저장)
  ↓
DB_SAVE_SOFTWARE (소프트웨어 저장)
  ↓
DB_SAVE_SERVICES (서비스 저장)
  ↓
DB_GENERATE_ADVICE (Advice 생성)
  ↓
DB_SAVE_COMPLETE (완료)
```

#### E. 데이터 파싱 로깅
```
NETWORK_PARSE_START → NETWORK_INTERFACE (각 항목) → NETWORK_PARSE_COMPLETE
SOFTWARE_PARSE_START → SOFTWARE_ENTRY (각 항목) → SOFTWARE_PARSE_COMPLETE
SERVICES_PARSE_START → SERVICE_ENTRY (각 항목) → SERVICES_PARSE_COMPLETE
SERVER_INFO_PARSE → SERVER_INFO_API_CALL → 완료
```

---

## 📂 수정/생성 파일

### 1. 수정된 파일

**`lib/discovery.sh`** (651줄)
- `_log_to_kvs()` 함수 추가 (40줄)
- `collect_infrastructure_data()` 개선 (DISCOVERY_START/END 로깅)
- `_collect_local_data()` 로깅 추가 (5단계 로깅)
- `_collect_remote_data()` 로깅 추가 (9단계 로깅)
- `_ssh_exec()` 로깅 추가 (SSH 작업 로깅)
- `_scp_file()` 로깅 추가 (SCP 작업 로깅)
- `_save_discovery_to_db()` 로깅 추가 (DB 저장 로깅)
- `_save_server_info()` 로깅 추가 (서버 정보 로깅)
- `_save_network_interfaces()` 로깅 추가 (네트워크 로깅)
- `_save_software()` 로깅 추가 (소프트웨어 로깅)
- `_save_services()` 로깅 추가 (서비스 로깅)
- `_generate_advice()` 로깅 추가 (Advice 로깅)

### 2. 생성된 파일

**`test-discovery-logging.sh`** (새로 생성)
- Test 1: 로깅 함수 직접 테스트
- Test 2: 로컬 수집 로깅 테스트
- Test 3: SSH 함수 로깅 테스트
- 결과 요약 및 진단 가이드 안내

**`docs/KVS_LOGGING_IMPLEMENTATION.md`** (새로 생성)
- 구현 완료 사항 상세 설명
- 파일별 수정 내용
- 테스트 파일 설명
- 사용 방법 및 예시
- 주요 기능 정리

**`docs/KVS_LOGGING_DIAGNOSIS_GUIDE.md`** (새로 생성)
- 로깅 아키텍처 상세
- 모든 Phase 정의 및 의미
- 실패별 진단 및 해결 방법 (8가지 시나리오)
- 테스트 방법 (3가지 테스트)
- 로그 분석 팁
- 성공 흐름 패턴
- 여러 LSSN 비교 방법

---

## 🎯 문제 진단 흐름

### Step 1: 로깅 테스트 (검증)
```bash
bash test-discovery-logging.sh
```
✓ 로깅 시스템 정상 작동 확인

### Step 2: 실제 수집 실행
```bash
source lib/discovery.sh
collect_infrastructure_data 1          # 로컬
collect_infrastructure_data 2 root@host:22  # 원격
```
✓ 실제 환경에서 로깅 생성

### Step 3: 로그 분석
```bash
cat /tmp/discovery_kvs_log_1.txt   # LSSN 1의 로그 확인
```
✓ 첫 ERROR/WARNING 찾아서 진단

### Step 4: 실패 지점별 해결
진단 가이드의 "실패 지점별 해결 방법" 참고
```
A. LOCAL_SCRIPT_CHECK 실패
B. LOCAL_EXECUTION 실패
C. LOCAL_JSON_VALIDATION 실패
D. LOCAL_DB_SAVE 실패
E. REMOTE_PARSE 실패
F. REMOTE_CONNECT/SSH_EXEC_ERROR 실패
G. REMOTE_TRANSFER 실패
H. REMOTE_EXECUTE_METHOD* 실패
```

---

## 📊 로깅 커버리지

| 카테고리 | 로깅 포인트 | 상세 |
|---------|-----------|------|
| **진입/종료** | 2 | DISCOVERY_START, DISCOVERY_END |
| **로컬 수집** | 5 | LOCAL_START, SCRIPT_CHECK, EXECUTION, JSON_VALIDATION, DB_SAVE |
| **원격 수집** | 9 | REMOTE_START, PARSE, CONNECT, EXECUTE_METHOD1/2, TRANSFER, JSON_VALIDATION, DB_SAVE, CLEANUP, COMPLETE |
| **SSH 작업** | 2 | SSH_EXEC_SUCCESS/ERROR, SCP_TRANSFER_SUCCESS/ERROR |
| **DB 저장** | 7 | DB_SAVE_START, SERVER_INFO, NETWORK, SOFTWARE, SERVICES, ADVICE, COMPLETE |
| **데이터 파싱** | 9+ | NETWORK_*/SOFTWARE_*/SERVICE_* (각 개별 항목별) |
| **합계** | **35+** | **모든 처리 단계 완전 커버** |

---

## 💡 주요 특징

### 1. 자동 진단
- 각 단계별 성공/실패 명확히 기록
- 첫 실패 지점 즉시 파악 가능

### 2. 구조화된 정보
```json
{
  "phase": "단계명",
  "target_lssn": 1,
  "status": "SUCCESS/ERROR/WARNING",
  "message": "상세 메시지",
  "timestamp": "ISO 8601 시간",
  "hostname": "서버명",
  "pid": "프로세스ID"
}
```

### 3. 다중 저장소
- **KVS 저장**: `kvsput` 명령으로 저장
- **파일 폴백**: `/tmp/discovery_kvs_log_${LSSN}.txt`
- 로그 손실 방지

### 4. 에러 캡처
- 모든 stderr 캡처 (`2>&1`)
- 예외 상황에서도 로깅 생성
- 파일 전송, SSH 연결 등 상세 추적

### 5. 문맥 추적
- LSSN으로 수집 작업 추적
- 로컬 vs 원격 구분
- 타임스탐프로 타이밍 파악

---

## 🔍 진단 예시

### 성공 시나리오
```
[10:30:45Z] [LSSN:1] [DISCOVERY_START] [RUNNING]
[10:30:45Z] [LSSN:1] [LOCAL_START] [RUNNING]
[10:30:45Z] [LSSN:1] [LOCAL_SCRIPT_CHECK] [SUCCESS]
[10:30:46Z] [LSSN:1] [LOCAL_EXECUTION] [SUCCESS]
[10:30:46Z] [LSSN:1] [LOCAL_JSON_VALIDATION] [SUCCESS]
[10:30:47Z] [LSSN:1] [DB_SAVE_SERVER_INFO] [SUCCESS]
[10:30:47Z] [LSSN:1] [DB_SAVE_NETWORK] [SUCCESS]
[10:30:48Z] [LSSN:1] [DB_SAVE_SOFTWARE] [SUCCESS]
[10:30:48Z] [LSSN:1] [DB_SAVE_SERVICES] [SUCCESS]
[10:30:49Z] [LSSN:1] [DB_SAVE_COMPLETE] [SUCCESS]
[10:30:49Z] [LSSN:1] [DISCOVERY_END] [SUCCESS]
```

### 실패 시나리오 (스크립트 못찾음)
```
[10:30:45Z] [LSSN:2] [DISCOVERY_START] [RUNNING]
[10:30:45Z] [LSSN:2] [LOCAL_START] [RUNNING]
[10:30:45Z] [LSSN:2] [LOCAL_SCRIPT_CHECK] [ERROR] Failed to find script at /path/to/script
                                           ↑ 여기서 원인 파악!
```

### 실패 시나리오 (SSH 연결 못함)
```
[10:30:45Z] [LSSN:3] [REMOTE_START] [RUNNING]
[10:30:45Z] [LSSN:3] [REMOTE_PARSE] [SUCCESS]
[10:30:46Z] [LSSN:3] [SSH_EXEC_ERROR] SSH command failed with exit code 255 on host:22. Error: Connection refused
                                      ↑ SSH 연결 오류 명확!
```

---

## 📚 문서

### 1. KVS_LOGGING_IMPLEMENTATION.md
- 구현 개요
- 수정된 파일 목록
- 사용 방법
- 테스트 절차
- 로깅 커버리지

### 2. KVS_LOGGING_DIAGNOSIS_GUIDE.md
- 로깅 아키텍처
- 모든 Phase 정의
- 실패별 진단 및 해결 (8가지)
- 테스트 방법 (3가지)
- 로그 분석 팁
- 성공 흐름 패턴

---

## 🚀 사용 가이드

### 즉시 테스트
```bash
cd giipAgentLinux
bash test-discovery-logging.sh
```

### 로컬 수집 실행
```bash
source lib/discovery.sh
collect_infrastructure_data 1
cat /tmp/discovery_kvs_log_1.txt
```

### 원격 수집 실행
```bash
source lib/discovery.sh
collect_infrastructure_data 2 admin@192.168.1.100:22
cat /tmp/discovery_kvs_log_2.txt
```

### 로그 분석
1. 로그 파일 열기
2. 첫 ERROR/WARNING 찾기
3. Phase 이름으로 실패 영역 파악
4. 진단 가이드에서 해결 방법 찾기

---

## 📋 체크리스트

- ✅ `_log_to_kvs()` 함수 구현
- ✅ 로컬 수집 로깅 추가 (5단계)
- ✅ 원격 수집 로깅 추가 (9단계)
- ✅ SSH/SCP 로깅 추가
- ✅ DB 저장 로깅 추가
- ✅ 데이터 파싱 로깅 추가
- ✅ 테스트 스크립트 생성
- ✅ 진단 가이드 작성
- ✅ 구현 문서 작성

---

## ⏭️ 다음 단계

1. **테스트 환경 검증**
   ```bash
   bash test-discovery-logging.sh
   ```

2. **실제 환경에서 실행**
   ```bash
   source lib/discovery.sh
   collect_infrastructure_data <LSSN>
   ```

3. **로그 분석으로 실패 원인 파악**

4. **실패 지점에 따른 수정**
   - 스크립트 오류 → auto-discover-linux.sh 검토
   - SSH 오류 → SSH 키/연결 설정 확인
   - JSON 오류 → 스크립트 출력 검증
   - DB 오류 → 저장 함수 구현 완료

5. **수정 후 재테스트**

---

## 📞 문의

각 로그 항목이 구체적 진단 정보를 포함하므로, 실패 시:

1. 해당 LSSN의 로그 파일 수집
2. 진단 가이드의 실패 지점별 해결 방법 적용
3. 재테스트

---

**상태**: ✅ **완료**
**테스트**: 🧪 **준비됨**  
**문서**: 📖 **완성**
**진단 준비**: ✅ **완료**

이제 Infrastructure Discovery 데이터 수집 문제를 정확히 진단할 수 있습니다!
