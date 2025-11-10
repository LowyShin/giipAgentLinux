# Gateway 설정 철학: Database as Single Source of Truth

## 🎯 핵심 원칙

**모든 Gateway 설정은 데이터베이스에서만 관리한다**

```
❌ CNF 파일에 Gateway 설정 추가 금지
✅ DB (tLSvr 테이블)에만 저장
✅ 웹 UI (lsvrdetail)에서만 수정
```

---

## 📋 설정 관리 위치

### ✅ CNF 파일 (`giipAgent.cnf`) - 최소한의 공통 설정만

```ini
# Agent 공통 설정 (Gateway/Normal 모두 사용)
sk="<your secret key>"          # ✅ 인증 정보
lssn="0"                         # ✅ 서버 식별자
giipagentdelay="60"              # ✅ 실행 주기
apiaddrv2="https://..."          # ✅ API 엔드포인트
apiaddrcode="..."                # ✅ API 인증 코드

# ⚠️ 아래 항목들은 절대 추가하지 말 것!
# gateway_mode              → DB에서 자동 감지
# gateway_serverlist        → DB에서 실시간 조회
# gateway_heartbeat_interval → 하드코딩 (매 사이클마다)
# gateway_ssh_*             → DB (tLSvr)에 저장
```

### ✅ 데이터베이스 (tLSvr 테이블) - Gateway 전용 설정

```sql
-- Gateway 서버 설정 (Gateway 자신)
is_gateway bit                    -- 1=Gateway 모드, 0=Normal 모드
gateway_lssn int                  -- NULL (Gateway는 자기 자신을 관리 안함)

-- 원격 서버 설정 (Gateway가 관리하는 서버들)
gateway_lssn int                  -- Gateway 서버의 LSSN (어떤 Gateway가 관리하는지)
gateway_ssh_host varchar(200)     -- SSH 접속 주소
gateway_ssh_user varchar(50)      -- SSH 사용자명
gateway_ssh_port int              -- SSH 포트 (기본: 22)
gateway_ssh_key_path varchar(500) -- SSH 키 파일 경로
gateway_ssh_password varbinary    -- SSH 비밀번호 (암호화)
```

---

## 🔄 설정 흐름

```
┌─────────────────────────────────────────────────────┐
│ 1. 웹 UI (lsvrdetail 페이지)                        │
│    - is_gateway 체크박스                            │
│    - Gateway SSH 설정 입력                          │
└────────────┬────────────────────────────────────────┘
             │ 저장
             ▼
┌─────────────────────────────────────────────────────┐
│ 2. DB (tLSvr 테이블)                                │
│    - 단일 진실 공급원 (Single Source of Truth)     │
│    - 모든 설정이 여기 저장됨                        │
└────────────┬────────────────────────────────────────┘
             │ API 조회
             ▼
┌─────────────────────────────────────────────────────┐
│ 3. Agent 시작 (giipAgent2.sh)                       │
│    - pApiLSvrGetConfigbySK 호출                     │
│    - is_gateway 값으로 모드 자동 결정               │
└────────────┬────────────────────────────────────────┘
             │ Gateway 모드면
             ▼
┌─────────────────────────────────────────────────────┐
│ 4. 서버 목록 조회                                   │
│    - pApiGatewayRemoteServerListForAgentbySK 호출   │
│    - JSON으로 서버 목록 받음 (CSV 파일 없음!)      │
└────────────┬────────────────────────────────────────┘
             │ 매 사이클마다
             ▼
┌─────────────────────────────────────────────────────┐
│ 5. 서버 상태 수집 및 명령 실행                      │
│    - 매번 DB에서 최신 정보 가져옴                   │
│    - 메모리에서 처리 (파일 캐시 없음)               │
└─────────────────────────────────────────────────────┘
```

---

## ❌ 금지 사항 (NEVER DO THIS!)

### 1. CNF 파일에 Gateway 설정 추가 금지

```ini
# ❌ 절대 추가하지 말 것!
gateway_mode="1"                    # DB에서 자동 감지함
gateway_serverlist="servers.csv"    # CSV 파일 사용 안함 (DB 직접 조회)
gateway_heartbeat_interval="300"    # 하드코딩됨 (매 사이클)
gateway_sync_interval="300"         # 실시간 조회 (동기화 개념 없음)
```

**이유**:
- CNF 파일과 DB 값이 달라지면 충돌 발생
- 어느 것이 진짜 설정인지 혼란
- 디버깅 복잡도 증가

### 2. CSV 파일 캐싱 금지

```bash
# ❌ 절대 만들지 말 것!
sync_gateway_servers() {
    wget ... > gateway_servers.csv  # NO!
}

# ✅ 매번 DB에서 직접 조회
get_gateway_servers() {
    wget ... > /tmp/temp.json  # 임시 파일만 사용
    # 처리 후 즉시 삭제
}
```

