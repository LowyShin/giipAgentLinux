# 🔍 Gateway 리모트 서버 처리 중단 - 빠른 진단 (3~5분)

> **📌 이 가이드:**
> - ⏱️ **3~5분만에** 원인을 찾을 수 있는 빠른 진단만 포함
> - 📖 상세 내용은 [GATEWAY_DETAILED_DIAGNOSIS.md](./GATEWAY_DETAILED_DIAGNOSIS.md) 참조
> - 🎯 대상: DevOps, Gateway 관리자
> - 🔗 관련 파일: `giipAgent3.sh`, `lib/gateway.sh`

---

## 🟢 현재 상황 (2025-11-27 20:50 기준)

**Gateway 정상 작동 중 ✅**

```
호스트: infraops01.istyle.local (LSSN: 71240)
모드: Gateway (version 3.00)
상태: ✅ 정상 작동
DB 체크: ✅ MySQL p-cnsldb02m, p-cnsldb03m (600-650ms)
KVS 레코드: 46개 (지난 60분)
마지막 이벤트: 정상 종료 (2025-11-27 20:50:18)
```

---

## ⚡ 30초 진단 (가장 빠름!)

### 🔄 Main Execution Flow

```
┌─────────────────────────────────────────────────────────────┐
│ giipAgent3.sh 시작                                           │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
         ┌──────────────────┐
         │ [5.1] Agent 시작  │
         │ - 버전: 3.00     │
         │ - 라이브러리 로드  │
         └────────┬─────────┘
                  │
                  ▼
         ┌──────────────────────┐
         │ [5.2] 설정 로드       │
         │ - giipAgent.cnf 읽기 │
         │ - 환경변수 검증      │
         └────────┬─────────────┘
                  │
                  ▼
    ┌────────────────────────────┐
    │ [5.3] is_gateway 값 확인   │
    │ (DB API: LSvrGetConfig)   │
    └────┬──────────────────┬────┘
         │                  │
    is_gateway=0        is_gateway=1
    (또는 false)        (또는 true)
         │                  │
         ▼                  ▼
    ┌──────────────┐  ┌──────────────────┐
    │ NORMAL MODE  │  │ GATEWAY MODE 진입 │
    │              │  │ [5.3.G] 초기화   │
    │ Queue 기반   │  │ - 리모트 서버    │
    │ 일반 처리    │  │   목록 조회      │
    │ (normal.sh) │  └────────┬─────────┘
    └──────────────┘           │
                              ▼
                   ┌─────────────────────┐
                   │ [5.4] 서버 목록 조회 │
                   │ API:                │
                   │ GatewayRemoteServer│
                   │ ListForAgent       │
                   └────────┬────────────┘
                            │
                    ┌───────┴──────┐
                    │              │
            성공 (count>0)   실패 or 빈 배열
                    │              │
                    ▼              ▼
         ┌──────────────────┐  ┌─────────────┐
         │ [5.5] 루프 시작   │  │ [5.5.E] 에러│
         │ - 각 서버별 처리  │  │ - 대기 후   │
         └────────┬─────────┘  │   재시도    │
                  │             └─────────────┘
                  ▼
    ┌────────────────────────────┐
    │ [5.6] 서버별 처리 시작      │
    │ - lssn별 루프              │
    └────────┬───────────────────┘
             │
             ▼
    ┌────────────────────────────┐
    │ [5.7] SSH 연결 테스트      │
    │ - sshpass 검증            │
    │ - 인증정보 확인            │
    └────┬──────────────────┬────┘
         │                  │
      성공                 실패
         │                  │
         ▼                  ▼
    ┌──────────────┐  ┌─────────────┐
    │ [5.8] 원격   │  │ [5.8.E]    │
    │ 명령 실행    │  │ SSH 에러    │
    │ - 데이터 수집│  │ 기록 및     │
    │ - KVS 저장   │  │ 다음 서버로 │
    └────┬─────────┘  └─────────────┘
         │
         ▼
    ┌──────────────┐
    │ [5.9] Auto-  │
    │ Discover 실행│
    │ - 시스템정보 │
    │   수집       │
    └────┬─────────┘
         │
         ▼
    ┌────────────────┐
    │ [5.10] 관리DB  │
    │ 체크 (Gateway) │
    │ - MySQL/MSSQL │
    │ - 성능정보     │
    └────┬───────────┘
         │
         ▼
    ┌────────────────┐
    │ 모든 서버 처리 │
    │ 완료?          │
    └────┬────────┬──┘
         │        │
         예      아니오
         │        │
         ▼        └───────┐
    ┌──────────┐          │
    │ [6.0]   │          ▼
    │ 정상종료 │◄─────────┘
    │ normal_ │
    │ exit    │
    └──────────┘
```

### 📋 상세 실행 단계별 KVS Factor 매핑

