# KVS 로깅을 통한 Infrastructure Discovery 문제 진단 가이드

> **📖 선행 문서**:
> - [완료 요약](../LOGGING_COMPLETION_SUMMARY.md) - 전체 개요 및 빠른 시작
> - [구현 상세](./KVS_LOGGING_IMPLEMENTATION.md) - 구현된 내용 및 파일 수정 내역

## 개요

Infrastructure Discovery 모듈에서 데이터 수집이 제대로 되지 않는 문제를 진단하기 위해 포괄적인 KVS 로깅 시스템을 구현했습니다.

## 로깅 아키텍처

### 로깅 설정
- **KVS_LOG_ENABLED**: true (기본값)
- **KVS_LSSN**: 각 수집 작업의 LSSN으로 자동 설정
- **저장 위치**: 
  - KVS 저장소 (kvsput 사용 가능시)
  - 파일 폴백: `/tmp/discovery_kvs_log_${KVS_LSSN}.txt`

### 로깅 함수: _log_to_kvs()
```bash
_log_to_kvs <phase> <lssn> <status> <message> [optional_data]
```

**파라미터**:
- `phase`: 현재 처리 단계 (예: LOCAL_START, REMOTE_CONNECT, JSON_VALIDATION)
- `lssn`: 대상 LSSN
- `status`: SUCCESS, RUNNING, ERROR, WARNING
- `message`: 상세 메시지
- `optional_data`: 추가 데이터 (JSON)

**출력 형식**:
```json
{
  "phase": "PHASE_NAME",
  "target_lssn": 1234,
  "status": "SUCCESS",
  "message": "Detailed message",
  "timestamp": "2024-01-15T10:30:45Z",
  "hostname": "server-name",
  "pid": 12345
}
```

## 로깅 단계 (Phase)

### 1. 진입/종료 단계

| Phase | 설명 | 상황 |
|-------|------|------|
| DISCOVERY_START | 수집 시작 | 로컬 또는 원격 수집 시작 |
| DISCOVERY_END | 수집 완료 | 모든 작업 완료 |

### 2. 로컬 데이터 수집 (LOCAL_*)

| Phase | 설명 | 실패시 영향 |
|-------|------|-----------|
| LOCAL_START | 로컬 수집 시작 | 수집이 시작되지 않음 |
| LOCAL_SCRIPT_CHECK | auto-discover-linux.sh 존재 확인 | 스크립트 못찾음 |
| LOCAL_EXECUTION | 스크립트 실행 | 스크립트 실행 실패 |
| LOCAL_JSON_VALIDATION | JSON 형식 검증 | 잘못된 JSON 출력 |
| LOCAL_DB_SAVE | 데이터베이스 저장 | 수집된 데이터가 DB에 안저장됨 |

### 3. 원격 데이터 수집 (REMOTE_*)

| Phase | 설명 | 실패시 영향 |
|-------|------|-----------|
| REMOTE_START | 원격 수집 시작 | SSH 연결 시도 전 실패 |
| REMOTE_PARSE | SSH 정보 파싱 | 원격 정보 형식 오류 |
| REMOTE_CONNECT | SSH 연결 시도 | SSH 연결 불가 |
| REMOTE_EXECUTE_METHOD1 | 기존 경로에서 스크립트 실행 시도 | 원격에 스크립트 없음 |
| REMOTE_TRANSFER | 스크립트 파일 전송 | SCP 전송 실패 |
| REMOTE_EXECUTE_METHOD2 | 전송된 스크립트 실행 | 원격 실행 실패 |
| REMOTE_JSON_VALIDATION_METHOD* | JSON 형식 검증 | 잘못된 JSON 출력 |
| REMOTE_DB_SAVE | 데이터베이스 저장 | 수집된 데이터가 DB에 안저장됨 |
| REMOTE_CLEANUP | 임시 파일 정리 | 원격 임시 파일 정리 (비필수) |
| REMOTE_COMPLETE | 원격 수집 완료 | 성공적 완료 |

### 4. SSH 작업 로깅

| Phase | 설명 |
|-------|------|
| SSH_EXEC_SUCCESS | SSH 명령 성공적 실행 |
| SSH_EXEC_ERROR | SSH 명령 실패 (exit code 포함) |
| SCP_TRANSFER_SUCCESS | 파일 전송 성공 |
| SCP_TRANSFER_ERROR | 파일 전송 실패 |

### 5. 데이터베이스 저장 (DB_SAVE_*)

| Phase | 설명 |
|-------|------|
| DB_SAVE_START | DB 저장 시작 |
| DB_SAVE_SERVER_INFO | 서버 정보 저장 (tLSvr) |
| DB_SAVE_NETWORK | 네트워크 인터페이스 저장 (tLSvrNIC) |
| DB_SAVE_SOFTWARE | 소프트웨어 저장 (tLSvrSoftware) |
| DB_SAVE_SERVICES | 서비스 저장 (tLSvrService) |
| DB_GENERATE_ADVICE | Advice 생성 (pApiAgentGenerateAdvicebyAK) |
| DB_SAVE_COMPLETE | 모든 DB 작업 완료 |

