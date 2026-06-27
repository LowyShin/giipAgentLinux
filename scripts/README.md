# Scripts

일반 유틸리티 및 유지보수 스크립트 모음

## 📄 파일 목록

### 진단 & 모니터링
- `check-gateway-execution.sh` - Gateway 실행 상태 확인
- `check-process-flood.sh` - 프로세스 폭증 진단
- `collect-perfmon.sh` - 성능 지표 수집
- `collect-server-diagnostics.sh` - 서버 진단 정보 수집
- `diagnose-server-load.sh` - 서버 부하 진단

### 자동 발견 & 동기화
- `giip-auto-discover.sh` - 시스템 자동 발견
- `sync-gateway-servers.sh` - Gateway 서버 동기화
- `sync-time.sh` - 시간 동기화

### 실행 & 관리
- `run-agent2-with-kvs.sh` - KVS를 사용한 Agent 실행
- `run-gateway-agent.sh` - Gateway Agent 실행

### 버전 관리
- `git-auto-sync.sh` - Git 자동 동기화

## 🚀 사용법

각 스크립트는 다음과 같이 실행할 수 있습니다:

```bash
bash scripts/script-name.sh [options]
```

자세한 사용법은 각 스크립트의 헤더 주석을 참고하세요.
