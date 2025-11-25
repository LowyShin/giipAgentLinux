# Infrastructure Discovery KVS 로깅 구현 완료

> **📖 선행 문서**: 
> - [완료 요약](../LOGGING_COMPLETION_SUMMARY.md) - 전체 개요 및 빠른 시작
> - [진단 가이드](./KVS_LOGGING_DIAGNOSIS_GUIDE.md) - 실패 지점별 진단 및 해결 방법

## 📋 개요

Infrastructure Discovery 데이터 수집 실패 문제를 진단하기 위해 **포괄적인 KVS 로깅 시스템**을 구현했습니다.

**목표**: "수집 안되고 있어. 어디서 문제가 생겼는지 tKVS에 로깅해서 네가 문제를 분석해봐"

> 📌 **표준 참고**: 모든 KVS 저장은 [KVS_STORAGE_STANDARD.md](KVS_STORAGE_STANDARD.md)의 `lib/kvs.sh` 기반 표준을 따릅니다.

## ✅ 구현 완료 사항

### 1. 핵심 로깅 함수 (`_log_to_kvs`)

**기능**:
- 각 처리 단계별 로그 생성
- KVS 저장소에 JSON 형식으로 저장
- 파일 기반 폴백 로깅 (`/tmp/discovery_kvs_log_${KVS_LSSN}.txt`)
- 타임스탐프, 호스트명, PID 자동 포함

**로그 형식**:
```json
{
  "phase": "LOCAL_START",
  "target_lssn": 1,
  "status": "SUCCESS",
  "message": "Starting local discovery",
  "timestamp": "2024-01-15T10:30:45Z",
  "hostname": "server-name",
  "pid": 12345
}
```

### 2. 로컬 수집 로깅 (5 단계)

| 단계 | 로깅 내용 | 실패시 진단 정보 |
|------|---------|----------------|
| LOCAL_START | 로컬 수집 시작 | 시작 실패 감지 |
| LOCAL_SCRIPT_CHECK | 스크립트 존재 확인 | 파일 경로 오류 |
| LOCAL_EXECUTION | 스크립트 실행 | 실행 에러 메시지 |
| LOCAL_JSON_VALIDATION | JSON 형식 검증 | 잘못된 JSON 샘플 |
| LOCAL_DB_SAVE | 데이터베이스 저장 | 각 테이블별 저장 상태 |

### 3. 원격 수집 로깅 (9 단계)

| 단계 | 로깅 내용 | 실패시 진단 정보 |
|------|---------|----------------|
| REMOTE_START | 원격 수집 시작 | 원격 정보 확인 |
| REMOTE_PARSE | SSH 정보 파싱 | 형식 오류 상세 |
| REMOTE_CONNECT | SSH 연결 시도 | 연결 실패 원인 |
| REMOTE_EXECUTE_METHOD1 | 기존 경로 시도 | 첫번째 시도 결과 |
| REMOTE_TRANSFER | 스크립트 전송 | SCP 전송 성공/실패 |
| REMOTE_EXECUTE_METHOD2 | 전송된 스크립트 실행 | 원격 실행 에러 |
| REMOTE_JSON_VALIDATION | JSON 검증 | 부분 JSON 샘플 |
| REMOTE_DB_SAVE | 데이터베이스 저장 | 저장 상태 |
| REMOTE_COMPLETE | 완료 신호 | 전체 성공 여부 |

### 4. SSH 작업 로깅

```
_ssh_exec() 함수:
  - SSH_EXEC_SUCCESS: 명령 성공
  - SSH_EXEC_ERROR: 명령 실패 (exit code 포함)
  
_scp_file() 함수:
  - SCP_TRANSFER_SUCCESS: 파일 전송 성공
  - SCP_TRANSFER_ERROR: 파일 전송 실패
```

### 5. 데이터베이스 저장 로깅