**이유**:
- CSV 파일과 DB가 동기화 안되면 문제
- 파일 권한, 경로 문제
- 실시간 반영 안됨

### 3. Interval을 CNF에 추가하지 말 것

```bash
# ❌ 절대 추가하지 말 것!
gateway_heartbeat_interval="300"
gateway_check_interval="60"
gateway_sync_interval="300"

# ✅ 스크립트에 하드코딩 또는 매 사이클 실행
# giipagentdelay (공통 설정)에 따라 모든 작업 수행
```

**이유**:
- Gateway는 `giipagentdelay`마다 실행됨
- 별도 interval 불필요 (복잡도만 증가)
- 타이밍 충돌 가능성

---

## ✅ 올바른 설정 방법

### 시나리오 1: Gateway 모드 활성화

```sql
-- 웹 UI에서 실행되는 SQL (자동)
UPDATE tLSvr 
SET is_gateway = 1 
WHERE lssn = 71240;

-- Agent가 다음 시작 시 자동으로 Gateway 모드로 전환됨
-- CNF 파일 수정 불필요!
```

### 시나리오 2: 원격 서버 추가

```sql
-- 웹 UI에서 실행되는 SQL (자동)
UPDATE tLSvr 
SET gateway_lssn = 71240,           -- Gateway LSSN
    gateway_ssh_host = '192.168.1.21',
    gateway_ssh_user = 'root',
    gateway_ssh_port = 22,
    gateway_ssh_key_path = '~/.ssh/key'
WHERE lssn = 71221;

-- Gateway가 다음 사이클에 자동으로 이 서버 관리 시작
-- CSV 파일 편집 불필요!
```

### 시나리오 3: SSH 비밀번호 변경

```sql
-- 웹 UI에서 실행되는 SQL (자동)
UPDATE tLSvr 
SET gateway_ssh_password = dbo.lwEncryptPassword('new_password')
WHERE lssn = 71221;

-- Agent가 다음 사이클에 자동으로 새 비밀번호 사용
-- CNF 파일 수정 불필요!
```

---

## 🔍 설정 디버깅

### Agent가 어떤 모드로 실행되는지 확인

```bash
# 로그 확인
tail -f ~/giipAgent/logs/giipAgent*.log

# 출력 예시 (Gateway 모드):
# [20251110123456] [Init] ✅ Gateway mode ENABLED (is_gateway=1 in DB)
# [20251110123456] ========================================
# [20251110123456] Starting GIIP Agent V2.0 in GATEWAY MODE

# 출력 예시 (Normal 모드):
# [20251110123456] [Init] ℹ️  Normal agent mode (is_gateway=0 in DB)
```

### DB 설정 직접 확인

```sql
-- Gateway 서버 확인
SELECT lssn, LSHostname, is_gateway 
FROM tLSvr 
WHERE lssn = 71240;

-- 원격 서버 목록 확인
SELECT lssn, LSHostname, gateway_lssn, gateway_ssh_host 
FROM tLSvr 
WHERE gateway_lssn = 71240;
```

---

## 📖 관련 문서

- **API 문서**: `giipdb/SP/pApiLSvrGetConfigbySK.sql`
- **서버 목록 API**: `giipdb/SP/pApiGatewayRemoteServerListForAgentbySK.sql`
- **Agent 구현**: `giipAgentLinux/giipAgent2.sh` (Line 1240-1300)
- **테이블 스키마**: `giipdb/Tables/tLSvr.sql`

---

## 🎓 개발자를 위한 체크리스트

새로운 Gateway 기능 추가 시:

- [ ] CNF 파일에 새 설정 추가하려고 하는가? → ❌ **하지 마세요!**
- [ ] DB 테이블에 컬럼을 추가했는가? → ✅ **올바릅니다**
- [ ] 웹 UI에서 설정할 수 있는가? → ✅ **필수입니다**
- [ ] Agent가 API로 조회하는가? → ✅ **올바릅니다**
- [ ] CSV 파일을 만들려고 하는가? → ❌ **하지 마세요!**
- [ ] 설정이 실시간 반영되는가? → ✅ **확인 필수**

---

## 🔒 원칙 요약

1. **Database = Single Source of Truth**
   - 모든 설정은 DB에만 저장
   - CNF 파일은 공통 인증 정보만

2. **No File Caching**
   - CSV 파일 없음
   - JSON은 메모리에서만 처리
   - 임시 파일은 즉시 삭제

3. **Real-time Configuration**
   - 매 사이클마다 DB 조회
   - 설정 변경 즉시 반영
   - Agent 재시작 불필요

4. **Web UI for Everything**
   - SSH로 CNF 파일 편집 금지
   - 웹 UI에서만 설정 변경
   - 감사 로그 자동 기록

---

**작성일**: 2025-11-10  
**버전**: 1.0  
**담당**: GIIP Development Team
