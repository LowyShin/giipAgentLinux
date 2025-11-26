# Tests

테스트 및 검증 스크립트 모음

## 📄 파일 목록

### KVS 테스트
- `test-kvs-simple.sh` - KVS 기본 테스트
- `test-kvs-standard.sh` - KVS 표준 테스트
- `test-kvs-logging.sh` - KVS 로깅 테스트
- `test-kvs-api-direct.sh` - KVS API 직접 테스트
- `test-kvsput-simple.sh` - KVS PUT 기본 테스트
- `test-kvsput-remote.ps1` - KVS PUT 원격 테스트

### Agent 테스트
- `test-agent-refactored.sh` - 리팩토링된 Agent 테스트
- `test-giipagent-diagnosis.sh` - Agent 진단 테스트

### Gateway 테스트
- `test-gateway.sh` - Gateway 기본 테스트
- `test-gateway-discovery.sh` - Gateway 발견 테스트
- `test-discovery-logging.sh` - 발견 로깅 테스트

### CQE 테스트
- `test-cqe-queue.sh` - CQE 큐 테스트

### 데이터베이스 테스트
- `test-managed-db-api.sh` - 관리 DB API 테스트
- `test-managed-db-check.sh` - 관리 DB 체크 테스트
- `test-mysql-performance.sh` - MySQL 성능 테스트

### 네트워크 & SSH
- `test-ssh-connection.sh` - SSH 연결 테스트
- `test-network-collection.ps1` - 네트워크 수집 테스트

## 🚀 사용법

```bash
bash tests/test-name.sh
```

또는 PowerShell 스크립트:

```powershell
pwsh tests/test-name.ps1
```

## ⚠️ 주의사항

- 테스트는 개발/테스트 환경에서만 실행하세요
- 프로덕션 환경에서의 실행 시 주의가 필요합니다
- 각 테스트는 독립적으로 실행 가능합니다
