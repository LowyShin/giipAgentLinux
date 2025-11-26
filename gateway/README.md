# Gateway

Gateway 관련 스크립트 및 문서

## 📄 핵심 파일

### 실행 스크립트
- `giipAgentGateway.sh` - Gateway Agent 메인 스크립트
- `giipAgentGateway-heartbeat.sh` - Gateway 하트비트 모니터링

### 설정 & 템플릿
- `giipAgentGateway_servers.csv.template` - Gateway 서버 목록 템플릿

### 발견 (Discovery)
- `GATEWAY_DISCOVERY_FILES.sh` - Gateway 발견 파일 목록
- `GATEWAY_DISCOVERY_SUMMARY.md` - Gateway 발견 요약

### 문서
- `README_GATEWAY.md` - Gateway 사용 가이드
- `README_GATEWAY_DISCOVERY.md` - Gateway 발견 가이드
- `GATEWAY_QUICKSTART_KR.md` - Gateway 빠른 시작 가이드 (한국어)

## 🚀 빠른 시작

1. `giipAgentGateway_servers.csv.template`을 복사하여 `giipAgentGateway_servers.csv` 생성
2. 서버 정보 입력
3. `bash giipAgentGateway.sh` 실행

자세한 내용은 해당 README 파일들을 참고하세요.

## 📖 주요 문서

- **GATEWAY_QUICKSTART_KR.md** - 가장 먼저 읽기
- **README_GATEWAY.md** - 상세 설정 가이드
- **README_GATEWAY_DISCOVERY.md** - 발견 기능 상세 설명
