# ⚠️ 새로운 설정 추가 전 필수 체크리스트

## 🚫 STOP! 설정 파일에 추가하기 전에 읽어보세요

### 질문 1: 이 설정이 Gateway 관련인가요?

```
YES → DB에 저장하세요 (CNF 파일 ❌)
NO  → 질문 2로 이동
```

**Gateway 관련 설정 예시**:
- `gateway_mode` → ❌ CNF에 추가 금지 (DB의 `is_gateway` 사용)
- `gateway_serverlist` → ❌ CNF에 추가 금지 (API로 실시간 조회)
- `gateway_heartbeat_interval` → ❌ CNF에 추가 금지 (하드코딩)
- `gateway_ssh_*` → ❌ CNF에 추가 금지 (DB의 `tLSvr.gateway_ssh_*` 사용)

### 질문 2: 이 설정이 서버마다 다른가요?

```
YES → DB에 저장하세요 (CNF 파일 ❌)
NO  → 질문 3으로 이동
```

**서버별 설정 예시**:
- SSH 주소, 포트, 사용자명
- 데이터베이스 연결 정보
- 수집 주기, 임계값
- 활성화/비활성화 상태

### 질문 3: 이 설정이 웹 UI에서 변경 가능해야 하나요?

```
YES → DB에 저장하세요 (CNF 파일 ❌)
NO  → 질문 4로 이동
```

**웹 UI 관리 설정 예시**:
- 알림 임계값
- 백업 스케줄
- 로그 보관 기간
- 기능 활성화 플래그

### 질문 4: 이 설정이 런타임에 변경되어야 하나요?

```
YES → DB에 저장하세요 (CNF 파일 ❌)
NO  → CNF 파일에 추가 가능 (단, 아래 조건 충족 시)
```

---

## ✅ CNF 파일에 추가 가능한 경우

**모든 조건을 만족해야 합니다**:

1. [ ] Gateway 관련 **아님**
2. [ ] 모든 서버에서 **동일한 값** 사용
3. [ ] 웹 UI에서 변경 **불필요**
4. [ ] Agent 재시작 없이 변경 **불필요**
5. [ ] 인증 정보 또는 API 엔드포인트 같은 **공통 설정**

**허용되는 CNF 설정 예시**:
```ini
sk="<secret_key>"                # ✅ 인증 정보 (공통)
lssn="0"                         # ✅ 서버 식별자 (초기값)
giipagentdelay="60"              # ✅ 실행 주기 (공통)
apiaddrv2="https://..."          # ✅ API URL (공통)
apiaddrcode="..."                # ✅ API 코드 (공통)
```

---

## ❌ CNF 파일에 추가 금지 예시

### 금지 1: Gateway 관련 모든 설정

```ini
# ❌ 절대 추가하지 말 것!
gateway_mode="1"
gateway_serverlist="servers.csv"
gateway_heartbeat_interval="300"
gateway_sync_interval="300"
gateway_check_interval="60"

# ✅ 대신 사용:
# - gateway_mode → DB의 tLSvr.is_gateway (API로 조회)
# - serverlist → pApiGatewayRemoteServerListForAgentbySK (API로 조회)
# - interval → giipagentdelay 사용 (공통 설정)
```

### 금지 2: 서버별로 다른 설정

```ini
# ❌ 절대 추가하지 말 것!
ssh_host="192.168.1.21"
ssh_port="22"
backup_enabled="1"
alert_threshold="80"

# ✅ 대신 사용:
# DB의 tLSvr 테이블에 컬럼 추가
# 웹 UI (lsvrdetail)에서 관리
```

### 금지 3: 파일 경로 캐시

```ini
# ❌ 절대 추가하지 말 것!
server_cache_file="./cache/servers.json"
db_query_cache="./cache/queries.csv"
temp_script_dir="/tmp/scripts"

# ✅ 대신 사용:
# - 임시 파일은 /tmp에 자동 생성
# - 처리 후 즉시 삭제
# - 캐싱하지 말고 매번 API 조회
```

### 금지 4: 런타임 변경 가능한 설정

```ini
# ❌ 절대 추가하지 말 것!
debug_mode="0"
log_level="INFO"
retry_count="3"

# ✅ 대신 사용:
# DB에 저장하여 웹 UI에서 변경
# 또는 환경변수로 전달
```

---

## 🔄 설정 추가 프로세스

### CNF 파일에 추가할 경우:

