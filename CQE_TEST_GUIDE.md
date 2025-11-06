# CQE (Command Queue Executor) 테스트 및 문제 해결 가이드

## 개요
- **테스트 일시**: 2025-01-04
- **목적**: giipAgent.sh/giipAgent2.sh의 CQE 큐 가져오기 기능 검증
- **핵심 테이블**: `tMgmtQue` (관리 작업 큐)
- **핵심 SP**: `pApiCQEQueueGetbySK`

## CQE 시스템 구조

### 1. 데이터 흐름
```
[Web UI: CQE 관리]
    ↓ (스크립트 등록)
[tMgmtScriptList] → (스케줄 체크) → [tMgmtQue]
    ↓
[giipAgent.sh 호출]
    ↓
[API 엔드포인트]
    ↓ (pApiCQEQueueGetbySK 실행)
[스크립트 반환 (ms_body)]
    ↓
[Agent가 스크립트 실행]
    ↓
[send_flag = 1 업데이트]
```

### 2. 테이블 구조

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

### 신 버전 (giipAgent2.sh)
```bash
# POST 방식
wget -O "$output_file" \
    --post-data="text=CQEQueueGet ${lssn} ${hostname} ${os} op&token=${sk}" \
    --header="Content-Type: application/x-www-form-urlencoded" \
    "${apiaddrv2}?code=${apiaddrcode}"

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
- **상태**: ⚠️ 수정 필요 (JSON 파싱 로직 추가됨)

## 변경 사항 (giipAgent2.sh)

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
- **신버전**: `giipAgent2_$Today.log`

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
# giipAgent2.sh 실행 (테스트 모드)
cd giipAgentLinux
chmod +x giipAgent2.sh

# 한 번만 실행하고 종료
./giipAgent2.sh

# 로그 확인
tail -f log/giipAgent2_$(date +%Y%m%d).log
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
- [ ] giipAgent2.sh 실행 → 큐 가져오기 성공
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
tail -f giipAgentLinux/log/giipAgent2_$(date +%Y%m%d).log

# 오늘 실행된 큐 개수
grep "Downloaded queue" giipAgentLinux/log/giipAgent2_$(date +%Y%m%d).log | wc -l

# 오류 확인
grep -i "error\|fail\|❌" giipAgentLinux/log/giipAgent2_$(date +%Y%m%d).log
```

## 결론

### 현재 상태
- ✅ **giipAgent.sh** (구버전): ASP Classic API 사용, 정상 작동
- ⚠️ **giipAgent2.sh** (신버전): PowerShell API로 전환, JSON 파싱 로직 추가됨
- ✅ **DB 구조**: tMgmtQue, pApiCQEQueueGetbySK 준비 완료

### 다음 단계
1. `test-cqe-queue.sh` 실행하여 양쪽 API 테스트
2. 테스트 스크립트를 Web UI에서 생성
3. giipAgent2.sh로 실제 실행 테스트
4. 문제 발생 시 위 "문제 해결" 섹션 참고

### 참고 파일
- **Agent 스크립트**: `giipAgentLinux/giipAgent2.sh`
- **테스트 스크립트**: `giipAgentLinux/test-cqe-queue.sh`
- **SP 파일**: `giipdb/SP/pApiCQEQueueGetbySK.sql`
- **테이블 정의**: `giipdb/Tables/tMgmtQue.sql`
- **로그 위치**: `giipAgentLinux/log/giipAgent2_YYYYMMDD.log`