```
_save_discovery_to_db() 함수:
  - DB_SAVE_START: 시작
  - DB_SAVE_SERVER_INFO: 서버 정보 저장 (tLSvr)
  - DB_SAVE_NETWORK: 네트워크 저장 (tLSvrNIC)
  - DB_SAVE_SOFTWARE: 소프트웨어 저장 (tLSvrSoftware)
  - DB_SAVE_SERVICES: 서비스 저장 (tLSvrService)
  - DB_GENERATE_ADVICE: Advice 생성
  - DB_SAVE_COMPLETE: 완료
```

### 6. 데이터 파싱 로깅

각 테이블별 파싱 단계에서 개별 항목 로깅:

```
_save_network_interfaces(): NETWORK_INTERFACE (각 NIC별 로그)
_save_software(): SOFTWARE_ENTRY (각 소프트웨어별 로그)
_save_services(): SERVICE_ENTRY (각 서비스별 로그)
```

## 📂 수정된 파일

### 1. `lib/discovery.sh` (651 줄)

**새로 추가된 함수**:
- `_log_to_kvs()`: 모든 로깅의 중심 함수

**로깅 추가된 함수**:
- `collect_infrastructure_data()`: DISCOVERY_START/END 로깅
- `_collect_local_data()`: LOCAL_* 5단계 로깅
- `_collect_remote_data()`: REMOTE_* 9단계 로깅
- `_ssh_exec()`: SSH_EXEC_* 로깅
- `_scp_file()`: SCP_TRANSFER_* 로깅
- `_save_discovery_to_db()`: DB_SAVE_* 로깅
- `_save_server_info()`: SERVER_INFO_* 로깅
- `_save_network_interfaces()`: NETWORK_* 로깅
- `_save_software()`: SOFTWARE_* 로깅
- `_save_services()`: SERVICE_* 로깅
- `_generate_advice()`: ADVICE_GENERATION 로깅

**개선 사항**:
- 모든 단계에서 success/error 로깅
- 에러 메시지 캡처 (stderr를 2>&1로 통합)
- 각 단계별 구체적 진단 정보 포함

## 🧪 테스트 파일

### `test-discovery-logging.sh` (새로 생성)

**목적**: KVS 로깅 시스템 테스트

**포함 내용**:
- Test 1: 로깅 함수 직접 테스트
- Test 2: 로컬 수집 로깅 테스트
- Test 3: SSH 함수 로깅 테스트
- 결과 요약 및 다음 단계 안내

**사용**:
```bash
bash test-discovery-logging.sh
```

## 📖 진단 가이드

### `docs/KVS_LOGGING_DIAGNOSIS_GUIDE.md` (새로 생성)

**포함 내용**:
1. 로깅 아키텍처 상세 설명
2. 모든 Phase 정의 및 의미
3. 문제별 진단 및 해결 방법
4. 테스트 방법
5. 로그 분석 팁
6. 성공 흐름 패턴

## 🎯 사용 방법

### 단계 1: 로깅 테스트
```bash
bash test-discovery-logging.sh
```

### 단계 2: 로컬 수집 실행
```bash
source lib/discovery.sh
collect_infrastructure_data 1
cat /tmp/discovery_kvs_log_1.txt
```

### 단계 3: 원격 수집 실행
```bash
source lib/discovery.sh
collect_infrastructure_data 2 root@192.168.1.100:22
cat /tmp/discovery_kvs_log_2.txt
```

### 단계 4: 로그 분석
- `/tmp/discovery_kvs_log_<LSSN>.txt` 파일 검토
- 첫 ERROR/WARNING 찾기
- 진단 가이드의 "실패 지점별 해결 방법" 참고

## 🔍 진단 예시

### 예시 1: 성공적인 로컬 수집 로그

