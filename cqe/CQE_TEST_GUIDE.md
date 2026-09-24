# CQE (Command Queue Executor) 테스트 및 문제 해결 가이드

> **⚠️ 필독**: 이 문서를 읽기 전에 반드시 참고하세요
> - [🚨 PROHIBITED_ACTIONS.md](../../giipdb/docs/PROHIBITED_ACTIONS.md) - 절대 금지 사항 (특히 #14 참고)
> - [PROHIBITED_ACTION_14_COMMON_MODULE.md](../../giipdb/docs/PROHIBITED_ACTION_14_COMMON_MODULE.md) - 공통 모듈 건드리지 말 것

## 개요
- **테스트 일시**: 2025-01-04
- **목적**: giipAgent.sh/giipAgent3.sh의 CQE 큐 가져오기 기능 검증
- **핵심 테이블**: `tMgmtQue` (관리 작업 큐)
- **핵심 SP**: `pApiCQEQueueGetbySK`

---

## 🔗 관련 문제 분석 문서

### 🚨 Gateway SSH 테스트 후 LSChkdt 미업데이트 문제

**파일**: `gateway/ssh_test.sh`

**증상**: 
```bash
bash gateway/ssh_test.sh  # 실행 성공
✅ Test completed
```

하지만 DB에서 확인:
```sql
SELECT LSsn, LSHostname, LSChkdt FROM tLSvr WHERE LSsn IN (71221, 71242)
-- LSChkdt가 업데이트되지 않음 (이전 값 유지)
```

**근본 원인**: pApiCQEQueueGetbySk SP가 **실행되지 않음**

#### 원인 분석

**1️⃣ queue_get 함수가 호출되지 않은 경우**
```bash
# gateway/ssh_test.sh의 로직
if [ $test_result -eq 0 ]; then  # SSH 연결 성공
    if declare -f queue_get &>/dev/null; then
        queue_get "$lssn" "$hostname" "$detected_os" "$queue_file"
    fi
fi
```

- ❌ SSH 연결 실패 → queue_get 미호출
- ❌ queue_get 함수 찾을 수 없음 → 미호출
- ✅ SSH 성공 + queue_get 함수 있음 → 호출

**2️⃣ queue_get 함수가 호출되었으나 API 호출 실패**

```bash
queue_get "$lssn" "$hostname" "$detected_os" "$queue_file"
# ↓
curl -X POST "${api_url}" \
    -d "text=CQEQueueGet&token=${sk}&jsondata=${jsondata}" \
    ...
```

실패 원인:
- ❌ sk 변수가 비어있음 (export 안 됨)
- ❌ apiaddrv2 변수가 비어있음
- ❌ 네트워크 오류
- ❌ API 엔드포인트 다운

**3️⃣ API 호출은 되었으나 SP가 실행되지 않음**

```bash
# API 응답 확인
[queue_get] INFO: No queue available for LSSN=71221
```

→ 이 메시지는 SP가 **실행됐으나 큐가 없음** (정상)
→ LSChkdt는 **업데이트되어야 함**

하지만 업데이트 안 됨 = **다른 원인**

#### 해결 방법

**1️⃣ SSH 연결 성공 확인**
```bash
# gateway/ssh_test.sh 출력에서
✅ Test completed
✓ p-cnsldb01m  # SSH 성공 표시
```

SSH가 성공으로 표시되었다면 연결은 정상입니다.

**2️⃣ queue_get 함수가 호출되었는지 확인**

```bash
# queue_get 함수 로드 확인
declare -f queue_get

# 결과:
# - 함수 내용 출력됨 → ✅ 정상 로드
# - "declare: queue_get: not found" → ❌ cqe.sh 로드 실패
```

**3️⃣ API 변수 전달 상태 확인**

⚠️ **주의**: `load_config` 함수는 공통 모듈이므로 수정 금지
- 참조: [PROHIBITED_ACTION_14](../../giipdb/docs/PROHIBITED_ACTION_14_COMMON_MODULE.md)

현재 구조 (원본):
```bash
# giipAgentLinux/lib/common.sh의 load_config
. "$config_file"  # ← source만 수행, export 미수행
```

**확인 방법 (추측 금지, 증거 기반으로)**:
```bash
# gateway/ssh_test.sh 또는 cqe.sh 내에서 실제 변수 값 확인
if [ -z "$sk" ]; then
    echo "ERROR: sk 변수가 비어있음"
    exit 1
fi
if [ -z "$apiaddrv2" ]; then
    echo "ERROR: apiaddrv2 변수가 비어있음"
    exit 1
fi
```

**4️⃣ API 응답 상태 직접 확인**

증거 기반 진단 (로그 요청 금지):
```bash
# 임시 응답 저장 후 분석
queue_file="/tmp/debug_queue_$$.sh"

# curl 직접 호출
curl -v -X POST "${apiaddrv2}" \
    -d "text=CQEQueueGet&token=${sk}&jsondata=..." \
    -o "${queue_file}" 2>&1 | tee /tmp/curl_debug.log

# 응답 코드 확인
echo "Response status: $?" 

# 응답 내용 확인
cat "${queue_file}"
```

**5️⃣ DB에서 SP 실행 여부 확인 (직접 조회)**

사용자에게 로그 요청 금지 - 직접 DB 조회:
```sql
-- SP 최근 실행 로그 확인
SELECT TOP 10 
    LSsn, LSHostname, LSChkdt,
    DATEDIFF(MINUTE, LSChkdt, GETDATE()) AS minutes_ago
FROM tLSvr WITH(NOLOCK)
WHERE LSsn IN (71221, 71242)
ORDER BY LSChkdt DESC

-- LSChkdt가 최근이면 → ✅ SP 실행됨
-- LSChkdt가 오래되면 → ❌ SP 미실행
```

#### 근본 원인 분석 (증거 기반)

**확인된 문제 리스트**:
1. ❓ `queue_get` 함수 호출 안 됨 → 코드 확인
2. ❓ API 변수(sk, apiaddrv2) 미설정 → 현재 구조 문제
3. ❓ API 응답 오류(401, 503 등) → 네트워크/엔드포인트 상태
4. ❓ SP 권한 부족 → 디비 권한 설정 확인

**증거를 찾으면 사용자에게 보고, 지시 대기**

#### 최가능성 높은 원인 (gateway/ssh_test.sh 기준)

| # | 원인 | 확인 방법 | 해결책 |
|---|------|---------|--------|
| 1 | **sk, apiaddrv2 미export** | queue_get 내에서 변수 확인 | `export sk apiaddrv2` 추가 |
| 2 | queue_get 함수 미로드 | cqe.sh 로드 확인 | `declare -f queue_get` 테스트 |
| 3 | SSH 연결 실패 | ssh_test 로그 확인 | SSH 문제 해결 |
| 4 | API 엔드포인트 오류 | curl 응답 확인 | API 상태 확인 |
| 5 | SP 권한 없음 | 로그 확인 | DB 권한 설정 |

---

## CQE 시스템 구조

### 1. API 호출 → DB 업데이트 플로우

```
gateway/ssh_test.sh 실행
    ↓
queue_get 함수 호출
    ↓
curl -X POST ${apiaddrv2}
  Data: text=CQEQueueGet&jsondata={...}&token=${sk}
    ↓
giipfaw Azure Function (giipApiSk2)
    ↓
SP 라우팅: CQEQueueGet → pApiCQEQueueGetbySk
    ↓
[중요] pApiCQEQueueGetbySk 실행
  ├─ INPUT: @sk, @lsSn, @hostname, @os
  ├─ 처리:
  │  1. CSN 조회 (SK로부터)
  │  2. tLSvr 업데이트
  │     └─ LSHostname, LSOSVer 업데이트
  │  3. ⭐ LSChkdt = GETDATE() 업데이트 ⭐
  │  4. tMgmtQue 조회 (큐 있는지 확인)
  │  5. ms_body(스크립트) 반환
  └─ OUTPUT: JSON 응답
    ↓
queue_get 함수에서 응답 파싱
    ↓
ms_body 추출 후 파일 저장
```

**⚠️ 핵심**: LSChkdt는 **SP가 성공적으로 실행될 때만 업데이트됨**

### 2. LSChkdt 업데이트 조건

| 조건 | 결과 | LSChkdt 업데이트 |
|------|------|-----------------|
| SP 실행 성공 | JSON 응답 (RstVal=200, 201, 404 등) | ✅ YES |
| SP 실행 실패 | API 에러 (401, 500) | ❌ NO |
| queue_get 함수 실패 | 파라미터 검증 실패 | ❌ NO |
| API 엔드포인트 오류 | HTTP 오류 (503 등) | ❌ NO |

### 3. 데이터 흐름
```
[Web UI: CQE 관리]
    ↓ (스크립트 등록)
[tMgmtScriptList] → (스케줄 체크) → [tMgmtQue]
    ↓
[gateway/ssh_test.sh]
    ↓
[queue_get 함수]
    ↓
[API 엔드포인트]
    ↓ (pApiCQEQueueGetbySk 실행)
[tLSvr.LSChkdt 업데이트] ⭐
    ↓
[스크립트 반환 (ms_body)]
    ↓
[queue_get에서 파일 저장]
```

### 4. 테이블 구조

#### tLSvr (Logical Server)
```sql
LSsn              INT PRIMARY KEY    -- Logical Server Serial Number
LSHostname        NVARCHAR(200)      -- 서버 호스트명
LSOSVer           NVARCHAR(255)      -- OS 정보
LSChkdt           DATETIME           -- ⭐ 마지막 체크 시간 (SP 실행시 업데이트)
```

#### tMgmtQue
```sql
qsn         BIGINT IDENTITY(1,1)  -- 큐 순번
mslsn       INT                   -- 스크립트 리스트 번호
usn         INT                   -- 사용자 번호
csn         INT                   -- 고객사 번호
lssn        INT                   -- 서버 번호
ms_body     NTEXT                 -- 스크립트 본문
send_flag   TINYINT               -- 전송 플래그 (0:대기, 1:전송완료)
regdate     DATETIME              -- 등록일시
enddate     DATETIME              -- 완료일시
script_type VARCHAR(5)            -- 스크립트 타입
```

## API 엔드포인트 비교

### 구 버전 (giipAgent.sh)
```bash
# GET 방식
${apiaddr}/api/cqe/cqequeueget03.asp?sk=$sk&lssn=$lssn&hn=${hostname}&os=$os&df=os&sv=${sv}

# 예시
https://giipasp.azurewebsites.net/api/cqe/cqequeueget03.asp?sk=xxx&lssn=71240&hn=testserver&os=Ubuntu...
```
- **프로토콜**: GET (URL 파라미터)
- **기술**: ASP Classic
- **응답**: Plain text (스크립트 본문)
- **상태**: ✅ 정상 작동 중

### 신 버전 (giipAgent3.sh)
```bash
# POST 방식
wget -O "$output_file" \
    --post-data="text=CQEQueueGet ${lssn} ${hostname} ${os} op&token=${sk}" \
    --header="Content-Type: application/x-www-form-urlencoded" \
    "${apiaddrv2}"

# 예시
https://giipfaw.azurewebsites.net/api/giipApiSk2?code=xxx
POST: text=CQEQueueGet 71240 testserver Ubuntu op&token=xxx
```
- **프로토콜**: POST (form-urlencoded)
- **기술**: PowerShell (Azure Function)
- **응답**: JSON 형식
  ```json
  {
    "data": [{
      "RstVal": "200",
      "ms_body": "스크립트 내용...",
      "mslsn": 12345,
      "script_type": "sh",
      "mssn": 67890
    }]
  }
  ```
- **상태**: ✅ JSON 파싱 로직 구현 완료

## 변경 사항 (giipAgent3.sh)

### 1. get_remote_queue() 함수
**변경 전** (URL 파라미터 방식):
```bash
local download_url="${apiaddrv2}/cqequeueget03?sk=$sk&lssn=$lssn..."
wget -O "$output_file" "$download_url"
```

**변경 후** (POST + JSON 파싱):
```bash
local api_url="${apiaddrv2}"
local text="CQEQueueGet ${lssn} ${hostname} ${os} op"

wget -O "$output_file" \
    --post-data="text=${text}&token=${sk}" \
    "${api_url}"

# JSON 응답 파싱
if [ -s "$output_file" ]; then
    local is_json=$(cat "$output_file" | grep -o '^{.*}$')
    if [ -n "$is_json" ]; then
        local script_body=$(cat "$output_file" | grep -o '"ms_body":"[^"]*"' | \
            sed 's/"ms_body":"//; s/"$//' | sed 's/\\n/\n/g')
        echo "$script_body" > "$output_file"
    fi
fi
```

### 2. 메인 루프 (Normal Mode)
- **변경 전**: GET 방식으로 wget 호출
- **변경 후**: POST 방식 + JSON 파싱 로직 추가

### 3. 로그 파일명
- **구버전**: `giipAgent_$Today.log`
- **신버전**: `giipAgent3_$Today.log`

## 테스트 방법

### 방법 1: 테스트 스크립트 실행
```bash
cd giipAgentLinux
chmod +x test-cqe-queue.sh
./test-cqe-queue.sh
```

**출력 결과 분석**:
- ✅ Old API 정상: "Response received (Old API)"
- ✅ New API 정상: "Response received (New API)" + "Script found in ms_body"
- ⚠️ 큐 없음: "RstVal: 404" → 정상 (스케줄된 스크립트가 없음)
- ❌ 오류: "error", "401", "500" 등

### 방법 2: DB 직접 확인
```sql
-- 대기 중인 큐 확인
SELECT TOP 10
    qsn, mslsn, lssn, 
    LEFT(ms_body, 100) AS script_preview,
    send_flag, regdate
FROM tMgmtQue WITH(NOLOCK)
WHERE lssn = 71240  -- 실제 LSSN으로 변경
    AND send_flag = 0
ORDER BY qsn DESC

-- 스크립트 스케줄 확인
SELECT 
    msl.mslSn, msl.lssn, msl.mssn,
    msl.active, msl.interval,
    msl.lastdate, msl.scdt,
    ms.msName, ms.msBody
FROM tMgmtScriptList msl WITH(NOLOCK)
INNER JOIN tMgmtScript ms WITH(NOLOCK) ON msl.mssn = ms.mssn
WHERE msl.lssn = 71240  -- 실제 LSSN으로 변경
    AND msl.active = 1
ORDER BY msl.lastdate DESC
```

### 방법 3: 실제 Agent 실행 테스트
```bash
# giipAgent3.sh 실행 (테스트 모드)
cd giipAgentLinux
chmod +x giipAgent3.sh

# 한 번만 실행하고 종료
./giipAgent3.sh

# 로그 확인
tail -f log/giipAgent3_$(date +%Y%m%d).log
```

## 문제 해결

### 문제 1: "404 no queue" 반복
**원인**: 실행할 스크립트가 스케줄되지 않음

**해결**:
1. Web UI → CQE 관리 → 스크립트 생성
2. 테스트 스크립트 예시:
   ```bash
   echo "Test CQE at $(date)"
   df -h
   ```
3. LSSN에 할당, interval 1분으로 설정
4. 1분 후 재테스트

### 문제 2: JSON 파싱 실패
**증상**: 
```
Response received (New API)
⚠️ No ms_body field found in JSON
```

**원인**: 
- SP가 호출되지 않음
- giipApiSk2가 CQEQueueGet 명령어를 인식하지 못함

**해결**:
1. SP 존재 확인:
   ```sql
   SELECT OBJECT_ID('pApiCQEQueueGetbySK')
   -- NULL이면 SP가 없음
   ```

2. SP가 없다면 배포:
   ```powershell
   pwsh .\mgmt\execSQLFile.ps1 -sqlfile ".\SP\pApiCQEQueueGetbySK.sql"
   ```

3. giipApiSk2에서 명령어 매핑 확인:
   - `run.ps1` 파일에서 `CQEQueueGet` → `pApiCQEQueueGetbySK` 매핑이 자동으로 이루어짐
   - `exec pApiCQEQueueGetbySK` 형식으로 실행됨

### 문제 3: "401 Unauthorized"
**원인**: SK (Secret Key) 인증 실패

**해결**:
1. giipAgent.cnf 확인:
   ```bash
   cat giipAgent.cnf | grep sk=
   ```
2. DB에서 SK 확인:
   ```sql
   SELECT cSK, cName FROM tCli WHERE cSK = 'your_sk_here'
   ```
3. SK가 만료되었다면 재생성

### 문제 4: 스크립트가 실행되지 않음
**증상**: 큐는 가져오지만 실행 안 됨

**원인**: 
- ms_body가 비어있음
- send_flag 업데이트 실패
- 스크립트 권한 문제

**해결**:
1. ms_body 확인:
   ```sql
   SELECT qsn, LEN(ms_body) AS body_length, ms_body
   FROM tMgmtQue
   WHERE qsn = (큐 번호)
   ```

2. 수동 실행 테스트:
   ```bash
   # 큐에서 가져온 스크립트 저장
   cat > /tmp/test_script.sh << 'EOF'
   #!/bin/bash
   echo "Test script execution"
   EOF
   
   chmod +x /tmp/test_script.sh
   /tmp/test_script.sh
   ```

3. send_flag 수동 업데이트:
   ```sql
   UPDATE tMgmtQue
   SET send_flag = 1, enddate = GETDATE()
   WHERE qsn = (큐 번호)
   ```

## 검증 체크리스트

- [ ] tMgmtQue 테이블 존재 확인
- [ ] pApiCQEQueueGetbySK SP 존재 확인
- [ ] giipAgent.cnf 설정 확인 (sk, lssn, apiaddrv2)
- [ ] test-cqe-queue.sh 실행 → Old API 정상
- [ ] test-cqe-queue.sh 실행 → New API 정상
- [ ] Web UI에서 테스트 스크립트 생성
- [ ] giipAgent3.sh 실행 → 큐 가져오기 성공
- [ ] 스크립트 실행 확인 (로그)
- [ ] send_flag = 1 업데이트 확인 (DB)

## 성능 및 모니터링

### 주요 메트릭
```sql
-- 대기 중인 큐 개수
SELECT COUNT(*) AS pending_queue_count
FROM tMgmtQue WITH(NOLOCK)
WHERE send_flag = 0

-- 최근 1시간 실행된 큐
SELECT COUNT(*) AS executed_queue_count
FROM tMgmtQue WITH(NOLOCK)
WHERE send_flag = 1
    AND enddate >= DATEADD(HOUR, -1, GETDATE())

-- 평균 실행 시간
SELECT 
    AVG(DATEDIFF(SECOND, regdate, enddate)) AS avg_execution_seconds
FROM tMgmtQue WITH(NOLOCK)
WHERE send_flag = 1
    AND enddate >= DATEADD(HOUR, -1, GETDATE())
```

### 로그 모니터링
```bash
# 실시간 로그 확인
tail -f giipAgentLinux/log/giipAgent3_$(date +%Y%m%d).log

# 오늘 실행된 큐 개수
grep "Downloaded queue" giipAgentLinux/log/giipAgent3_$(date +%Y%m%d).log | wc -l

# 오류 확인
grep -i "error\|fail\|❌" giipAgentLinux/log/giipAgent3_$(date +%Y%m%d).log
```

## 결론

### 현재 상태
- ✅ **giipAgent.sh** (구버전): ASP Classic API 사용, 정상 작동
- ✅ **giipAgent3.sh** (신버전): PowerShell API로 전환, JSON 파싱 로직 추가됨
- ✅ **DB 구조**: tMgmtQue, pApiCQEQueueGetbySK 준비 완료

### 다음 단계
1. `test-cqe-queue.sh` 실행하여 양쪽 API 테스트
2. 테스트 스크립트를 Web UI에서 생성
3. giipAgent3.sh로 실제 실행 테스트
4. 문제 발생 시 위 "문제 해결" 섹션 참고

### 참고 파일
- **Agent 스크립트**: `giipAgentLinux/giipAgent3.sh`
- **테스트 스크립트**: `giipAgentLinux/test-cqe-queue.sh`
- **SP 파일**: `giipdb/SP/pApiCQEQueueGetbySK.sql`
- **테이블 정의**: `giipdb/Tables/tMgmtQue.sql`
- **로그 위치**: `giipAgentLinux/log/giipAgent3_YYYYMMDD.log`