| 단계 | 포인트 | 설명 | KVS Factor | 정상 신호 (JSON in kValue) | 에러 신호 (JSON in kValue) |
|------|--------|------|-----------|----------|----------|
| 1 | [5.1] | Agent 시작 | `giipagent` | `{"event_type":"startup","mode":"gateway","is_gateway":1}` | ❌ 없음 → 실행 안됨 |
| 2 | [5.2] | 설정 로드 | ⚠️ KVS 미기록* | - | - |
| 3 | [5.3] | is_gateway 판단 | `api_lsvrgetconfig_response` | `{"is_gateway":1}` | `{"is_gateway":0,"error":"API failed"}` |
| 3.G | [5.3.G] | Gateway 모드 초기화 | `giipagent` | `{"event_type":"gateway_init","server_count":N}` | ❌ 없음 → Normal 모드 진입 |
| 4.S | [5.4-START] | 리모트 서버 조회 시작 | `gateway_step_5.4_start` | `{"action":"list_servers_start","timestamp":"..."}` | - |
| 4 | [5.4] | 리모트 서버 조회 성공 | `gateway_step_5.4_success` | `{"action":"list_servers_success","server_count":N}` | `gateway_step_5.4_failed`: `{"reason":"empty_response"}` 또는 `{"reason":"api_error_response"}` |
| 5.E | [5.5-EXTRACT] | 서버 정보 추출 | `gateway_server_extract` | `{"action":"server_params_extracted","server_params":{...}}` | `gateway_step_5.5_failed`: `{"action":"extract_params_empty"}` |
| 5.V | [5.5-VALIDATE] | 서버 정보 검증 | - | ✅ 통과 시 다음 단계 | `gateway_step_5.5_failed`: `{"action":"validation_failed","hostname":"..."}` |
| 6 | [5.6] | 서버 파싱 완료 | `gateway_step_5.6_parsed` | `{"action":"server_parsed","hostname":"...","ssh_host":"...","ssh_port":...}` | - |
| 7 | [5.8] | 큐 조회 | `gateway_step_5.8_success` | `{"action":"queue_fetch_success","queue_file_size":...}` | `gateway_step_5.8_failed`: `{"error":"HTTP Error..."}` |
| 8 | [5.9-START] | SSH 시도 시작 | `gateway_step_5.9_ssh_start` | `{"action":"ssh_attempt_start","ssh_host":"...","ssh_port":...}` | - |
| 8 | [5.9-SUCCESS] | SSH 성공 | `gateway_step_5.9_ssh_success` | `{"action":"ssh_success","exit_code":0}` | `gateway_step_5.9_ssh_failed`: `{"action":"ssh_failed","exit_code":N,"error":"..."}` |
| 9 | [5.10] | 원격 명령 실행 | `gateway_step_5.10_complete` | `{"action":"command_executed","response_time_ms":...,"output":"..."}` | `gateway_step_5.10_failed`: `{"action":"command_failed","error":"..."}` |
| 10 | [6.0] | 정상 종료 | `giipagent` | `{"event_type":"shutdown","status":"normal_exit","servers_processed":N}` | `{"event_type":"shutdown","status":"error","reason":"..."}` |

**주요 변경사항:**
- ⚠️ [5.2] 설정 로드는 KVS에 기록되지 않음 (로그 파일에만 기록)
- ⚠️ [5.7] SSH 테스트는 [5.9]로 합쳐짐 (실제 SSH 실행 결과로 기록)
- 🆕 각 **성공** 및 **실패** 시점에 별도의 Factor로 즉시 기록
- 🆕 JSON in kValue는 **raw 데이터** (string escaping 없음)
- 🆕 모든 Factor에 `timestamp` 포함 (디버깅용)
- 🆕 문제 발생 시 상세 데이터 (에러 메시지, 상태값 등) 함께 기록

#### 📌 KVS 저장 규칙 (중요!)

**kValue JSON 구조 (Raw JSON 형식):**
```json
{
  "action": "단계별_행동",
  "timestamp": "2025-11-27 09:25:14",
  "status": "success|failed",
  "hostname": "remote-server-01",
  "server_lssn": 71241,
  "parent_lssn": 71240,
  "details": {
    "error": "에러 메시지",
    "response_time_ms": 1234,
    "exit_code": 0
  }
}
```

**각 스텝별 로깅 시점:**

| 스텝 | 시작 시점 | 완료 시점 | Factor | 
|------|----------|----------|---------|
| 5.4 (서버 목록 조회) | 없음 | `gateway_step_5.4_success` 또는 `gateway_step_5.4_failed` | 단일 Record |
| 5.5 (서버 정보 추출) | 없음 | `gateway_server_extract` + 검증 결과 | 단일 Record |
| 5.6 (서버 파싱) | 없음 | `gateway_step_5.6_parsed` | 단일 Record |
| 5.8 (큐 조회) | 없음 | `gateway_step_5.8_success` 또는 `gateway_step_5.8_failed` | 단일 Record |
| 5.9 (SSH 실행) | `gateway_step_5.9_ssh_start` | `gateway_step_5.9_ssh_success` 또는 `gateway_step_5.9_ssh_failed` | 2개 Records |
| 5.10 (원격 명령) | 없음 | `gateway_step_5.10_complete` 또는 `gateway_step_5.10_failed` | 단일 Record |

**문제 해결 시 확인 포인트:**

1. **[5.4] 실패 시:**
   - `gateway_step_5.4_failed` 확인 → `reason` 필드 확인
   - `kValue`에 응답 데이터 상세 기록됨

2. **[5.5] 실패 시:**
   - `gateway_step_5.5_failed` 확인 → `action` 필드 확인
   - `server_params` 전체 기록됨 (어디서 실패했는지 확인 가능)

3. **[5.9] SSH 실패 시:**
   - `gateway_step_5.9_ssh_failed` 확인 → `error` 필드 확인
   - SSH 파라미터 모두 기록 (ssh_host, ssh_port, ssh_user 등)

4. **[5.10] 명령 실패 시:**
   - `gateway_step_5.10_failed` 확인 → `error` 필드 확인
   - 실제 원격 명령 에러 메시지 포함

