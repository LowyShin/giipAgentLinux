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

### 운영 정리 (1회성, CQE 로 실행)
- `cleanup_nameless_lssn.sh` - lssn=0 자가등록 루프(giip 2928)가 만든 이름 없는 tLSvr 행(hostname/os/heartbeat 모두 NULL)을 LSvrDel 로 soft-delete (giip 2948). 기본 `--action dryrun`(쓰기 호출 없음), `--action apply` 는 롤백 SQL 출력 후 1건씩 삭제·재조회 검증. CQE 런처 본문과 종료코드는 스크립트 헤더 참조. 테스트: `tests/test-cleanup-nameless-lssn.sh`

### 버전 관리
- `git-auto-sync.sh` - Git 자동 동기화

## 🚀 사용법

각 스크립트는 다음과 같이 실행할 수 있습니다:

```bash
bash scripts/script-name.sh [options]
```

자세한 사용법은 각 스크립트의 헤더 주석을 참고하세요.
