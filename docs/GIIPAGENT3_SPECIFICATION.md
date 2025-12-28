# giipAgent3.sh 사양서 (Architecture & Module Specification)

> **📅 문서 메타데이터**  
> - 최초 작성: 2025-11-11  
> - 최종 수정: 2025-12-28  
> - 작성자: AI Agent  
> - 목적: giipAgent3 모듈 구조, KVS 로깅 규칙, 외부 스크립트 호출 구조 명세

---

## 🚨 필수 읽기 순서

**이 문서를 읽기 전에 꼭 먼저 읽어야 할 문서**:

| 문서 | 설명 |
|------|------|
| **⚠️ [SHELL_COMPONENT_SPECIFICATION.md](./SHELL_COMPONENT_SPECIFICATION.md)** | lib/*.sh 개발 표준 |
| **[CQE_SPECIFICATION.md](./CQE_SPECIFICATION.md)** | CQE (Centralized Queue Engine) 명세 |
| **[MODULAR_ARCHITECTURE.md](./MODULAR_ARCHITECTURE.md)** | 모듈 구조 개요 |

**관련 문서**:
- [AI_AGENT_GUIDELINES.md](./AI_AGENT_GUIDELINES.md) - AI Agent 작업 규칙 및 체크리스트
- [CHANGELOG.md](./CHANGELOG.md) - 변경 이력
- [DATABASE_CHECK_FLOW.md](./DATABASE_CHECK_FLOW.md) - MySQL 서버 리스트 수집 흐름
- [AUTO_DISCOVERY_ARCHITECTURE.md](./AUTO_DISCOVERY_ARCHITECTURE.md) - Discovery 설계
- [GATEWAY_SETUP_GUIDE.md](./GATEWAY_SETUP_GUIDE.md) - Gateway 환경 설정

---

## 📋 목차

1. [개요](#개요)
2. [핵심 용어 정의](#-핵심-용어-정의)
3. [모듈 구조](#모듈-구조)
4. [KVS 로깅 규칙](#kvs-로깅-규칙)
5. [버전 추적](#버전-추적)
6. [실행 흐름](#실행-흐름)
7. [외부 스크립트 호출 구조](#-외부-스크립트-호출-구조)

---

## 개요

**파일**: `giipAgentLinux/giipAgent3.sh`  
**버전**: 3.00  
**라인 수**: 378 lines (2025-12-28)  
**아키텍처**: Modular (lib/*.sh 라이브러리 분리)  
**모드**: Gateway + Normal (병행 실행)

---

## 🎯 핵심 용어 정의

### 1️⃣ Gateway 서버
**정의**: GIIP Agent가 Gateway 모드로 실행되는 서버

| 속성 | 값 |
|------|-----|
| **식별자** | `LSSN` (tLSvr) |
| **DB 표시** | `is_gateway = 1` |
| **역할** | 원격 서버 및 DB 중앙 관리 |
| **gateway_lssn** | NULL |

### 2️⃣ 리모트 서버
**정의**: Gateway가 SSH를 통해 원격 작업을 수행하는 서버

| 속성 | 값 |
|------|-----|
| **식별자** | `LSSN` (tLSvr) |
| **DB 표시** | `is_gateway = 0` |
| **gateway_lssn** | NOT NULL (관리하는 Gateway LSSN) |
| **Agent 설치** | ❌ 없음 |

### 3️⃣ 리모트 데이터베이스
**정의**: Gateway를 통해 접근하는 외부 DB

| 속성 | 값 |
|------|-----|
| **테이블** | `tManagedDatabase` |
| **식별자** | `mdb_id` |
| **gateway_lssn** | NOT NULL (필수) |

---

## 모듈 구조

### 메인 스크립트

**giipAgent3.sh**
- 역할: 진입점, 설정 로드, 모드 분기
- 위치: `giipAgentLinux/giipAgent3.sh`

### 라이브러리 모듈 (lib/*.sh)

#### lib/common.sh
**필수 로드**: ✅ 모든 모드

**제공 기능**:
- `load_config()`: 설정 로드
- `log_message()`: 로그 기록
- `error_handler()`: 에러 처리
- `detect_os()`: OS 감지

**로드 시점**: giipAgent3.sh 최우선

#### lib/kvs.sh
**필수 로드**: ✅ 모든 모드

**제공 기능**:
- `kvs_put()`: KVS 저장
- `save_execution_log()`: 실행 이력 저장

**KVS 로깅**: ✅ kFactor=giipagent

#### lib/cleanup.sh
**필수 로드**: ✅ 모든 모드

**제공 기능**:
- `cleanup_old_temp_files()`: 패턴 매칭 파일 삭제
- `cleanup_all_temp_files()`: 모든 임시 파일 정리

**정리 대상**:
- `/tmp/gateway_servers_*.json`
- `/tmp/remote_profile_*.json`
- `/tmp/queue_get_params_*.json`
- `/tmp/ssh_test_logs/`

#### lib/target_list.sh
**필수 로드**: ✅ 모든 모드

**제공 기능**:
- `display_target_servers()`: 서버 목록 표시
- `print_info/success/error/warning()`: 색상 출력

#### lib/gateway_api.sh
**필수 로드**: ⚠️ Gateway 모드만

**제공 기능**:
- `get_gateway_servers()`: Remote 서버 목록 조회

#### lib/check_managed_databases.sh
**필수 로드**: ⚠️ Gateway 모드만

**제공 기능**:
- `check_managed_databases()`: 관리 DB 체크

**외부 Python 스크립트**:
- `parse_managed_db_list.py`: JSON 파싱
- `extract_db_types.py`: DB 타입 추출

---

## KVS 로깅 규칙

### 절대 규칙: startup 로깅은 1번만!

**startup 로깅 위치**:
- Gateway 모드: `scripts/gateway_mode.sh`
- Normal 모드: `scripts/normal_mode.sh`

### KVS 이벤트 타입

| 이벤트 | 파일 | kFactor |
|--------|------|---------|
| startup | gateway_mode.sh / normal_mode.sh | giipagent |
| shutdown | giipAgent3.sh | giipagent |
| queue_check | normal_mode.sh | giipagent |

---

## 버전 추적

### 환경변수

```bash
export GIT_COMMIT="unknown"
export FILE_MODIFIED=$(stat -c %y "${BASH_SOURCE[0]}")
```

### startup JSON 구조

```json
{
  "pid": 12345,
  "config_file": "giipAgent.cnf",
  "git_commit": "a1b2c3d",
  "file_modified": "2025-11-11 09:30:00"
}
```

---

## 실행 흐름

### ⭐ 실행 모드 구조

**중요**: 이 구조는 **절대 수정하지 말 것!**

```
giipAgent3.sh 실행
  ↓
DB에서 is_gateway 조회
  ↓
┌─────────────────────┬─────────────────────┐
│ is_gateway=1        │ is_gateway=0        │
│ Gateway Mode 실행   │ (Gateway 스킵)      │
└─────────────────────┴─────────────────────┘
  ↓                     ↓
  └─────────┬───────────┘
            ↓
      Normal Mode (항상 실행)
            ↓
      Shutdown Log (1번만)
```

**핵심 규칙**:

| 항목 | 규칙 |
|------|------|
| 구조 | `if` 문 (else ❌) |
| Normal 모드 | **항상 실행** |
| Gateway 모드 | **조건부 실행** |
| Shutdown log | `fi` 다음 1번만 |

**절대 하면 안 될 것**:
- ❌ `if-else` 구조 (한 모드만 실행됨)
- ❌ Normal 모드를 Gateway 하위에 종속
- ❌ shutdown log 중복 작성

---

## 🎯 외부 스크립트 호출 구조

### 호출 계층도

```
giipAgent3.sh
│
├─ scripts/net3d_mode.sh (Net3D 수집)
│
├─ [if is_gateway=1] scripts/gateway_mode.sh
│  │
│  ├─ scripts/gateway-fetch-servers.sh
│  ├─ scripts/gateway-ssh-test.sh
│  └─ scripts/gateway-check-db.sh
│
└─ [항상] scripts/normal_mode.sh
```

### 파일별 역할

| 파일 | 호출자 | 용도 | 독립 실행 |
|------|--------|------|---------|
| **net3d_mode.sh** | giipAgent3.sh | Net3D 수집 | ✅ 가능 |
| **gateway_mode.sh** | giipAgent3.sh | Gateway 오케스트레이터 | ✅ 가능 |
| **gateway-fetch-servers.sh** | gateway_mode.sh | 서버 목록 조회 | ✅ 가능 |
| **gateway-ssh-test.sh** | gateway_mode.sh | SSH 테스트 | ✅ 가능 |
| **gateway-check-db.sh** | gateway_mode.sh | DB 체크 | ✅ 가능 |
| **normal_mode.sh** | giipAgent3.sh | Normal 모드 | ✅ 가능 |

### 호출 특징

#### 독립 실행 가능
각 스크립트는 bash로 독립 실행:
```bash
bash scripts/gateway-fetch-servers.sh /path/to/config
```

#### 오케스트레이터 패턴
gateway_mode.sh는 순서대로 실행:
1. gateway-fetch-servers.sh
2. gateway-ssh-test.sh  
3. gateway-check-db.sh

#### 라이브러리 로드 순서
```bash
. "${LIB_DIR}/common.sh"
. "${LIB_DIR}/kvs.sh"
```

---

## 📊 파일 구조 요약

```
giipAgentLinux/
├── giipAgent3.sh           # 메인 진입점
│
├── scripts/
│   ├── net3d_mode.sh       # Net3D 수집
│   ├── gateway_mode.sh     # Gateway 오케스트레이터
│   ├── gateway-fetch-servers.sh
│   ├── gateway-ssh-test.sh
│   ├── gateway-check-db.sh
│   └── normal_mode.sh      # Normal 모드
│
└── lib/
    ├── common.sh           # 공통 함수
    ├── kvs.sh              # KVS 로깅
    ├── cleanup.sh          # 임시 파일 정리
    ├── target_list.sh      # 서버 목록 표시
    ├── gateway_api.sh      # Gateway API
    ├── check_managed_databases.sh  # DB 체크
    ├── parse_managed_db_list.py    # JSON 파싱
    └── extract_db_types.py         # DB 타입 추출
```

---

## 🔗 관련 문서

- [AI_AGENT_GUIDELINES.md](./AI_AGENT_GUIDELINES.md) - AI Agent 작업 규칙
- [CHANGELOG.md](./CHANGELOG.md) - 변경 이력
- [DATABASE_CHECK_FLOW.md](./DATABASE_CHECK_FLOW.md) - DB 체크 흐름