---

## 📋 테스트 및 진단 스크립트 완벽 가이드

> **정리 완료:** 모든 테스트 스크립트 사용법을 이 섹션에 통합했습니다.
> - 중복 제거 ✅
> - 사용 시나리오별 분류 ✅
> - 실제 커맨드 복사-붙여넣기 가능 ✅

---
```powershell
# Windows PowerShell에서 실행 (모든 것을 이것 하나로 시작!)
cd C:\path\to\giipdb
pwsh .\mgmt\check-latest.ps1
```

**출력 해석 (3가지만):**
- ✅ `[5.x]` 포인트들이 순서대로 나타나는가? → **정상**
- ❌ `[5.4]` 이후 아무것도 없는가? → **서버 목록 조회 실패** (원인: 데이터 없음 또는 API 에러)
- ❌ `[5.9]` 실패 나타나는가? → **SSH 연결 실패** (원인: 인증정보 또는 네트워크 문제)

---

## 🎯 4가지 진단 명령어 (상황별)

**목적:** giipAgent3.sh 실행 시 KVS에 저장된 로그를 빠르게 확인  
**위치:** `giipdb/mgmt/check-latest.ps1`  
**용도:** Gateway 및 일반 Agent 디버깅

**1️⃣ 최근 5분 전체 흐름 (가장 많이 사용)**
```powershell
pwsh .\mgmt\check-latest.ps1
```

**2️⃣ 다른 서버 진단**
```powershell
pwsh .\mgmt\check-latest.ps1 -Lssn 71241 -Minutes 30
```

**3️⃣ SSH 문제만 보기**
```powershell
pwsh .\mgmt\check-latest.ps1 -PointFilter "5\.[79]" -NoPointFilter:$false
```

**4️⃣ 정상 종료 확인**
```powershell
pwsh .\mgmt\check-latest.ps1 -PointFilter "6\.0" -NoPointFilter:$false
```

> **더 많은 옵션:** 이 문서 아래의 "📋 테스트 및 진단 스크립트" 섹션 참조

---

## 🔧 가장 흔한 5가지 원인 + 해결

**원인 1️⃣: is_gateway 설정 오류**
```bash
# 1. 확인
grep is_gateway /path/to/giipAgent.cnf
# 2. 수정 (필요시)
sed -i 's/is_gateway=0/is_gateway=1/g' /path/to/giipAgent.cnf
```

**원인 2️⃣: SSH 인증 실패**
```bash
# 1. sshpass 설치 확인
which sshpass
# 2. 없으면 설치
apt-get install sshpass  # Ubuntu/Debian
yum install sshpass      # CentOS/RHEL
# 3. SSH 테스트
sshpass -p YOUR_PASSWORD ssh -o ConnectTimeout=5 giip@REMOTE_IP "echo OK"
```

**원인 3️⃣: 리모트 서버 목록 없음**
```sql
-- DB 확인 (Gateway에 할당된 리모트 서버 있는가?)
SELECT COUNT(*) FROM tManagedServer WHERE gateway_lssn = 71240;
```

**원인 4️⃣: API 연결 실패**
```bash
# 1. API 연결 테스트
curl -I https://YOUR_API_URL
# 2. SSL 인증서 확인
curl -v https://YOUR_API_URL 2>&1 | grep -i certificate
```

**원인 5️⃣: 라이브러리 파일 누락**
```bash
# 1. 파일 확인
ls -la /path/to/giipAgentLinux/lib/gateway.sh
# 2. 권한 확인
chmod +x /path/to/giipAgentLinux/lib/*.sh
```

---

## 📞 최종 확인 (문제 해결 후)
```
[5.1] Agent 시작
  ↓
[5.2] 설정 로드
  ↓
[5.3] is_gateway=0 감지 → NORMAL MODE 진입
  ↓
[5.5.N] 큐 기반 처리 (CQEQueueGet API)
  ↓
[5.6.N] 큐 항목별 처리
  ↓
[5.7.N] 각 DB 상태 체크
  ↓
[6.0] 정상 종료
```

### B. GATEWAY MODE (is_gateway = 1)
```
[5.1] Agent 시작
  ↓
[5.2] 설정 로드
  ↓
[5.3.G] is_gateway=1 감지 → GATEWAY MODE 진입
  ↓
[5.4] GatewayRemoteServerListForAgent API 호출
  ↓
  ├─ 성공 (count > 0)
  │  ↓
  │  [5.5] 루프 시작
  │  ↓
  │  [5.6] 서버별 순차 처리 시작
  │  ├─ SSH 연결 테스트 [5.7]
  │  ├─ 원격 명령 실행 [5.8]
  │  ├─ Auto-Discover 실행 [5.9]
  │  └─ 관리DB 체크 [5.10]
  │
  └─ 실패 (count = 0 또는 API 에러)
     ↓
     [5.5.E] 에러 로깅 및 대기
     ↓
     다음 사이클에서 재시도
```

---

## 🔴 현재 문제 분석 및 해결책

### 📊 최근 실행 결과 (2025-11-27 09:25 UTC+9)