```bash
# 1. 위 체크리스트 모두 확인
# 2. 설정 추가
vi giipAgent.cnf

# 3. 주석으로 설명 추가 (필수!)
# 4. 기본값 설정
# 5. Agent 재시작 테스트
# 6. 문서 업데이트
```

### DB에 추가할 경우 (권장):

```sql
-- 1. 테이블 컬럼 추가
ALTER TABLE tLSvr ADD new_setting VARCHAR(100) NULL;

-- 2. SP 수정 (API 반환값에 포함)
ALTER PROCEDURE pApiLSvrGetConfigbySK ...

-- 3. 웹 UI 화면 추가
-- giipv3/src/app/[locale]/lsvrdetail/page.tsx

-- 4. Agent 코드 수정 (API 값 사용)
-- giipAgentLinux/giipAgent3.sh
```

---

## 📋 설정 추가 체크리스트

새로운 설정을 추가할 때:

### 계획 단계
- [ ] Gateway 관련인지 확인 → DB 저장
- [ ] 서버별로 다른 값인지 확인 → DB 저장
- [ ] 웹 UI 관리 필요한지 확인 → DB 저장
- [ ] 런타임 변경 필요한지 확인 → DB 저장
- [ ] 위 모두 아니면 → CNF 파일 가능

### CNF 파일 추가 시
- [ ] 명확한 주석 작성
- [ ] 기본값 설정
- [ ] 타입 검증 코드 추가
- [ ] 에러 처리 추가
- [ ] README 문서 업데이트

### DB 추가 시 (권장)
- [ ] 테이블 스키마 변경
- [ ] SP 수정 (조회 API)
- [ ] 웹 UI 화면 추가
- [ ] Agent 코드 수정
- [ ] 마이그레이션 스크립트 작성
- [ ] API 문서 업데이트

---

## 🎯 원칙 요약

### 1. Database First
```
설정 추가 고민 중? → 일단 DB에 저장하세요
CNF 파일은 최후의 수단입니다
```

### 2. Single Source of Truth
```
같은 설정을 두 곳에 저장하지 마세요
DB 또는 CNF 중 하나만 선택하세요
```

### 3. No File Caching
```
CSV, JSON 파일로 캐싱하지 마세요
매번 API로 최신 값을 가져오세요
```

### 4. Web UI Friendly
```
사용자가 SSH 접속해서 파일 편집하게 하지 마세요
웹 UI에서 클릭 몇 번으로 변경 가능하게 하세요
```

---

## 🔍 실제 사례

### ❌ 잘못된 사례

```ini
# giipAgent.cnf (잘못된 예시)
gateway_mode="1"                    # DB와 충돌 가능
gateway_heartbeat_interval="300"    # 불필요한 설정
gateway_serverlist="servers.csv"    # DB 조회하면 됨
backup_schedule="0 2 * * *"         # 서버별로 다를 수 있음
```

**문제점**:
- CNF의 `gateway_mode`와 DB의 `is_gateway`가 다르면?
- `heartbeat_interval`을 변경하려면 모든 서버에 SSH 접속?
- CSV 파일이 DB와 동기화 안되면?
- cron 스케줄을 웹 UI에서 변경 못함

### ✅ 올바른 사례

```ini
# giipAgent.cnf (올바른 예시)
sk="your_secret_key"                # ✅ 공통 인증
lssn="0"                            # ✅ 초기값
giipagentdelay="60"                 # ✅ 공통 주기
apiaddrv2="https://..."             # ✅ API URL
```

```sql
-- DB (tLSvr 테이블)
is_gateway bit                      -- ✅ Gateway 모드
gateway_heartbeat_enabled bit       -- ✅ Heartbeat 활성화
backup_schedule varchar(50)         -- ✅ Backup 스케줄
alert_threshold int                 -- ✅ 알림 임계값
```

**장점**:
- 웹 UI에서 모든 설정 변경 가능
- Agent 재시작 불필요
- 설정 히스토리 추적 가능
- 서버별 다른 값 설정 가능

---

## 📖 참고 문서

- **설정 철학**: `docs/GATEWAY_CONFIG_PHILOSOPHY.md`
- **DB 스키마**: `giipdb/Tables/tLSvr.sql`
- **API 문서**: `giipdb/SP/pApiLSvrGetConfigbySK.sql`
- **Agent 코드**: `giipAgentLinux/giipAgent3.sh`

---

**작성일**: 2025-11-10  
**버전**: 1.0  
**목적**: CNF 파일 오염 방지 및 DB 중심 설계 유도