### 6. 데이터 파싱 (PARSE_*, _ENTRY)

| Phase | 설명 |
|-------|------|
| SERVER_INFO_PARSE | 서버 정보 파싱 완료 |
| SERVER_INFO_API_CALL | 서버 정보 API 호출 |
| NETWORK_PARSE_START | 네트워크 파싱 시작 |
| NETWORK_INTERFACE | 개별 NIC 항목 |
| NETWORK_PARSE_COMPLETE | 네트워크 파싱 완료 |
| SOFTWARE_PARSE_START | 소프트웨어 파싱 시작 |
| SOFTWARE_ENTRY | 개별 소프트웨어 항목 |
| SOFTWARE_PARSE_COMPLETE | 소프트웨어 파싱 완료 |
| SERVICES_PARSE_START | 서비스 파싱 시작 |
| SERVICE_ENTRY | 개별 서비스 항목 |
| SERVICES_PARSE_COMPLETE | 서비스 파싱 완료 |

## 문제 진단 가이드

### 단계 1: 로그 파일 확인

```bash
# LSSN별 로그 파일 확인
cat /tmp/discovery_kvs_log_<LSSN>.txt

# 예제: LSSN 1의 로그 확인
cat /tmp/discovery_kvs_log_1.txt
```

### 단계 2: 실패 지점 파악

로그를 읽으면서 **ERROR 상태**를 찾습니다:

```
[2024-01-15T10:30:45Z] [LSSN:1] [LOCAL_START] [RUNNING] Starting local discovery
[2024-01-15T10:30:46Z] [LSSN:1] [LOCAL_SCRIPT_CHECK] [SUCCESS] Script found
[2024-01-15T10:30:46Z] [LSSN:1] [LOCAL_EXECUTION] [ERROR] Script execution failed: Permission denied
                                                   ↑ 여기서 실패!
```

### 단계 3: 실패 지점별 해결 방법

#### A. **LOCAL_SCRIPT_CHECK 실패**
```
⚠️  문제: auto-discover-linux.sh 스크립트를 찾지 못함
🔍 확인:
  - 파일 존재 확인: ls -la giipscripts/auto-discover-linux.sh
  - 경로 확인: DISCOVERY_SCRIPT_LOCAL 변수 확인
  - 파일 권한: chmod +x giipscripts/auto-discover-linux.sh
```

#### B. **LOCAL_EXECUTION 실패**
```
⚠️  문제: 스크립트 실행 실패
🔍 확인:
  - 로그 메시지에서 에러 내용 확인 (예: Permission denied, not found)
  - 스크립트 종속성 확인: python3, jq, lsb_release 등
  - 실행 권한: ls -la giipscripts/auto-discover-linux.sh
💡 해결:
  bash giipscripts/auto-discover-linux.sh 2>&1
  로 직접 실행하여 에러 확인
```

#### C. **LOCAL_JSON_VALIDATION 실패**
```
⚠️  문제: 스크립트는 실행되었지만 JSON 형식이 잘못됨
🔍 확인:
  - 로그의 "First 500 chars" 부분 확인
  - JSON 형식 검증:
    bash giipscripts/auto-discover-linux.sh | python3 -m json.tool
🔧 원인:
  - 스크립트 출력에 불필요한 echo/print 문이 있음
  - 에러 메시지가 stdout으로 섞여있음
  - JSON 필드 누락
```

#### D. **LOCAL_DB_SAVE 실패**
```
⚠️  문제: JSON은 유효하지만 DB 저장 실패
🔍 확인:
  - 로그에서 DB_SAVE_* 단계의 상태 확인
  - 각 테이블별 저장 실패 이유 확인:
    - DB_SAVE_SERVER_INFO: _save_server_info() 함수 문제
    - DB_SAVE_NETWORK: _save_network_interfaces() 함수 문제
    - DB_SAVE_SOFTWARE: _save_software() 함수 문제
    - DB_SAVE_SERVICES: _save_services() 함수 문제
💡 현재 상태: _save_*() 함수들은 TODO 상태
     실제 API 호출 또는 KVS 저장 로직 구현 필요
```

#### E. **REMOTE_PARSE 실패**
```
⚠️  문제: SSH 연결 정보 파싱 실패
🔍 형식:
  정확한 형식: ssh_user@ssh_host:ssh_port
  또는: ssh_user@ssh_host (기본 포트 22 사용)
💡 예제:
  root@192.168.1.100:22
  admin@remote.example.com
```

#### F. **REMOTE_CONNECT 또는 SSH_EXEC_ERROR 실패**
```
⚠️  문제: SSH 연결 불가
🔍 확인:
  - 네트워크 연결 확인: ping <ssh_host>
  - SSH 서버 실행 확인: nc -zv <ssh_host> 22
  - SSH 키 확인: ls -la /root/.ssh/
  - SSH 권한 확인: chmod 600 /root/.ssh/id_rsa
  - SSH 접속 테스트: ssh -v root@<ssh_host> 'hostname'
💡 로그에서 실패 원인 확인:
  exit code 값을 통해 구체적 에러 파악
```