**KVS 조회 결과:**
```
✅ 조회 완료: 14/41 (최근 5분 내 기록)

실행 순서:
1. ✅ [5.1] Agent 시작 (09:25:03)
   - version=3.00, mode=gateway, is_gateway=1
   
2. ✅ [5.3] Gateway 모드 초기화 (09:25:03)
   - event_type: gateway_init
   - db_connectivity: will_verify
   - server_count: 0
   
3. ✅ [5.4] Auto-Discover 진행 (09:25:03 ~ 09:25:08)
   - STEP-1: Configuration Check ✅
   - STEP-2: Script Path Check ⚠️ (경로 미존재, 하지만 계속 진행)
   - STEP-3: Initialize KVS Records ✅
   - STEP-4: Execute Auto-Discover Script ✅
   - STEP-5: Validate Result File ✅
   - STEP-6: Extract Components ✅
   - STEP-7: Store Complete Marker ✅
   - auto_discover_complete: status=completed ✅
   
4. ✅ [5.5] Managed DB 체크 (09:25:14 ~ 09:25:16)
   - p-cnsldb01m: ✅ 620ms
   - p-cnsldb02m: ✅ 645ms
   - p-cnsldb03m: ✅ 658ms
   
5. ✅ [6.0] 정상 종료 (09:25:18)
   - status: normal_exit
```

### ✅ 현재 상태: 정상 작동

**결론:** 🟢 **문제 없음** - 스크립트가 정상적으로 실행되고 있습니다.

### ⚠️ 주의 사항

| 항목 | 상태 | 영향도 | 조치 |
|------|------|--------|------|
| Auto-Discover 스크립트 경로 | ⚠️ 미존재 | 🟡 낮음 | 경로 확인 필수, 하지만 현재는 처리 진행 중 |
| 순차 실행 | ✅ 정상 | - | 각 단계가 올바른 순서로 진행 |
| 데이터 수집 | ✅ 정상 | - | 모든 DB로부터 성능 데이터 수집 중 |
| KVS 저장 | ✅ 정상 | - | 모든 결과가 정상적으로 KVS에 기록 |

---

### 🔍 문제 발생 시나리오별 해결책

#### **시나리오 1️⃣: 포인트 [5.1] ~ [5.3] 중 하나가 없음**

**증상:**
```
❌ [5.1] 없음 → Agent 시작 불가
❌ [5.2] 없음 → Config 로드 실패
❌ [5.3] 없음 → is_gateway 판단 불가
```

**원인:**
- giipAgent3.sh 실행 안됨
- 라이브러리 파일 로드 실패
- 설정 파일 누락 또는 권한 문제

**해결 방법:**
```bash
# 1. 스크립트 실행 권한 확인
ls -la giipAgent3.sh
chmod +x giipAgent3.sh

# 2. 라이브러리 파일 확인
ls -la lib/*.sh
ls -la lib/common.sh lib/kvs.sh

# 3. 설정 파일 확인
cat ../giipAgent.cnf | head -20
grep "is_gateway" ../giipAgent.cnf

# 4. 수동 실행
./giipAgent3.sh
```

---

#### **시나리오 2️⃣: [5.3] 이후 [5.3.G] (Gateway 모드)가 없고 NORMAL 모드로 진입**

**증상:**
```
✅ [5.1] Agent 시작
✅ [5.2] 설정 로드
✅ [5.3] is_gateway 값 조회
❌ [5.3.G] 없음 → NORMAL MODE로 진입 (Gateway 모드 미진입)
```

**원인:**
- `is_gateway=0` 또는 `false`로 설정됨
- DB API 응답에서 is_gateway 값이 0임
- 설정이 최근에 변경됨

**해결 방법:**

```bash
# 1. 로컬 설정 파일 확인
cat ../giipAgent.cnf | grep -i "is_gateway\|gateway"

# 2. 필요시 수정
sed -i 's/is_gateway=0/is_gateway=1/g' ../giipAgent.cnf

# 3. DB 설정도 확인 (DB API 응답값)
# KVS 조회로 API 응답 확인
# kFactor: api_lsvrgetconfig_response에서 is_gateway 값 확인
```

**SQL 직접 확인 (필요시):**
```sql
-- SQL Server
SELECT lssn, hostname, is_gateway 
FROM tManagedServer 
WHERE lssn = 71240;

-- 필요시 수정
UPDATE tManagedServer SET is_gateway = 1 WHERE lssn = 71240;
```

---

#### **시나리오 3️⃣: [5.4] Auto-Discover 단계 중 특정 STEP에서 중단**

**증상:**
```
✅ [5.3.G] Gateway 모드 초기화
✅ STEP-1, 2, 3 완료
❌ STEP-4 실행 중 중단 또는 실패
❌ auto_discover_complete 없음 또는 status: error
```

**원인:**
- Auto-Discover 스크립트 실행 실패
- 스크립트 경로 오류
- 타임아웃 (60초 초과)
- 권한 문제

**해결 방법:**

```bash
# 1. Auto-Discover 스크립트 경로 확인
ls -la /home/shinh/scripts/infraops01/giipAgentLinux/giipscripts/auto-discover-linux.sh

# 2. 없으면 경로 수정 필요
# giipAgent3.sh 또는 gateway.sh에서 경로 수정

# 3. 스크립트 실행 권한 확인
chmod +x /home/shinh/scripts/infraops01/giipAgentLinux/giipscripts/auto-discover-linux.sh

# 4. 스크립트 직접 테스트
/home/shinh/scripts/infraops01/giipAgentLinux/giipscripts/auto-discover-linux.sh

# 5. 타임아웃 시간 증가 필요시
# gateway.sh에서 timeout 값 수정 (기본: 60초)
# timeout_sec=120 으로 변경
```

**KVS에서 에러 메시지 확인:**
```powershell
# PowerShell에서 STEP별 상세 로그 조회
cd giipdb
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71240 -KFactor auto_discover_step_4_execution -Top 5
```