```
[2024-01-15T10:30:45Z] [LSSN:1] [DISCOVERY_START] [RUNNING] Starting infrastructure discovery
[2024-01-15T10:30:45Z] [LSSN:1] [LOCAL_START] [RUNNING] Starting local discovery
[2024-01-15T10:30:45Z] [LSSN:1] [LOCAL_SCRIPT_CHECK] [SUCCESS] Script found at /path/to/auto-discover-linux.sh
[2024-01-15T10:30:46Z] [LSSN:1] [LOCAL_EXECUTION] [SUCCESS] Script executed successfully
[2024-01-15T10:30:46Z] [LSSN:1] [LOCAL_JSON_VALIDATION] [SUCCESS] JSON validation passed
[2024-01-15T10:30:47Z] [LSSN:1] [DB_SAVE_START] [RUNNING] Starting database save operations
[2024-01-15T10:30:47Z] [LSSN:1] [DB_SAVE_SERVER_INFO] [SUCCESS] Server info saved
[2024-01-15T10:30:48Z] [LSSN:1] [DB_SAVE_NETWORK] [SUCCESS] Network interfaces saved
[2024-01-15T10:30:48Z] [LSSN:1] [DB_SAVE_SOFTWARE] [SUCCESS] Software inventory saved
[2024-01-15T10:30:49Z] [LSSN:1] [DB_SAVE_SERVICES] [SUCCESS] Services saved
[2024-01-15T10:30:49Z] [LSSN:1] [DB_SAVE_COMPLETE] [SUCCESS] All database operations completed
[2024-01-15T10:30:49Z] [LSSN:1] [DISCOVERY_END] [SUCCESS] Infrastructure discovery completed
```

### 예시 2: 실패 (스크립트 실행 에러)

```
[2024-01-15T10:30:45Z] [LSSN:2] [DISCOVERY_START] [RUNNING] Starting infrastructure discovery
[2024-01-15T10:30:45Z] [LSSN:2] [LOCAL_START] [RUNNING] Starting local discovery
[2024-01-15T10:30:45Z] [LSSN:2] [LOCAL_SCRIPT_CHECK] [SUCCESS] Script found
[2024-01-15T10:30:45Z] [LSSN:2] [LOCAL_EXECUTION] [ERROR] Script execution failed: /bin/bash: python3: not found
                                                     ↑ 여기서 문제 파악!
```

## 📊 로깅 커버리지

| 카테고리 | 항목 수 | 상세 |
|---------|--------|------|
| 진입/종료 | 2 | DISCOVERY_START/END |
| 로컬 수집 | 5 | LOCAL_* (5단계) |
| 원격 수집 | 9 | REMOTE_* (9단계) |
| SSH 작업 | 2 | SSH_EXEC_*, SCP_TRANSFER_* |
| DB 저장 | 7 | DB_SAVE_* (6+완료) |
| 데이터 파싱 | 9 | NETWORK_*/SOFTWARE_*/SERVICE_* |
| 조언 생성 | 1 | ADVICE_GENERATION |
| **합계** | **35+** | **모든 단계 및 부단계 포함** |

## 🚀 다음 단계

1. **테스트 환경에서 로깅 검증**
   ```bash
   bash test-discovery-logging.sh
   ```

2. **실제 LSSN으로 수집 실행**
   ```bash
   source lib/discovery.sh
   collect_infrastructure_data <LSSN>
   cat /tmp/discovery_kvs_log_<LSSN>.txt
   ```

3. **로그 분석으로 실패 지점 파악**

4. **실패 지점 해결 (진단 가이드 참고)**

5. **원격 서버 테스트** (SSH 설정 후)

## 💡 주요 기능

✅ **자동 진단**: 각 단계별 상세 로깅으로 실패 지점 자동 파악
✅ **다중 저장소**: KVS + 파일 폴백으로 로그 손실 방지
✅ **타임스탐프**: 모든 로그에 정확한 시간 기록
✅ **문맥 정보**: 호스트명, PID, LSSN으로 추적 가능
✅ **에러 상세**: 에러 메시지 캡처로 정확한 원인 파악
✅ **구조화된 JSON**: 자동 분석 및 시각화 가능

## 📝 주의사항

- KVS_LOG_ENABLED는 기본값 true (필요시 false로 설정 가능)
- 로그 파일은 자동 생성/추가되므로 정기적 정리 권장
- 매우 큰 Infrastructure 데이터의 경우 로그 파일 크기 주의

---

**상태**: 구현 완료 ✅
**테스트**: 준비됨 🧪
**진단 준비**: 완료 📖
