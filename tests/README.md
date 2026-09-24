# Tests

테스트 및 검증 스크립트 모음

## 📄 파일 목록

### KVS 테스트
- `test-kvs-simple.sh` - KVS 기본 테스트
- `test-kvs-standard.sh` - KVS 표준 테스트
- `test-kvs-logging.sh` - KVS 로깅 테스트
- `test-kvs-api-direct.sh` - KVS API 직접 테스트
- `test-kvsput-simple.sh` - KVS PUT 기본 테스트
- `test-kvsput-remote.sh` - KVS PUT 원격 테스트 (scp/ssh 로 원격 서버에서 scripts/test-kvsput.sh 실행)

### Agent 테스트
- `test-agent-refactored.sh` - 리팩토링된 Agent 테스트
- `test-giipagent-diagnosis.sh` - Agent 진단 테스트

### Log Collector 테스트 (giip #1635)
- `test-cleanup-nameless-lssn.sh` - scripts/cleanup_nameless_lssn.sh 오프라인 검증(curl 스텁): dryrun 무쓰기, 잘못된 이스케이프 파싱(jq/awk), apply 요청 형식·롤백 SQL·실패 가드·시간 예산·fail-closed·CQE 런처 (giip 2948)
- `test-log-collector-offset-rotation.sh` - lib/log_collector.sh 오프셋 추적, 회전
  감지(inode 변경/truncate), 비밀 마스킹, 재시도 큐(용량 제한+drop-oldest) 단위 테스트.
  네트워크 호출은 로컬에서 mock 처리(api_post override) - 실 서버에 붙지 않는다.

### Gateway 테스트
- `test-gateway.sh` - Gateway 기본 테스트
- `test-gateway-discovery.sh` - Gateway 발견 테스트
- `test-discovery-logging.sh` - 발견 로깅 테스트

### CQE 테스트
- `test-cqe-queue.sh` - CQE 큐 테스트

### lssn=0 자동등록 테스트
- `test-lssn0-registration.sh` - 네트워크 없이(curl stub) lssn=0 자동등록을 검증:
  cnf 의 lssn 줄 갱신(따옴표/공백/CRLF 변형), inode 유지, 읽기전용 cnf → 사이드카
  `giipAgent.lssn` + load_config 반영, lssn=0 queue_get 차단, 잘못된 응답 시 cnf 불변.

### 데이터베이스 테스트
- `test-managed-db-api.sh` - 관리 DB API 테스트
- `test-managed-db-check.sh` - 관리 DB 체크 테스트
- `test-mysql-performance.sh` - MySQL 성능 테스트

### URL Test API
- `test-url-test-api.sh` - `/api/giip-proxy` 의 URLTestPut/URLTestGet 호출 검증 (`--token` 필수)

### 네트워크 & SSH
- `test-ssh-connection.sh` - SSH 연결 테스트
- `test-network-collection.sh` - 네트워크 수집 테스트 (scp/ssh 로 원격 서버에서 scripts/debug-network.sh 실행)

## 🚀 사용법

```bash
bash tests/test-name.sh
```

이 레포는 Linux 에이전트 전용이라 PowerShell(.ps1) 스크립트를 두지 않는다(giip 2951).
Windows 에이전트는 giipAgentWin 레포를 쓴다.

## ⚠️ 주의사항

- 테스트는 개발/테스트 환경에서만 실행하세요
- 프로덕션 환경에서의 실행 시 주의가 필요합니다
- 각 테스트는 독립적으로 실행 가능합니다