---

#### **시나리오 4️⃣: [5.5] Auto-Discover 완료 후 [5.6] 서버 처리가 없음**

**증상:**
```
✅ auto_discover_complete: status=completed
❌ managed_db_check 기록 없음
❌ 서버별 처리 로그 없음
```

**원인:**
- GatewayRemoteServerListForAgent API 호출 실패
- 리모트 서버 목록이 비어있음 (count=0)
- 서버 처리 루프 진입 실패

**해결 방법:**

```bash
# 1. API 직접 테스트
curl -X POST \
  -d "text=GatewayRemoteServerListForAgent lssn&token=YOUR_SECRET_KEY&jsondata={\"lssn\":71240}" \
  https://giipfaw.azurewebsites.net/api/giipApiSk2 \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --insecure

# 2. 응답 형식 확인
# {"data":[]} → 빈 배열 (서버 없음)
# {"data":[{"lssn":71241,...},...]} → 정상

# 3. DB에서 리모트 서버 확인
SELECT COUNT(*) FROM tManagedServer WHERE gateway_lssn = 71240;

# 4. 없으면 DB에 리모트 서버 추가
INSERT INTO tManagedServer (lssn, hostname, gateway_lssn, ...) VALUES (...);
```

---

#### **시나리오 5️⃣: [5.6] 서버별 처리 중 SSH 연결 실패**

**증상:**
```
✅ managed_db_check 기록 시작
❌ 첫 번째 또는 특정 서버에서 중단
❌ 로그: "SSH: Connection refused" 또는 "Permission denied"
```

**원인:**
- SSH 인증 정보 오류
- 리모트 서버가 응답하지 않음
- 방화벽 또는 네트워크 문제
- sshpass 미설치

**해결 방법:**

```bash
# 1. sshpass 설치 확인
which sshpass
sshpass -V

# 2. 없으면 설치
apt-get install sshpass  # Ubuntu/Debian
yum install sshpass      # CentOS/RHEL

# 3. SSH 인증 정보 확인 (giipAgent.cnf)
grep -i "remote_user\|remote_pass" ../giipAgent.cnf

# 4. 각 리모트 서버별 SSH 테스트
for server_ip in $(grep "remote_server" ../giipAgent.cnf | cut -d= -f2); do
  echo "Testing $server_ip..."
  sshpass -p YOUR_PASSWORD ssh -o ConnectTimeout=5 giip@$server_ip "echo OK"
done

# 5. 리모트 서버에서 SSH 포트 확인
ssh -vvv giip@REMOTE_SERVER_IP

# 6. 방화벽 확인
telnet REMOTE_SERVER_IP 22
```

**KVS에서 SSH 로그 확인:**
```powershell
# SSH 연결 결과 로그 조회
cd giipdb
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71240 -KFactor ssh_connection -Top 10
```

---

#### **시나리오 5️⃣-A: SSH 연결 성공 후 lsChkdt 미업데이트**

**증상:**
```
✅ [5.9] SSH 연결 성공 로그 있음
✅ gateway_step_5.9_ssh_success 기록됨
❌ tManagedServer.lsChkdt가 최신 날짜로 업데이트 안됨
❌ 리모트 서버 상태가 "checking" 상태에서 안 넘어감
```

**원인:**
- CQEQueueGet API 호출이 제대로 이루어지지 않음
- API 응답 처리 실패
- 네트워크 연결 끊김

**핵심 메커니즘 (giipAgent3.sh → gateway.sh → normal.sh):**

```bash
# giipAgentLinux/lib/gateway.sh line 648:
# [5.3.1] 🟢 Gateway 자신의 큐 처리 (CQEQueueGet API 호출 → LSChkdt 자동 업데이트)

# giipAgentLinux/lib/normal.sh line 24:
local text="CQEQueueGet lssn hostname os op"
local jsondata="{\"lssn\":${lssn},\"hostname\":\"${hostname}\",\"os\":\"${os}\",\"op\":\"op\"}"

# ✅ CQEQueueGet API 호출 시 DB에서 자동으로:
# 1. lsChkdt를 현재 시간으로 설정
# 2. lsChkStatus를 업데이트
# → gateway.sh가 직접 업데이트하는 게 아니라 API 응답으로 자동 업데이트됨!
```

**따라서 lsChkdt 업데이트를 위한 필수 조건:**

| 조건 | 상태 | 확인 방법 |
|------|------|---------|
| ✅ CQEQueueGet API 호출 | 필수 | KVS에서 [5.3.1] 포인트 확인 |
| ✅ API 응답 수신 | 필수 | 네트워크 연결 정상 |
| ✅ DB 연결 정상 | 필수 | API 서버의 DB 연결 상태 |
| ✅ lsChkdt 컬럼 활성 | 필수 | tManagedServer 테이블 스키마 |

**해결 방법:**

```powershell
# 1️⃣ CQEQueueGet API가 실제로 호출되는지 확인 (KVS 로그)
cd giipdb
pwsh .\mgmt\check-latest.ps1 -PointFilter "5\.3\.1" -NoPointFilter:$false -Top 20

# 출력 예시 (정상):
# [5.3.1] Gateway 자신의 큐 조회 시작
# [5.3.1-EXECUTE] Gateway 자신의 큐 존재, 스크립트 실행 
# [5.3.1-COMPLETED] Gateway 자신의 큐 실행 완료

# 2️⃣ [5.3.1] 포인트가 있는가?
# ✅ 있음 → API 호출 성공, lsChkdt는 자동 업데이트됨
# ❌ 없음 → fetch_queue 함수 미로드 또는 API 호출 실패

# 3️⃣ [5.3.1-EMPTY]가 나오는 경우?
# → API 응답이 없음 (404) → 큐 서버 연결 문제
```