#### G. **REMOTE_TRANSFER 실패**
```
⚠️  문제: SCP를 통한 파일 전송 실패
🔍 확인:
  - 원격 서버 접근 권한 확인
  - /tmp 디렉토리 쓰기 권한 확인:
    ssh root@<host> 'touch /tmp/test.txt && rm /tmp/test.txt'
  - 원격 서버의 디스크 공간 확인
  - 로컬 파일 존재 확인: ls -la giipscripts/auto-discover-linux.sh
```

#### H. **REMOTE_EXECUTE_METHOD* 실패**
```
⚠️  문제: 원격에서 스크립트 실행 실패
🔍 확인 (SSH로 직접 실행):
  ssh root@<host> 'bash /opt/giip/agent/linux/giipscripts/auto-discover-linux.sh'
  ssh root@<host> 'bash /tmp/auto-discover-linux.sh'
💡 원격 서버에서:
  - bash 설치 확인: which bash
  - 스크립트 의존성 설치:
    python3, jq, curl, lsb_release 등
```

## 테스트 방법

### 테스트 1: 로깅 함수 직접 테스트

```bash
# lib/discovery.sh 로드
source lib/discovery.sh

# KVS 로깅 테스트
export KVS_LSSN=9999
_log_to_kvs "TEST_PHASE" "9999" "SUCCESS" "Test message"

# 로그 파일 확인
cat /tmp/discovery_kvs_log_9999.txt
```

### 테스트 2: 로컬 수집 테스트

```bash
# LSSN 1로 로컬 수집 실행
bash test-discovery-logging.sh

# 또는 직접 실행
source lib/discovery.sh
collect_infrastructure_data 1

# 로그 파일 확인
cat /tmp/discovery_kvs_log_1.txt
```

### 테스트 3: 원격 수집 테스트

```bash
# SSH로 원격 서버 수집
source lib/discovery.sh
collect_infrastructure_data 2 root@192.168.1.100:22

# 로그 파일 확인
cat /tmp/discovery_kvs_log_2.txt
```

## 로그 분석 팁

### 1. 성공적 흐름 패턴

```
DISCOVERY_START [RUNNING]
  → LOCAL_START [RUNNING]
    → LOCAL_SCRIPT_CHECK [SUCCESS]
    → LOCAL_EXECUTION [SUCCESS]
    → LOCAL_JSON_VALIDATION [SUCCESS]
    → LOCAL_DB_SAVE [SUCCESS]
      → DB_SAVE_START [RUNNING]
      → DB_SAVE_SERVER_INFO [SUCCESS]
      → DB_SAVE_NETWORK [SUCCESS]
      → DB_SAVE_SOFTWARE [SUCCESS]
      → DB_SAVE_SERVICES [SUCCESS]
      → DB_SAVE_COMPLETE [SUCCESS]
DISCOVERY_END [SUCCESS]
```

### 2. 빠른 실패 원인 파악

로그를 아래 순서로 확인하세요:

1. **첫 번째 ERROR/WARNING 찾기**
2. **Phase 이름 확인**: LOCAL_* vs REMOTE_* (원인 영역 파악)
3. **Message 읽기**: 구체적 에러 내용 파악
4. **앞뒤 로그 확인**: 실패 전 성공한 단계와 비교

### 3. 여러 LSSN 비교

```bash
# 성공한 LSSN과 실패한 LSSN 비교
diff <(cat /tmp/discovery_kvs_log_1.txt) <(cat /tmp/discovery_kvs_log_2.txt)

# 실패한 LSSN만 필터링
grep ERROR /tmp/discovery_kvs_log_*.txt
```

## 다음 단계

1. **로깅 테스트**
   ```bash
   bash test-discovery-logging.sh
   ```

2. **실제 수집 실행**
   ```bash
   source lib/discovery.sh
   collect_infrastructure_data 1  # 로컬 테스트
   ```

3. **로그 검토 및 문제 진단**
   ```bash
   cat /tmp/discovery_kvs_log_1.txt
   ```

4. **실패 지점에 따른 해결**
   - 위의 "실패 지점별 해결 방법" 참고

5. **원격 서버 테스트** (SSH 설정 후)
   ```bash
   collect_infrastructure_data 2 root@<remote-host>:22
   cat /tmp/discovery_kvs_log_2.txt
   ```

## 문의 및 피드백

각 로그 항목이 구체적 진단 정보를 포함하고 있으므로, 실제 문제 발생시:

1. 해당 LSSN의 로그 파일 수집
2. 위의 진단 가이드에 따라 실패 지점 파악
3. 실패 지점의 해결 방법 적용

으로 문제를 빠르게 해결할 수 있습니다.
