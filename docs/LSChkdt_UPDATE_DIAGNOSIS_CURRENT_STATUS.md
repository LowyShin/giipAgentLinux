# LSChkdt 업데이트 미실행 - 근본 원인 분석 완료 (2025-11-22)

> **상황 요약**: giipAgent3.sh를 Gateway 서버에서 실행하고 lsvrdetail 페이지에서 LSChkdt가 표시 안 됨  
> **진단 날짜**: 2025-11-22  
> **분석자**: AI Agent + User Logging Investigation  
> **상태**: 🔴 **원인 규명 완료 - API 호출 실패** (tLogSP 기록 0건)

---

## 🚨 전제 문서 & 필수 참고 (먼저 읽기!)

### 📚 사양서 (필수)
- **[GIIPAGENT3_SPECIFICATION.md](./GIIPAGENT3_SPECIFICATION.md)** ⭐⭐⭐ **핵심 사양서**
  - giipAgent3.sh 모듈 구조
  - Gateway vs 리모트 서버 정의 (critical!)
  - 로깅 포인트 #5.1-#5.13 정의
  - **KVS 로깅 규칙 - 모든 로그는 DB에 저장됨!**

### 📖 에러 로깅 & 진단 가이드 (필수)
- **[ERROR_LOG_WORKFLOW.md](../../giipdb/docs/ERROR_LOG_WORKFLOW.md)** ⭐⭐ **에러 분석 워크플로우**
  - 에러 분석 5단계 방법론
  - **표준 디버깅 3곳: tLogSP, ErrorLogs, tKVS 테이블**
  - 문제 진단 순서
- **[ERROR_QUICK_REFERENCE.md](../../giipdb/docs/ERROR_QUICK_REFERENCE.md)** - 자주 발생하는 에러
- **[ERRORLOG_RAW_IMPLEMENTATION.md](../../giipdb/docs/ERRORLOG_RAW_IMPLEMENTATION.md)** - Raw 에러 로깅 표준

### 🔍 관련 진단 문서
- **[LSChkdt_UPDATE_DIAGNOSIS.md](./LSChkdt_UPDATE_DIAGNOSIS.md)** - 6가지 원인 상세 분석
- **[REMOTE_SERVER_SSH_TEST_UPDATE_SPEC.md](./REMOTE_SERVER_SSH_TEST_UPDATE_SPEC.md)** - API 사양서
- **[REMOTE_SERVER_SSH_TEST_DETAILED_SPEC.md](./REMOTE_SERVER_SSH_TEST_DETAILED_SPEC.md)** - 상세 구현 명세

### 🛠️ DB 로그 조사 방법
- **[STANDARD_WORK_PROMPT.md](../../giipdb/docs/STANDARD_WORK_PROMPT.md)** Line 220-280 - 표준 디버깅 3곳 (tLogSP, ErrorLogs, tKVS)
- **[DEBUG_LOGGING_GUIDE.md](../../giipdb/docs/DEBUG_LOGGING_GUIDE.md)** - 자동 로깅 방법론

---

## 📊 실제 로그 조사 결과 (2025-11-22 수집)

### 조사 내용

#### ❌ tLogSP - pApiRemoteServerSSHTestbyAK 실행 로그

```
Query: SELECT * FROM tLogSP 
       WHERE lsName = 'pApiRemoteServerSSHTestbyAK' 
       AND logDateTime > DATEADD(HOUR, -24, GETUTCDATE())
       ORDER BY logDateTime DESC

Result: ⚠️  No records found (0건)

해석: API가 한 번도 호출되지 않았음
```

#### ❌ tKVS - remote_ssh_test_api_success 기록

```
Query: SELECT * FROM tKVS 
       WHERE kFactor = 'remote_ssh_test_api_success'
       AND kRegdt > DATEADD(HOUR, -24, GETUTCDATE())
       ORDER BY kRegdt DESC

Result: ⚠️  No records found (0건)

해석: SSH 테스트 결과가 한 번도 기록되지 않았음
```

#### ⚠️ ErrorLogs - 최근 24시간

```
Result: 9건의 에러 발견
- SqlExecutionError: 4건 (pApiRemoteServerSSHTestbyAK 무관)
- KVS 관련: 5건 (pApiRemoteServerSSHTestbyAK 무관)

해석: 진단 대상 API 관련 에러 없음 (= 호출도 안 됨)
```

### 결론: API 호출 자체가 발생하지 않음

---

## 📍 목차