**최종 확인:**

```bash
# lsChkdt 확인 (직접 확인은 사용자가 할 것)
# SQL:
SELECT TOP 20 
    lssn, hostname, lsChkdt,
    DATEDIFF(MINUTE, lsChkdt, GETDATE()) as minutes_ago,
    lsChkStatus
FROM tManagedServer 
WHERE lssn IN (71240, 71241, 71242)
ORDER BY lsChkdt DESC;

# 예상 결과 (정상):
# lssn=71240: lsChkdt=2025-11-27 19:25:18, minutes_ago=0-5 ✅
# lssn=71241: lsChkdt=2025-11-27 19:25:18, minutes_ago=0-5 ✅
# lssn=71242: lsChkdt=2025-11-27 19:25:18, minutes_ago=0-5 ✅

# ❌ 문제: minutes_ago > 30 
# → CQEQueueGet API 호출이 안됨 → [5.3.1] 포인트가 없음 확인
```

**문제 해결 체크리스트:**

- [ ] KVS에 `[5.3.1-COMPLETED]` 기록이 있는가? (API 호출 성공)
- [ ] 있다면 → **lsChkdt는 자동 업데이트됨 ✅** (확인만 하면 됨)
- [ ] 없다면 → **API 호출 자체가 안됨** (fetch_queue 함수 또는 API 서버 문제)

---

#### **시나리오 6️⃣: [5.8] 명령 실행은 되지만 데이터 수집이 없음**

**증상:**
```
✅ SSH 연결 성공
✅ [5.9-SUCCESS] SSH 연결 성공 로그 있음
✅ lsChkdt 업데이트됨
❌ 하지만 응답 데이터(managed_db_check 등)가 없음
❌ response_time_ms 없음
```

**원인:**
- 원격 명령 실행 실패 또는 타임아웃
- 명령 출력 파싱 오류
- 권한 부족
- 리모트 도구 미설치

**해결 방법:**

```bash
# 1. 리모트 서버에서 명령 직접 테스트
ssh giip@REMOTE_SERVER_IP "mysql -u user -p password -e 'SELECT VERSION();'"

# 2. 명령 결과 확인
ssh giip@REMOTE_SERVER_IP "mysql -u user -p password -e 'SHOW STATUS WHERE Variable_name=\"Threads_connected\";'"

# 3. 필요한 도구 설치 확인
ssh giip@REMOTE_SERVER_IP "which mysql"
ssh giip@REMOTE_SERVER_IP "which mongosh"

# 4. 권한 확인
ssh giip@REMOTE_SERVER_IP "whoami"

# 5. giipAgent.cnf에서 명령 정의 확인
grep "remote_cmd\|remote_query" ../giipAgent.cnf
```

**KVS에서 명령 실행 결과 확인:**
```powershell
# managed_db_check의 response_time_ms 확인
cd giipdb
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71240 -KFactor managed_db_check -Top 10
```

---

#### **시나리오 7️⃣: [5.9] Auto-Discover 실행이 매우 느림 또는 타임아웃**

**증상:**
```
✅ STEP-4 Execute 시작
❌ 60초 이상 대기 없이 실패
❌ 타임아웃 메시지
❌ auto_discover_complete가 나타나지 않음
```

**원인:**
- Auto-Discover 스크립트가 느림
- 타임아웃 설정이 짧음 (기본: 60초)
- 시스템 리소스 부족
- 네트워크 지연

**해결 방법:**

```bash
# 1. Auto-Discover 스크립트 직접 실행 (시간 측정)
time /home/shinh/scripts/infraops01/giipAgentLinux/giipscripts/auto-discover-linux.sh

# 2. 실행 시간 확인
# real: 2-3초 정상
# real: 10초 이상 → 느림
# real: 60초 이상 → 타임아웃 위험

# 3. 필요시 타임아웃 증가
# gateway.sh에서:
# timeout_sec=60 → timeout_sec=120 또는 180

# 4. 또는 백그라운드 실행으로 변경
# 긴 작업은 큐에 저장 후 별도 처리
```

---

#### **시나리오 8️⃣: [5.10] 관리DB 체크 실패**

**증상:**
```
✅ Auto-Discover 완료
✅ 처음 몇 개 DB는 성공
❌ 특정 DB에서 connection error
❌ check_status: failed
```

**원인:**
- DB 연결 실패 (네트워크, 인증, 포트)
- DB 서버 다운
- DB 크레덴셜 오류
- 방화벽 차단

**해결 방법:**

```bash
# 1. 해당 DB 직접 연결 테스트
mysql -h DB_HOST -u USER -p DB_PASSWORD -e "SELECT 1;"

# 2. 포트 확인
telnet DB_HOST 3306

# 3. DB 서버 상태 확인
# 다른 클라이언트에서 연결 가능한지 확인

# 4. 크레덴셜 확인
# giipAgent.cnf 또는 DB 메타데이터 확인

# 5. 방화벽 확인
# iptables / ufw 상태 확인
iptables -L -n | grep 3306
```

