# GIIP Agent for Linux

![GIIP Logo](https://giipasp.azurewebsites.net/logo.png)

**Version**: 3.0 (Modular Architecture)

## 🌟 개념

GIIP Agent는 서버 모니터링 및 원격 관리 시스템입니다.

**주요 기능:**
- ✅ CQE (Command Queue Execution) - 중앙에서 원격 명령 실행
- ✅ Gateway Mode - 다중 서버 관리 (SSH 기반)
- ✅ Auto-Discovery - 인프라 자동 수집 (OS, 하드웨어, 소프트웨어, 서비스)
- ✅ KVS 로깅 - 모든 실행 이력 자동 기록
- ✅ 5분 주기 하트비트 리포팅

**배포 옵션:**
- **표준 에이전트**: 각 서버에 직접 설치
- **Gateway 에이전트**: 게이트웨이 서버에 설치하여 다중 서버 관리

## 📁 디렉토리 구조

```
giipAgentLinux/
├── 📄 giipAgent3.sh          # 메인 에이전트 (권장)
├── 📄 giipAgent.cnf          # 설정 파일 (템플릿)
├── 📄 README.md              # 이 문서
│
├── 📁 docs/                  # 상세 문서 모음
├── 📁 lib/                   # 핵심 라이브러리 함수
├── 📁 giipscripts/           # 기본 스크립트 (auto-discover 등)
├── 📁 scripts/               # 유틸리티 스크립트 (진단, 모니터링)
├── 📁 gateway/               # Gateway 모드 관련
├── 📁 cqe/                   # CQE (Command Queue Execution)
├── 📁 admin/                 # 관리자 스크립트 (설치, 등록)
└── 📁 tests/                 # 테스트 스크립트
```

## 🚀 빠른 시작

### 1. 설치

```bash
cd ~
git clone https://github.com/LowyShin/giipAgentLinux.git
cd giipAgentLinux

# 설정 파일 준비 (홈 디렉토리의 giipAgent 폴더에 위치해야 함!)
mkdir -p ~/giipAgent
cp giipAgent.cnf ~/giipAgent/
vi ~/giipAgent/giipAgent.cnf  # sk, lssn 입력

# 설치
sudo ./admin/giipcronreg.sh
```

**⚠️ 중요:** `giipAgent.cnf`는 **홈 디렉토리의 `giipAgent` 폴더**에 위치해야 합니다!
- 에이전트 경로: `~/giipAgentLinux/`
- 설정 파일: `~/giipAgent/giipAgent.cnf` ✅

### 2. 설정 확인

```bash
# 설정 파일 확인
cat ~/giipAgent/giipAgent.cnf | grep -E "sk=|lssn=|apiaddrv2="

# Cron 등록 확인
crontab -l | grep giip
```

### 3. 배포 모드 선택

**표준 모드** (각 서버에 직접 설치)
```bash
# 그대로 사용 - 5분마다 자동 실행
```

**Gateway 모드** (다중 서버 관리)
- 설정: [Gateway 빠른 시작](gateway/GATEWAY_QUICKSTART_KR.md)

## 📚 문서 링크

### 🆕 핵심 문서
- **[설치 상세 가이드](docs/INSTALLATION_DETAILED.md)** - 단계별 설치 절차
- **[설정 가이드](docs/CONFIGURATION_GUIDE.md)** - 설정 파일 상세 설명

### 📋 개념 & 아키텍처
- [모듈식 아키텍처](docs/MODULAR_ARCHITECTURE.md) - v3.0 설계
- [giipAgent3.sh 명세서](docs/GIIPAGENT3_SPECIFICATION.md) - 실행 조건, 동작 흐름
- [SSH 연결 모듈](docs/SSH_CONNECTION_MODULE_GUIDE.md) - SSH 테스트 모듈
- [Auto-Discovery 아키텍처](docs/AUTO_DISCOVERY_ARCHITECTURE.md) - 자동 수집 구조
- [서비스 필터링](docs/SERVICE_PACKAGE_FILTER.md) - 소프트웨어 필터 규칙

### 🚀 기능별 가이드
- **[CQE 명세서](docs/CQE_SPECIFICATION.md)** - 원격 명령 실행 시스템
- **[DPA 통합 가이드](docs/DPA_INTEGRATION_TEST.md)** - 데이터베이스 성능 분석
- **[Utility Scripts 가이드](docs/UTILITY_SCRIPTS_GUIDE.md)** - 진단 및 모니터링 스크립트

### 🏢 Gateway 모드
- **[Gateway 설정 철학](docs/GATEWAY_CONFIG_PHILOSOPHY.md)** - 필독!
- **[Gateway 설정 가이드](docs/GATEWAY_SETUP_GUIDE.md)** - 실제 환경 설정
- [Gateway 빠른 시작](gateway/GATEWAY_QUICKSTART_KR.md) - 한글 가이드
- [Gateway README](gateway/README_GATEWAY.md) - 전체 매뉴얼

### 🔧 운영 & 문제해결
- **[문제 해결 가이드](docs/TROUBLESHOOTING_GUIDE.md)** - 일반 문제 해결
- **[제거 가이드](docs/UNINSTALLATION.md)** - 설치 제거

### 🔗 외부 문서
- [API 엔드포인트 비교](../giipfaw/docs/API_ENDPOINTS_COMPARISON.md) - giipApi vs giipApiSk vs giipApiSk2
- [Agent 설치 가이드](../giipdb/docs/AGENT_INSTALLATION_GUIDE.md) - 전체 설치 프로세스
- [테스트 서버 설정](../giipdb/docs/TEST_SERVER_INSTALLATION.md) - 테스트 환경
- [보안 체크리스트](../giipdb/docs/SECURITY_CHECKLIST.md) - 보안 점검

## ⚠️ 주의사항

### 설정 파일 위치
- **템플릿**: `giipAgentLinux/giipAgent.cnf` (저장소 내)
- **실제 사용**: `~/giipAgent/giipAgent.cnf` (홈 디렉토리)
  - 예: `/home/username/giipAgent/giipAgent.cnf`

### 프로덕션 문제 해결
```bash
# ❌ 저장소의 템플릿은 참고용만
cat giipAgentLinux/giipAgent.cnf

# ✅ 서버의 실제 설정 파일 확인
ssh user@server "cat ~/giipAgent/giipAgent.cnf"
```

## 📞 지원

- **GitHub Issues**: https://github.com/LowyShin/giipAgentLinux/issues
- **Email**: support@giip.io
- **Web**: https://giipasp.azurewebsites.net

## 📄 라이선스

인프라 관리 및 모니터링용 무료 사용