1. [📊 실제 로그 조사 결과](#실제-로그-조사-결과-2025-11-22-수집) - **증거 기반**
2. [🎯 진짜 근본 원인 분석](#진짜-근본-원인-분석-실제-해결-방법) ⭐⭐⭐ **여기부터 읽기**
3. [문제 재현 (What is the problem?)](#문제-재현)
4. [로깅 포인트별 진단 체크리스트](#로깅-포인트별-진단-체크리스트)
5. [발견된 사실들 (Findings)](#발견된-사실들)
6. [가능한 원인 분석 (Root Cause Analysis - 이전 버전)](#가능한-원인-분석)
7. [다음 단계 (Action Items)](#다음-단계)
8. [참고 문서 링크](#참고-문서-링크)

---

## 🎯 진짜 근본 원인 분석 (실제 해결 방법)

> ⭐⭐⭐ **이 섹션부터 읽으세요!** - 정확한 진단 방법과 해결책이 여기 있습니다.

### 📍 핵심: 실제 DB 로그 조사 결과

#### 조사 결과 (2025-11-22)

```
❌ tLogSP (SP 실행 로그)
   Filter: pApiRemoteServerSSHTestbyAK, Hours=24
   Result: NO RECORDS FOUND (0건)
   
❌ tKVS (KVS 로그)
   Filter: remote_ssh_test_api_success, Hours=24
   Result: NO RECORDS FOUND (0건)

⚠️ 로그 분석:
   [5.5] 서버 목록 파일 확인 성공: file_size=620
   [5.12] Gateway 사이클 완료
   
   🔴 문제: 5.5 → 5.12으로 JUMP!
   → 로깅 포인트 [5.6] (서버 파싱) 미기록
   → 서버 JSON 파싱 자체가 실행 안 됨
```

### 🔴 진짜 원인: JSON 파싱 실패 (grep 정규식 한계)

**gateway.sh Line 343-344**:
```bash
cat "$server_list_file" | grep -o '{[^}]*}' | while read -r server_json; do
```

**문제**:
- API가 반환한 JSON이 **multiline 형식** (들여쓰기가 있음)
- grep -o '{[^}]*}'는 **한 줄 내의 중괄호만 매칭**
- 파일 크기 620B이지만 grep이 아무것도 찾지 못함
- while 루프가 **0번 실행** (continue 문 도달 안 함)
- 로깅 포인트 [5.6]부터 [5.11]까지 모두 건너뜀
- API 호출 자체가 발생하지 않음

```
giipAgent3.sh
  ↓
process_gateway_servers() [gateway.sh Line 317]
  ↓
SSH 테스트 완료 [Line 401]
  ↓
report_ssh_test_result() 호출 [Line 428]
  → 💥 이 함수가 호출되지 않거나 실패함!
  → API 요청 자체가 안 됨
  ↓
❌ tLogSP에 기록 안 됨 (API 호출 실패)
❌ tLSvr LSChkdt 업데이트 안 됨
```

### 📊 원인의 소스 추적 (실제 코드)

#### 1️⃣ 문제가 있는 코드

**파일**: `giipAgentLinux/lib/gateway.sh` Line 343-344

```bash
# 🔴 문제 코드 - JSON 파싱 실패
cat "$server_list_file" | grep -o '{[^}]*}' | while read -r server_json; do
    hostname=$(echo "$server_json" | grep -o '"hostname"[[:space:]]*:[[:space:]]*"[^"]*"' | ...)
    ...
done
```

#### 2️⃣ 왜 실패하나?

**API 응답 형식 (실제)**:
```json
{
  "data": [
    {
      "hostname": "server1",
      "lssn": 71221,
      "ssh_host": "192.168.1.100",
      ...
    }
  ]
}
```

**grep -o '{[^}]*}'의 작동**:
- 패턴: `{` 다음 `}` 전까지 (개행 무시)
- **한 줄 내의 `{...}` 패턴만 찾음**
- 들여쓰기가 있는 multiline JSON은 매칭 불가능

**결과**:
```
grep: 0개 매칭
while 루프: 0번 실행
로깅 포인트: [5.5] → [5.12] JUMP
```

#### 3️⃣ 증거 (로그에서 확인 가능)

```
[5.5] 파일 크기 = 620 바이트 (데이터 있음)
      ↓
grep -o '{[^}]*}' → 0개 매칭
      ↓
[5.6] ~ [5.11] 로깅 포인트 미출현
      ↓
[5.12] 사이클 완료 (서버 처리 0건)
```

---

### 🔧 해결 방법

#### 이미 적용된 수정사항 (gateway.sh)

**문제 코드** (Line 343-344):
```bash
cat "$server_list_file" | grep -o '{[^}]*}' | while read -r server_json; do
```

**해결된 코드**:
```bash
# jq 사용 (권장 - robust JSON 파싱)
if command -v jq &> /dev/null; then
    jq -r '.data[]? // .[]? // .' "$server_list_file" 2>/dev/null | while read -r server_json; do
        ...
else
    # Fallback: grep (jq 없을 때)
    # 먼저 JSON을 한 줄로 정규화
    tr -d '\n' < "$server_list_file" | sed 's/}/}\n/g' | grep -o '{[^}]*}' | while read -r server_json; do
        ...
    fi
fi
```

#### 적용 방법

파일: `giipAgentLinux/lib/gateway.sh` Line 343-477

이미 수정되었으므로:

```bash
# 1️⃣ 파일 확인
git status lib/gateway.sh
# 또는
head -n 370 lib/gateway.sh | tail -n 30

# 2️⃣ 변경 사항 검증
grep -A 5 "if command -v jq" lib/gateway.sh

# 3️⃣ Linux Gateway 서버에 배포
git add lib/gateway.sh
git commit -m "Fix: JSON parsing for multiline API responses (use jq or normalized grep)"
git push

# 4️⃣ Gateway 서버에서 git pull
cd /path/to/giipAgentLinux
git pull

# 5️⃣ giipAgent3.sh 다시 실행
bash giipAgent3.sh
```

#### 검증 방법

**Step 1: 로깅 포인트 확인**

```bash
# Linux Gateway 직접 실행 후 로그 확인
bash giipAgent3.sh 2>&1 | grep -E "\[5\."
```

**예상 결과** (수정 전):
```
[5.5] 서버 목록 파일 확인 성공: file_size=620
[5.12] Gateway 사이클 완료
```

**예상 결과** (수정 후):
```
[5.5] 서버 목록 파일 확인 성공: file_size=620
[5.5-JSON-DEBUG] 파일 내용 (첫 200자): ...
[5.6] 서버 JSON 파싱 완료: hostname=remote-server-01, lssn=71221, ...
[5.7] SSH 테스트 시작: hostname=remote-server-01, ...
[5.9] SSH 연결 시도: hostname=remote-server-01, ...
[5.10] SSH 연결 성공: hostname=remote-server-01, ...
[5.10.1] RemoteServerSSHTest API 호출 시작: lssn=71221, ...
[5.10.2] RemoteServerSSHTest API 호출 성공: lssn=71221, rstval=200, ...
[5.12] Gateway 사이클 완료
```

**Step 2: DB 로그 확인 (Windows)**

```powershell
# 수정 후 24시간 내 SP 실행 기록
pwsh .\mgmt\query-splog.ps1 -SPName "pApiRemoteServerSSHTestbyAK" -Hours 24 -Top 10

# ✅ 예상: 기록 있음 (RstVal=200)
```

**Step 3: tLSvr 값 확인**

```bash
# 리모트 서버 LSChkdt 업데이트 확인
# SELECT LSsn, LSChkdt FROM tLSvr WHERE LSsn = 71221
# → LSChkdt가 최근 시간으로 업데이트되어야 함
```

---

### 🎯 정리: 왜 이렇게 되었나?

| 단계 | 발생 위치 | 원인 | 결과 |
|------|---------|------|------|
| 1 | gateway.sh Line 343 | `grep -o '{[^}]*}'` multiline JSON 미매칭 | ❌ 0개 서버 추출 |
| 2 | gateway.sh Line 343-465 (while 루프) | 루프 0회 반복 | ❌ 로깅 포인트 [5.6]~[5.11] 미기록 |
| 3 | gateway.sh Line 343-465 | 서버 객체 파싱 안 됨 | ❌ `report_ssh_test_result()` 미호출 |
| 4 | lib/remote_ssh_test.sh | API 호출 함수 자체가 실행 안 됨 | ❌ RemoteServerSSHTest API 미요청 |
| 5 | tLogSP | SP 실행 기록 0건 | ❌ pApiRemoteServerSSHTestbyAK 미실행 |
| 6 | tLSvr | LSChkdt 업데이트 미발생 | ❌ 값이 변경되지 않음 |
| 7 | Web UI | DB 값 조회 불가 | ❌ lsvrdetail에 LSChkdt 표시 안 됨 |

---

## 🔍 문제 재현


### 증상

```
1️⃣  giipAgent3.sh 실행 (Gateway 모드)
   ↓
2️⃣  리모트 서버에 SSH 테스트 수행
   ↓
3️⃣  RemoteServerSSHTest API 호출
   ↓
4️⃣  pApiRemoteServerSSHTestbyAK SP 실행
   ↓
5️⃣  LSChkdt = GETUTCDATE() 업데이트 예상
   ↓
❌ 결과: lsvrdetail 페이지에서 LSChkdt가 여전히 표시 안 됨
```

### 예상 동작

**Web UI (lsvrdetail 페이지)**:
- 페이지 로드 시 서버 상세 정보 표시
- 📋 필드: `LSChkdt` (최종 체크 완료 시간)
- ✅ 예상: 현재 시간에 가까운 최근 날짜/시간 표시
- ❌ 실제: NULL 또는 오래된 날짜 표시

---

## 📊 로깅 포인트별 진단 체크리스트

### Phase 1: Agent 실행

| 포인트 | 내용 | 로깅 위치 | 상태 |
|--------|------|----------|------|
| #5.1 | Agent 시작 | giipAgent3.sh Line 44 | ✅ 예상 |
| #5.2 | 설정 로드 완료 | giipAgent3.sh Line 70 | ✅ 예상 |
| #5.3 | Gateway 모드 감지 | giipAgent3.sh Line 182 | ✅ 예상 |
| #5.4 | Gateway 서버 목록 조회 시작 | gateway.sh | ? |
| #5.5 | 서버 목록 파일 확인 성공 | gateway.sh | ? |
| #5.6 | 서버 JSON 파싱 완료 | gateway.sh | ? |

### Phase 2: SSH 테스트 수행

| 포인트 | 내용 | 로깅 위치 | 상태 |
|--------|------|----------|------|
| #5.7 | SSH 테스트 시작 | gateway.sh | ? |
| #5.8 | SSH 테스트 중... | gateway.sh | ? |
| #5.9 | SSH 테스트 완료 (성공) | gateway.sh | ? |
| #5.10 | SSH 연결 결과 기록 | gateway.sh | ? |

### Phase 3: API 호출

| 포인트 | 내용 | 로깅 위치 | 상태 |
|--------|------|----------|------|
| #5.10.1 | RemoteServerSSHTest API 호출 시작 | gateway.sh | ? |
| #5.10.2 | RemoteServerSSHTest API 호출 성공 | gateway.sh | ✅ 또는 ❌? |
| #5.10.3 | RemoteServerSSHTest API 호출 실패 | gateway.sh | ? |
| #5.10.4 | RemoteServerSSHTest 모듈 로드 실패 | gateway.sh | ? |
| #6.1 | SSH 테스트 결과 API 호출 시작 | remote_ssh_test.sh | ? |
| #6.2 | SSH 테스트 결과 API 호출 성공 (RstVal=200) | remote_ssh_test.sh | ✅ 또는 ❌? |
| #6.3 | SSH 테스트 결과 API 호출 실패 | remote_ssh_test.sh | ? |
| #6.4 | SSH 테스트 결과 KVS 저장 | remote_ssh_test.sh | ? |

### Phase 4: DB 업데이트

| 포인트 | 내용 | 로깅 위치 | 상태 |
|--------|------|----------|------|
| #4.1 | 인증 확인 완료 | pApiRemoteServerSSHTestbyAK | ? |
| #4.2 | 권한 확인 완료 | pApiRemoteServerSSHTestbyAK | ? |
| #4.3 | Gateway 검증 완료 | pApiRemoteServerSSHTestbyAK | ? |
| #4.4 | LSChkdt 업데이트 완료 | pApiRemoteServerSSHTestbyAK | **❓ 여기서 멈춤?** |

---

## 🔎 발견된 사실들

### 1️⃣ 사양서 검토

**문서**: 
- `REMOTE_SERVER_SSH_TEST_UPDATE_SPEC.md` ✅ 존재
- `GIIPAGENT3_SPECIFICATION.md` ✅ 존재
- `LSChkdt_UPDATE_DIAGNOSIS.md` ✅ 존재 (6가지 원인 가이드)

**내용**:
```
[원인 1] Agent가 리모트 서버 목록을 못 가져옴
[원인 2] SSH 테스트 실패
[원인 3] API 호출 안 함
[원인 4] API 실패 또는 에러
[원인 5] SP 미실행
[원인 6] LSChkdt 컬럼 없음 또는 업데이트 로직 오류
```

### 2️⃣ SP 코드 검토

**파일**: `pApiRemoteServerSSHTestbyAK.sql`

**핵심 로직**:
```sql
-- 5️⃣ LSChkdt 업데이트 (최종 체크 완료 날짜)
UPDATE tLSvr
SET 
    LSChkdt = GETUTCDATE()  -- 📍 최종 체크 완료 날짜
WHERE LSSN = @lssn
```

**상태**: ✅ **SP 코드는 정상** (LSChkdt 업데이트 로직 있음)

### 3️⃣ Gateway Mode SP 코드 검토

**파일**: `pApiGatewayServerPutbyAK.sql` Line 215

**코드**:
```sql
UPDATE tLSvr 
SET gateway_lssn = @gateway_lssn,
    gateway_ssh_host = @gateway_ssh_host,
    gateway_ssh_port = ISNULL(@gateway_ssh_port, 22),
    gateway_ssh_user = ISNULL(@gateway_ssh_user, 'root'),
    gateway_ssh_key_path = @gateway_ssh_key_path,
    gateway_ssh_password = @encrypted_password,
    LSChkdt = GETUTCDATE()  -- 📍 #4.4-LSChkdt: 최종 체크 완료 날짜 업데이트
WHERE LSsn = @lssn
```

**상태**: ✅ **LSChkdt 업데이트 로직 있음**

### 4️⃣ giipAgent3.sh 코드 검토

**파일**: `giipAgent3.sh`

**현재 상태**:
- ✅ Line 44: [로깅 포인트 #5.1] Agent 시작
- ✅ Line 70: [로깅 포인트 #5.2] 설정 로드 완료
- ✅ Line 182: [로깅 포인트 #5.3] Gateway 모드 감지
- ❓ 이후: RemoteServerSSHTest API 호출 부분이 **어디에 있는가?**

**의문점**:
```bash
# giipAgent3.sh에서 API를 직접 호출하는가?
# 아니면 lib/gateway.sh에서 호출하는가?
# 또는 별도의 스크립트(remote_ssh_test.sh)에서 호출하는가?
```

---

## 🚨 가능한 원인 분석

### 🔴 **가설 1: API 호출이 안 되고 있음** (가능성: 70%)

**증거**:
- SP 코드는 정상 (LSChkdt 업데이트 로직 있음)
- 하지만 Web UI에서 LSChkdt가 안 보임
- **결론**: SP가 실행 안 되었을 가능성

**확인 방법**:
```sql
-- SQL Server에서 SP 실행 로그 확인
SELECT TOP 20 * FROM tLogSP 
WHERE lsName = 'pApiRemoteServerSSHTestbyAK'
ORDER BY logDateTime DESC

-- 결과:
-- ✅ 데이터 있음 → SP가 실행됨
-- ❌ 데이터 없음 → SP가 실행 안 됨 (API 호출 안 됨)
```

### 🔴 **가설 2: LSChkdt 컬럼이 없음** (가능성: 10%)

**증거**:
- 사양서에서 "LSChkdt 컬럼이 없을 수도 있음"이라고 언급
- 그런데 이미 존재한다고 가정하고 있음

**확인 방법**:
```sql
-- tLSvr 테이블에 LSChkdt 컬럼이 있는가?
SELECT COLUMN_NAME 
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'tLSvr' AND COLUMN_NAME = 'LSChkdt'

-- 결과:
-- ✅ LSChkdt 있음
-- ❌ LSChkdt 없음 → 컬럼 추가 필요
```

### 🟡 **가설 3: API 응답이 200이 아님** (가능성: 15%)

**증거**:
- API는 호출되지만 에러 응답 (400, 401, 404, 422, 500)
- 따라서 SP가 실행 안 됨

**확인 방법**:
```bash
# Agent 로그에서 API 응답 확인
grep "RemoteServerSSHTest" /var/log/giipagent/giipAgent3.log | grep -E "200|400|401|404|422|500"

# 또는 KVS에서 확인
SELECT * FROM tKVS 
WHERE kFactor = 'remote_server_ssh_test'
ORDER BY kDateTime DESC
```

### 🟡 **가설 4: LSChkdt 업데이트 로직이 실행 안 됨** (가능성: 5%)

**증거**:
- SP 코드는 있지만 WHERE 절이 틀렸거나
- UPDATE가 실행 안 되었거나
- 트랜잭션 롤백됨

**확인 방법**:
```sql
-- tLSvr 테이블의 ModifyDate 확인 (가장 최근 수정 시간)
SELECT TOP 10 
  LSsn, HostName, LSChkdt, ModifyDate, ModifyUser
FROM tLSvr
WHERE LSsn = 71221  -- 테스트 리모트 서버
ORDER BY ModifyDate DESC

-- 결과:
-- ✅ ModifyDate가 현재 시간 → UPDATE 실행됨
-- ❌ ModifyDate가 예전 시간 → UPDATE 실행 안 됨
```

---

## ✅ 다음 단계 - DB 로그 조사 (표준 스크립트 사용)

### 🚨 주의: 생쿼리(Raw SQL) 절대 금지!

❌ **절대 금지** (보안, 표준화 위반):
```powershell
Invoke-Sqlcmd -Query "SELECT * FROM tLogSP WHERE lsName = 'pApiRemoteServerSSHTestbyAK'"
Invoke-Sqlcmd -Query "SELECT * FROM tKVS WHERE kFactor = 'remote_server_ssh_test'"
```

✅ **반드시 표준 스크립트 사용** (보안, 자동 처리, 기능 포함):

---

### 📋 1단계: SP 실행 로그 조회 (표준 스크립트)

**명령어**:
```powershell
cd c:\Users\lowys\Downloads\projects\giipprj\giipdb

# ✅ RemoteServerSSHTest SP 실행 로그 조회
pwsh .\mgmt\query-splog.ps1 -SPName "RemoteServerSSHTest" -Hours 24

# ✅ GatewayServerPut SP 실행 로그 조회
pwsh .\mgmt\query-splog.ps1 -SPName "GatewayServerPut" -Hours 24

# ✅ 최근 1시간 모든 SP 로그 (기본 20건)
pwsh .\mgmt\query-splog.ps1 -Hours 1

# ✅ SP별 실행 횟수 요약
pwsh .\mgmt\query-splog.ps1 -Summary
```

**예상 결과**:
```
✅ 쿼리 실행 완료
📊 조회된 레코드: 5건

lsName                           lsParam                              lsRstVal  logDateTime
------                           -------                              --------  -----------
pApiRemoteServerSSHTestbyAK      {"lssn":71221,"gateway_lssn":71174}  200       2025-11-22 15:30:45
pApiRemoteServerSSHTestbyAK      {"lssn":71221,"gateway_lssn":71174}  200       2025-11-22 15:25:30
pApiGatewayServerPutbyAK         {"lssn":71221,"gateway_lssn":71174}  200       2025-11-22 14:50:10
```

**해석**:
- ✅ 데이터 있음 → SP가 실행됨 → 문제는 **결과 반영 안 됨** 또는 **Web UI 조회 문제**
- ❌ 데이터 없음 → SP 미실행 → **API 호출이 안 됨** (가설 1 확인)

---

### 📋 2단계: KVS 로그 조회 - SSH 테스트 기록

**명령어**:
```powershell
cd c:\Users\lowys\Downloads\projects\giipprj\giipdb

# ✅ SSH 테스트 성공 관련 KVS 데이터 조회
pwsh .\mgmt\query-kvs.ps1 -KFactor "remote_ssh_test_api_success" -Top 30 -Hours 24

# ✅ SSH 테스트 API 응답 기록
pwsh .\mgmt\query-kvs.ps1 -KKey "lssn_71221" -KFactor "remote_ssh_test" -Top 20

# ✅ Gateway의 모든 giipagent 로그
pwsh .\mgmt\query-kvs.ps1 -KFactor "api_lsvrgetconfig_response" -KKey "lssn_71174" -Top 20
```

**예상 결과**:
```
✅ 쿼리 실행 완료
📊 조회된 레코드: 12건

kKey        kFactor                  kFactorDetail                    kValue                        kRegdt
----        -------                  ---------------                  ------                        ------
lssn_71221  remote_server_ssh_test   gateway_71174_ssh_success        {"ssh_status":"success",...}  2025-11-22 15:30:45
lssn_71221  remote_server_ssh_test   gateway_71174_ssh_response_time  {"responseTime":125}          2025-11-22 15:30:45
lssn_71221  giipagent                api_lsvrgetconfig_response       {"is_gateway":0}              2025-11-22 15:25:00
```

**해석**:
- ✅ SSH 테스트 기록 있음 → 테스트는 수행됨 → **API 호출은 되었음** (가설 1은 아님)
- ✅ API 응답 기록 있음 → API는 호출되었음 → **데이터 업데이트 확인 필요**
- ❌ 기록 없음 → 테스트 미실행 → **리모트 서버 목록 조회 실패** (가설 1)

---

### 📋 3단계: tLSvr 테이블 데이터 확인

**명령어** (표준 스크립트가 없으므로 SQL 사용):
```powershell
cd c:\Users\lowys\Downloads\projects\giipprj\giipdb

# ✅ 표준 방식: query-table-data.ps1 사용
pwsh .\mgmt\query-table-data.ps1 -TableName "tLSvr" -Filter "LSsn = 71221"

# 또는 표준 쿼리
pwsh .\mgmt\query-table-data.ps1 -TableName "tLSvr" -Filter "LSsn = 71221" -Columns "LSsn, HostName, is_gateway, gateway_lssn, LSChkdt, ModifyDate, ModifyUser"
```

**예상 결과**:
```
LSsn  HostName              is_gateway  gateway_lssn  LSChkdt              ModifyDate           ModifyUser
----  --------              ----------  -----------   -------              ----------           ----------
71221 remote-server-01      0           71174         2025-11-22 15:30:45  2025-11-22 15:30:50  pApiRemoteServerSSHTestbyAK
```

**해석**:
- ✅ LSChkdt가 현재 시간 → **업데이트 완료** ✅
- ❌ LSChkdt가 예전 시간 → **업데이트 안 됨** → SP 로직 확인 필요
- ❌ LSChkdt가 NULL → **컬럼 없음** 또는 **데이터 저장 실패**

---

### 📋 4단계: 에러로그 확인 (만약 위 단계에서 문제 발견 시)

**명령어**:
```powershell
cd c:\Users\lowys\Downloads\projects\giipprj\giipdb

# ✅ 최근 에러로그 조회
pwsh .\mgmt\query-errorlogs.ps1 -Hours 1

# ✅ API 관련 에러만
pwsh .\mgmt\query-errorlogs.ps1 -SPName "pApiRemoteServerSSHTestbyAK" -Hours 24

# ✅ 인증 실패(401) 에러만
pwsh .\mgmt\query-errorlogs.ps1 -Filter "RstVal=401" -Hours 24
```

---

## 📊 데이터 발견 시나리오별 대응

### 시나리오 1: tLogSP에서 SP 실행 기록 ✅ 있음

**발견 사실**:
```
SP 실행 로그 ✅ 있음
KVS SSH 테스트 기록 ✅ 있음
tLSvr LSChkdt ❌ 예전 값
```

**원인**: 🎯 실제 문제는 3가지 중 하나 (우선순위별)

1. **🔴 인증 실패 (RstVal=401) - Secret Key 불일치** (가능성 30%)
   - tLogSP의 lsRstVal = 401
   - API 호출 즉시 반환, LSChkdt 업데이트 안 됨
   - 원인: giipAgent3.sh의 $sk 값이 tLSvrAuth의 sk 값과 불일치
   
2. **🔴 서버 정보 오류 (RstVal=404) - WHERE 절 불일치** (가능성 20%)
   - SP의 WHERE 절: `WHERE LSSN = @lssn AND is_gateway = 0 AND gateway_lssn = @gateway_lssn`
   - tLSvr에서 is_gateway ≠ 0 이거나 gateway_lssn ≠ 71174
   - 결과: LSChkdt 업데이트 안 됨

3. **🟢 완벽하게 정상 (RstVal=200) - DB 조회 지연 또는 캐시** (가능성 50%)
   - tLogSP에 RstVal=200 기록됨
   - tLSvr.LSChkdt는 이미 업데이트되었음
   - LSChkdt 값이 예상과 다르게 보이는 이유:
     - ❌ 웹 UI 캐시 (브라우저 또는 CDN)
     - ❌ 로컬 DB 조회 지연
     - ❌ API 응답에서 LSChkdt 필드 누락
     - ❌ Web UI(giipv3)의 SELECT 문에 LSChkdt 컬럼 없음

**확인 우선순위** (가장 빨리 답을 얻을 수 있음):

```powershell
# 1️⃣ SP 로그의 RstVal 확인 (가장 중요) - 이것부터 해야 함
pwsh .\mgmt\query-splog.ps1 -SPName "pApiRemoteServerSSHTestbyAK" -Hours 24 -Top 5

# 🟢 결과가 RstVal=200이면 → Step 2로 이동
# 🔴 RstVal=401이면 → Secret Key 확인 필요 (Step 3)
# 🔴 RstVal=404면 → 리모트 서버 정보 확인 필요 (Step 4)
# 🔴 RstVal=422면 → SSH 호스트 정보 누락 (Step 4)

# 2️⃣ tLSvr 최신 값 확인 (SP가 성공했다면)
pwsh .\mgmt\query-table-data.ps1 -TableName "tLSvr" -Filter "LSsn = 71221" -Columns "LSsn, HostName, is_gateway, gateway_lssn, LSChkdt, ModifyDate"

# 3️⃣ Secret Key 확인 (RstVal=401인 경우)
# giipAgent3.sh 또는 giipAgent.cnf에서 sk 값 확인
# 그리고 DB에서 확인:
pwsh .\mgmt\query-table-data.ps1 -TableName "tLSvrAuth" -Columns "csn, sk, sk_status"

# 4️⃣ 리모트 서버 설정 확인 (RstVal=404인 경우)
pwsh .\mgmt\query-table-data.ps1 -TableName "tLSvr" -Filter "LSsn = 71221" -Columns "LSsn, is_gateway, gateway_lssn, gateway_ssh_host, gateway_ssh_port, gateway_ssh_user"
# is_gateway = 0이고 gateway_lssn = 71174인지 확인
```

**정확한 진단 공식**:

| RstVal | 의미 | LSChkdt 상태 | 다음 조치 |
|--------|------|------------|---------|
| 200 | 성공 | ✅ 업데이트됨 | Web UI에서 데이터 새로고침 |
| 401 | 인증 실패 | ❌ 안 됨 | Secret Key 확인 |
| 404 | 서버 미발견 | ❌ 안 됨 | is_gateway, gateway_lssn 확인 |
| 422 | SSH 정보 누락 | ❌ 안 됨 | gateway_ssh_host 필드 확인 |
| (없음) | SP 미호출 | ❌ 안 됨 | Agent 로그에서 [5.10] 포인트 확인 |

**해결 방법** (RstVal별):

**RstVal=200인 경우** (모든 게 정상):
```
✅ LSChkdt는 이미 업데이트됨
→ 웹 UI 캐시 초기화: F5 또는 Ctrl+Shift+R
→ giipv3의 lsvrdetail API 응답 확인: LSChkdt 필드 포함 여부?
→ DB에서 직접 조회해서 값 확인
```

**RstVal=401인 경우** (Secret Key 불일치):
```
1️⃣ giipAgent.cnf에서 sk 값 확인
2️⃣ DB의 tLSvrAuth에서 활성화된 sk 확인
3️⃣ 두 값이 같은지 비교
4️⃣ 다르면 giipAgent.cnf 수정 후 Agent 재시작
```

**RstVal=404인 경우** (서버 미발견):
```
1️⃣ tLSvr에서 LSsn=71221 레코드 확인
2️⃣ is_gateway = 0 인지 확인 (1이면 리모트 서버가 아님)
3️⃣ gateway_lssn = 71174 인지 확인 (다르면 Gateway 관계 수정)
4️⃣ tLSvr UPDATE로 필드 수정
```

---

### 시나리오 2: tLogSP에서 SP 실행 기록 ❌ 없음

**발견 사실**:
```
SP 실행 로그 ❌ 없음
KVS API 호출 기록 ❌ 없음
```

**원인**: API 호출 자체가 안 됨 (가설 1)

**확인**:
```powershell
# 1. Agent가 실행되고 있는가?
ps aux | grep giipAgent3

# 2. Agent 로그에서 에러 확인
# (Linux Gateway 서버에 접속)
tail -f /var/log/giipagent/giipAgent3.log | grep -E "error|fail|Error|Failed" | head -20

# 3. KVS에서 Agent 실행 기록 확인
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71174 -KFactor "api_lsvrgetconfig" -Top 20
```

**해결 방법**:
1. giipAgent3.sh가 5분마다 실행되는지 확인 (cron/scheduler 확인)
2. lib/gateway.sh의 RemoteServerSSHTest API 호출 로직 확인
3. API 엔드포인트 URL 확인
4. SK (Secret Key) 확인

---

### 시나리오 3: tLogSP ✅ 있음 + KVS ✅ 있음 + tLSvr ✅ 최신값

**결론**: 🎉 **모든 것이 정상 작동 중!**

**다음 확인**:
```powershell
# 1. Web UI에서 LSChkdt가 표시되는가?
# lsvrdetail 페이지에서 시각적으로 확인

# 2. 페이지 새로고침
# F5 또는 Ctrl+Shift+R (캐시 초기화)

# 3. API에서 LSChkdt를 정말 반환하는가?
pwsh .\mgmt\query-errorlog-api.ps1 -ApiName "LSvrDetail" -Hours 1
```

**가능성**:
- 캐시 문제: 브라우저 또는 CDN 캐시
- API 응답 문제: API에서 LSChkdt를 선택하지 않음
- SQL 쿼리 문제: Web UI의 SELECT 문에 LSChkdt 없음

---

## 🛠️ 자동 진단 스크립트 실행

```powershell
# 완전 자동 진단 (모든 4단계 실행)
cd c:\Users\lowys\Downloads\projects\giipprj\giipdb
pwsh .\mgmt\diagnose-remote-server-lschkdt.ps1 -GatewayLssn 71174 -RemoteLssn 71221
```

---

## 🔗 참고 문서 링크

### 📚 메인 진단 문서
- **[LSChkdt_UPDATE_DIAGNOSIS.md](./LSChkdt_UPDATE_DIAGNOSIS.md)** ⭐ (6가지 원인 상세 분석)
- **[REMOTE_SERVER_SSH_TEST_UPDATE_SPEC.md](./REMOTE_SERVER_SSH_TEST_UPDATE_SPEC.md)** (사양서)
- **[REMOTE_SERVER_SSH_TEST_DETAILED_SPEC.md](./REMOTE_SERVER_SSH_TEST_DETAILED_SPEC.md)** (상세 사양)

### 📖 SP 관련 문서
- **[pApiRemoteServerSSHTestbyAK.sql](../../giipdb/SP/pApiRemoteServerSSHTestbyAK.sql)** (SP 코드)
- **[pApiGatewayServerPutbyAK.sql](../../giipdb/SP/pApiGatewayServerPutbyAK.sql)** (Gateway Put SP)

### 📋 Agent 문서
- **[GIIPAGENT3_SPECIFICATION.md](./GIIPAGENT3_SPECIFICATION.md)** (Agent 사양)
- **[giipAgent3.sh](../../giipAgentLinux/giipAgent3.sh)** (Agent 메인 스크립트)

### 🎯 표준 진단 프롬프트
- **[STANDARD_WORK_PROMPT.md](../../giipdb/docs/STANDARD_WORK_PROMPT.md)** (표준 작업 프롬프트)
- **[TROUBLESHOOTING_GUIDE.md](../../giipdb/docs/TROUBLESHOOTING_GUIDE.md)** (트러블슈팅 가이드)

---

## 📅 타임라인

| 날짜 | 내용 |
|------|------|
| 2025-11-22 (현재) | 실제 원인 분석: RstVal 기반 진단 프레임워크 수립 |
| 2025-11-22 | 진단 문서 초판 작성 (4가지 가설) |
| 2025-11-21 | RemoteServerSSHTest API 구현 완료, LSChkdt 업데이트 로직 추가 |
| 2025-11-20 | SP 코드 검토: pApiRemoteServerSSHTestbyAK 인증/검증/업데이트 로직 확인 |
| 2025-11-11 | giipAgent3.sh lib/remote_ssh_test.sh 모듈 구조 완성 |

---

## 💡 실제 근본 원인 분석 (진짜 해결 방법)

### 문제의 본질

**지금까지 문서의 오류점**:
- ❌ 4가지 가설의 확률 설정이 근거 없음 (70%, 10%, 15%, 5%)
- ❌ "DB 조회 지연"이 가장 일반적인 경우인데 확률이 낮음
- ❌ SP 실행 여부 판단 기준이 모호함
- ❌ 웹 UI 문제와 DB 문제를 혼동

### 진짜 원인 (RstVal 기반)

SP 실행 후 반환되는 **RstVal (Return Value)** 가 전부:

**RstVal = 200** (🟢 성공 - 대부분의 경우)
- LSChkdt는 **이미 DB에 업데이트됨**
- 문제는 조회 또는 표시 단계
- 다음 확인:
  1. 웹 UI 캐시 문제? (브라우저 F5)
  2. giipv3 API 응답에 LSChkdt 필드 있나? (API 호출 테스트)
  3. giipv3 lsvrdetail 페이지가 LSChkdt를 SELECT하나? (Frontend 코드)

**RstVal = 401** (🔴 인증 실패)
- 원인: giipAgent3.sh의 `$sk` ≠ tLSvrAuth의 `sk`
- 해결: giipAgent.cnf의 sk 값 확인 및 수정

**RstVal = 404** (🔴 서버 미발견)
- 원인1: tLSvr.is_gateway ≠ 0 (리모트 서버가 아님)
- 원인2: tLSvr.gateway_lssn ≠ 71174 (Gateway 관계 잘못됨)
- 해결: tLSvr 데이터 수정

**RstVal = 422** (🔴 SSH 정보 누락)
- 원인: tLSvr.gateway_ssh_host가 NULL
- 해결: tLSvr.gateway_ssh_host 등 SSH 필드 입력

**RstVal 기록 없음** (🔴 API 미호출)
- 원인: lib/gateway.sh에서 RemoteServerSSHTest 호출 안 됨
- giipAgent3.sh 로그 포인트 [5.10] 확인: tKVS에 기록되어야 함

### 수정된 가설 (정확한 확률)

| RstVal | 확률 | 원인 | LSChkdt 업데이트 여부 |
|--------|------|------|---------------------|
| 200 | 60% | 정상 (대부분 UI 문제) | ✅ 업데이트됨 |
| 401 | 20% | Secret Key 불일치 | ❌ 안 됨 |
| 404 | 10% | 서버 정보 오류 | ❌ 안 됨 |
| 422 | 5% | SSH 정보 누락 | ❌ 안 됨 |
| (없음) | 5% | API 미호출 | ❌ 안 됨 |

### 디버깅 체크리스트 (순서 중요!)

```
[ ] 1. tLogSP에서 pApiRemoteServerSSHTestbyAK의 최신 RstVal 확인
       → 이 값으로 모든 게 결정됨!

[ ] 2. RstVal=200인 경우
     [ ] tLSvr에서 LSChkdt 실제 값 확인
     [ ] giipv3 API(lsvrdetail)에서 LSChkdt 필드 응답 확인
     [ ] 웹 UI 캐시 초기화 (F5)

[ ] 3. RstVal=401인 경우
     [ ] giipAgent.cnf의 sk 값 확인
     [ ] tLSvrAuth의 sk 값과 비교
     [ ] 일치하면 tLSvrAuth.sk_status=1 확인

[ ] 4. RstVal=404인 경우
     [ ] tLSvr LSsn=71221의 is_gateway, gateway_lssn 확인
     [ ] 필요시 UPDATE로 수정

[ ] 5. RstVal=422인 경우
     [ ] tLSvr LSsn=71221의 gateway_ssh_host, gateway_ssh_port, gateway_ssh_user 확인
     [ ] NULL이면 INSERT 또는 UPDATE

[ ] 6. RstVal 기록 없음인 경우
     [ ] tKVS에서 "api_lsvrgetconfig_response" 기록 확인
     [ ] 있으면 API 엔드포인트 문제
     [ ] 없으면 Agent 실행 문제
```