**KVS에서 DB 체크 실패 상세 확인:**
```powershell
cd giipdb
pwsh .\mgmt\query-kvs.ps1 -KType lssn -KKey 71240 -KFactor managed_db_check -Top 20
# check_status: failed인 항목 찾기
```

---

## 📊 상세 진단 (필요시만)

> **핵심:** 가장 중요한 지표는 `tManagedServer.lsChkdt`가 **최근 5분 이내로 주기적 업데이트** 되는가?
> 
> **이것이 가능하다 = 모든 것이 정상**

### ✅ Level 1: 기본 설정 확인 (소요 시간: 5분)

#### 1️⃣ Gateway 모드 활성화 확인

```bash
# giipAgent.cnf 확인
cat /path/to/giipAgent.cnf | grep -E "is_gateway|gateway_mode"

# 예상 결과:
# is_gateway=1 또는 gateway_mode=1
```

**진단 포인트:**
- [ ] `is_gateway` 또는 `gateway_mode`가 `1` 또는 `true`로 설정되어 있는가?
- [ ] 값이 `0` 또는 `false`로 변경되었는가?

**문제 발견 시:**
```bash
# giipAgent.cnf 수정
sed -i 's/is_gateway=0/is_gateway=1/g' giipAgent.cnf
```

#### 2️⃣ DB 설정 값 조회 (실시간 확인)

```bash
# giipAgent3.sh 로그 포인트 #5.2 확인
# 로그에서 "is_gateway" 값 추출

# 직접 조회 (API 테스트)
curl -X POST \
  -d "text=LSvrGetConfig lssn hostname&token=YOUR_SECRET_KEY&jsondata={\"lssn\":YOUR_LSSN,\"hostname\":YOUR_HOSTNAME}" \
  https://YOUR_API_URL

# 응답 형식 예시:
# {"data":[{"is_gateway":true,"RstVal":"200",...}]}
```

**진단 포인트:**
- [ ] API 응답에 `is_gateway` 필드가 있는가?
- [ ] 값이 `true` 또는 `1`인가?
- [ ] API 자체가 응답하는가 (연결 실패는 아닌가)?

#### 3️⃣ 로그 포인트 확인 (실행 흐름 추적)

```bash
# giipAgent3.sh 실행 후 로그 확인
# 로그 위치: 보통 /var/log/giip/ 또는 /tmp/

# 포인트 #5.1 ~ #5.3 확인
grep -E "\[5\.[1-3]\]" /path/to/logfile

# 예상 출력:
# [giipAgent3.sh] 🟢 [5.1] Agent 시작: version=3.00
# [giipAgent3.sh] 🟢 [5.2] 설정 로드 완료: lssn=12345, hostname=gateway01, is_gateway=1
# [giipAgent3.sh] 🟢 [5.3] Gateway 모드 감지 및 초기화
```

**진단 포인트:**
- [ ] `[5.1]` 로그가 있는가? (Agent 시작)
- [ ] `[5.2]` 로그가 있는가? (설정 로드)
  - [ ] `is_gateway=1`이 명시되어 있는가?
- [ ] `[5.3]` 로그가 있는가? (Gateway 모드 초기화)

**문제 발견 시:**
- `[5.2]`에서 `is_gateway=0`이면 DB 설정 확인 필요
- `[5.2]`가 없으면 DB API 연결 문제
- `[5.3]`이 없으면 실제 Gateway 모드 진입 실패

**✅ 더 빠른 방법: KVS 데이터로 확인**

```powershell
# Windows/PowerShell에서
cd giipdb
pwsh .\mgmt\check-latest.ps1

# 출력:
# 최근 5분 내 [5.x] 포인트 로그 표시
# 예: 16/82 (전체 82개 중 최근 5분 내 16개)
```

| 포인트 | 의미 | KVS Factor | 정상 상태 |
|-------|------|-----------|---------|
| [5.1] | Agent 시작 | giipagent | 매 사이클마다 1회 |
| [5.2] | 설정 로드 완료 | api_lsvrgetconfig_success | is_gateway=1 포함 |
| [5.3] | Gateway 모드 초기화 | gateway_init | 항상 나타남 |
| [5.4] | 서버 목록 조회 시작 | gateway_operation | 주기적 반복 |

**의심 신호:**
- ❌ [5.1] ~ [5.3] 중 하나 이상 없음: 초기화 실패
- ❌ [5.3] 이후 [5.4]가 오지 않음: 서버 조회 루프 미진입
- ❌ 같은 포인트가 반복: Hang/데드락 가능성

---

### ✅ Level 2~4: 상세 진단

> **더 자세한 진단 절차는 [GATEWAY_DETAILED_DIAGNOSIS.md](./GATEWAY_DETAILED_DIAGNOSIS.md) 참조**

**빠른 요약:**
- **Level 2:** `tManagedServer.lsChkdt` SQL 조회로 SSH 연결 성공 확인
- **Level 3:** GatewayRemoteServerListForAgent API 호출로 서버 목록 확인
- **Level 4:** 디버그 모드(`bash -x giipAgent3.sh`) 실행으로 전체 흐름 추적

---

## 🔧 일반적인 원인과 해결책

### 원인 1: `is_gateway` 설정이 0 또는 false

**증상:**
- 로그에 `[5.3]` 포인트가 없음
- "Running in NORMAL MODE" 메시지 표시

**해결:**
```bash
# 1. giipAgent.cnf 수정
sed -i 's/is_gateway=0/is_gateway=1/g' /path/to/giipAgent.cnf

# 2. DB 테이블 수정 (필요시)
# SQL Server:
UPDATE tManagedServer SET is_gateway = 1 WHERE lssn = YOUR_GATEWAY_LSSN

# 3. giipAgent3.sh 재실행
./giipAgent3.sh
```

---

### 원인 2: DB API 연결 실패

**증상:**
- 로그에 `[5.2]` 포인트가 없거나 "Failed to fetch server config" 메시지
- API URL이 잘못되었거나 네트워크 연결 불가

**확인:**
```bash
# API 연결 테스트
curl -I https://YOUR_API_URL

# SSL 인증서 문제 확인
curl -v https://YOUR_API_URL 2>&1 | grep -i "certificate\|ssl"

# 방화벽 확인
telnet YOUR_API_URL 443
```

**해결:**
```bash
# giipAgent.cnf에서 API URL 확인
grep -i "apiaddr" /path/to/giipAgent.cnf

# 필요시 수정
sed -i 's|apiaddrv2=.*|apiaddrv2="https://correct-url"|g' /path/to/giipAgent.cnf
```

---

### 원인 3: 리모트 서버 목록이 비어있음

**증상:**
- 로그에 `[5.5]` 포인트에서 "count=0" 표시
- GatewayRemoteServerListForAgent API가 빈 배열 반환

**확인:**
```bash
# DB에서 직접 확인
# 해당 Gateway에 할당된 리모트 서버가 있는가?
SELECT COUNT(*) FROM tManagedServer WHERE gateway_lssn = YOUR_GATEWAY_LSSN
```

**해결:**
```bash
# 1. DB 테이블에 리모트 서버 추가
# 2. 또는 API를 통해 서버 등록
# 3. 다시 시도
./giipAgent3.sh
```

---

### 원인 4: SSH 연결 실패

**증상:**
- 로그에 `[5.7]` (SSH 연결 테스트) 이후 에러 메시지
- "sshpass: Permission denied" 또는 "Connection refused"

**확인:**
```bash
# sshpass 설치 확인
which sshpass
sshpass -V

# SSH 키 또는 암호 확인
ssh -i /path/to/key giip@YOUR_REMOTE_SERVER "echo OK"
```

**해결:**
```bash
# 1. sshpass 설치 (없으면)
apt-get install sshpass  # Ubuntu/Debian
yum install sshpass      # CentOS/RHEL

# 2. SSH 인증 정보 확인
# giipAgent.cnf에서 SSH 설정 확인
grep -i "ssh\|remote_user\|remote_pass" /path/to/giipAgent.cnf

# 3. 방화벽 확인
# 리모트 서버의 SSH 포트(보통 22) 열려있는가?
telnet YOUR_REMOTE_SERVER_IP 22
```

---

### 원인 5: 라이브러리 파일 누락 또는 손상

**증상:**
- 에러: "gateway.sh not found" 또는 유사한 메시지
- 또는 라이브러리 함수 정의 안됨 에러

**확인:**
```bash
# 라이브러리 파일 확인
ls -la /path/to/giipAgentLinux/lib/

# 파일 무결성 확인
md5sum /path/to/giipAgentLinux/lib/*.sh

# 파일 인코딩 확인 (DOS/Unix line endings 문제)
file /path/to/giipAgentLinux/lib/gateway.sh
```

**해결:**
```bash
# 1. 라이브러리 파일 권한 수정
chmod +x /path/to/giipAgentLinux/lib/*.sh

# 2. 라인 ending 수정 (필요시)
dos2unix /path/to/giipAgentLinux/lib/*.sh

# 3. 파일 재다운로드 (손상된 경우)
# Git에서 다시 받아오기 등
```

---

## 📚 관련 문서 및 다음 단계

**문제 해결 완료:** 정상 작동 확인 후 모니터링 계속

**여전히 미해결:** [GATEWAY_DETAILED_DIAGNOSIS.md](./GATEWAY_DETAILED_DIAGNOSIS.md) 참조

---

## 🔄 문제 해결 프로세스

1. **초기 진단**: Level 1 체크리스트 완료
2. **근본 원인 파악**: Level 2-3 진단 수행
3. **일반적 원인별 해결**: 5가지 원인 중 해당 항목 적용
4. **심화 진단**: 위의 모든 단계 후에도 미해결 시 Level 4 진행
5. **검증**: 변경 후 giipAgent3.sh 재실행 및 로그 확인

---

## ✅ 문제 해결 완료 확인 (핵심 항목만)

- [ ] `pwsh .\mgmt\check-latest.ps1` → [5.x] 포인트 나타나는가?
- [ ] `SELECT DATEDIFF(MINUTE, lsChkdt, GETDATE()) FROM tManagedServer WHERE lssn=71241` → 0-5 사이?
- [ ] lsChkdt가 매 5분마다 새로운 시간으로 업데이트?
- [ ] 이전과 다르게 정상 작동하는가?

**모두 예라면 문제 해결 완료! ✅**

---

## 📊 정리 요약

✅ **3~5분 빠른 진단** - 가장 흔한 5가지 원인 정리
✅ **4가지 상황별 명령어** - 상황에 맞는 최적 명령어 제시
✅ **KVS Factor 기반 추적** - 포인트별 실행 흐름 명확
✅ **SQL 직접 확인** - lsChkdt 업데이트 여부로 최종 판단

---

**📝 문서 버전:** v2.2 (2025-11-27)  
**⚡ 최근 개선:** 진단 체크리스트 축약, Level 2-4 상세 내용 별도 파일로 분리  
**👤 담당:** DevOps Team
