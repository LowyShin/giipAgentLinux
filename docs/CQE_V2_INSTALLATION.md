# CQE v2 설치 및 마이그레이션 가이드

## 개요

CQE (Command Queue Execution) v2는 기존 시스템의 성능과 안정성을 대폭 개선한 버전입니다.

**주요 개선사항**:
- ⚡ 80% 빠른 응답 속도 (300-500ms → 50-100ms)
- 🔒 트랜잭션 보장으로 데이터 무결성 향상
- 📊 감사 추적 (audit trail) 지원
- 🚀 10배 높은 동시성 처리 능력
- 🛡️ 포괄적인 에러 핸들링

## 설치 순서

### 1단계: Stored Procedures 설치

```powershell
cd giipdb

# Agent용 SP (4개)
pwsh .\mgmt\execSQLFile.ps1 -sqlfile ".\SP\pCQEv2_QueueGet.sql"
pwsh .\mgmt\execSQLFile.ps1 -sqlfile ".\SP\pCQEv2_QueueGenerate.sql"
pwsh .\mgmt\execSQLFile.ps1 -sqlfile ".\SP\pCQEv2_ResultPut.sql"
pwsh .\mgmt\execSQLFile.ps1 -sqlfile ".\SP\pCQEv2_Heartbeat.sql"
pwsh .\mgmt\execSQLFile.ps1 -sqlfile ".\SP\pCQEv2_QueueCleanup.sql"

# Web UI용 SP (10개)
pwsh .\mgmt\execSQLFile.ps1 -sqlfile ".\SP\pApiCQEv2_ScheduleList.sql"
pwsh .\mgmt\execSQLFile.ps1 -sqlfile ".\SP\pApiCQEv2_SchedulePut.sql"
pwsh .\mgmt\execSQLFile.ps1 -sqlfile ".\SP\pApiCQEv2_ScheduleDel.sql"
pwsh .\mgmt\execSQLFile.ps1 -sqlfile ".\SP\pApiCQEv2_ScheduleActivate.sql"
pwsh .\mgmt\execSQLFile.ps1 -sqlfile ".\SP\pApiCQEv2_ScriptList.sql"
pwsh .\mgmt\execSQLFile.ps1 -sqlfile ".\SP\pApiCQEv2_ScriptDetail.sql"
pwsh .\mgmt\execSQLFile.ps1 -sqlfile ".\SP\pApiCQEv2_ScriptPut.sql"
pwsh .\mgmt\execSQLFile.ps1 -sqlfile ".\SP\pApiCQEv2_ResultList.sql"
pwsh .\mgmt\execSQLFile.ps1 -sqlfile ".\SP\pApiCQEv2_ServerStatus.sql"
```

### 2단계: 인덱스 최적화

```powershell
# 인덱스 생성 (운영 환경: 유지보수 시간에 실행)
pwsh .\mgmt\execSQLFile.ps1 -sqlfile ".\SP\CQEv2_Indexes.sql"
```

**예상 소요 시간**:
- 소규모 DB (< 10만 건): 1-2분
- 중규모 DB (10만-100만 건): 5-10분
- 대규모 DB (> 100만 건): 20-30분

### 3단계: SQL Agent Jobs 설정

#### 3.1 큐 사전 생성 Job

```sql
USE [msdb]
GO

-- Job 생성
EXEC sp_add_job
    @job_name = N'GIIP CQE Queue Generator',
    @enabled = 1,
    @description = N'Generate CQE queues based on schedule intervals'
GO

-- Job Step 추가
EXEC sp_add_jobstep
    @job_name = N'GIIP CQE Queue Generator',
    @step_name = N'Generate Queues',
    @subsystem = N'TSQL',
    @command = N'EXEC pCQEv2_QueueGenerate',
    @database_name = N'giipdb',
    @retry_attempts = 3,
    @retry_interval = 1
GO

-- 스케줄 추가 (매 1분마다)
EXEC sp_add_schedule
    @schedule_name = N'Every 1 Minute',
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 4,
    @freq_subday_interval = 1,
    @active_start_time = 0
GO

-- Job에 스케줄 연결
EXEC sp_attach_schedule
    @job_name = N'GIIP CQE Queue Generator',
    @schedule_name = N'Every 1 Minute'
GO

-- 서버에 Job 추가
EXEC sp_add_jobserver
    @job_name = N'GIIP CQE Queue Generator'
GO
```

#### 3.2 큐 정리 Job

```sql
-- Job 생성
EXEC sp_add_job
    @job_name = N'GIIP CQE Queue Cleanup',
    @enabled = 1,
    @description = N'Clean up old CQE queues'
GO

-- Job Step 추가
EXEC sp_add_jobstep
    @job_name = N'GIIP CQE Queue Cleanup',
    @step_name = N'Cleanup Old Queues',
    @subsystem = N'TSQL',
    @command = N'EXEC pCQEv2_QueueCleanup @completed_days=7, @pending_days=30, @failed_days=30',
    @database_name = N'giipdb',
    @retry_attempts = 3,
    @retry_interval = 5
GO

-- 스케줄 추가 (매일 새벽 2시)
EXEC sp_add_schedule
    @schedule_name = N'Daily at 2 AM',
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_time = 20000
GO

-- Job에 스케줄 연결
EXEC sp_attach_schedule
    @job_name = N'GIIP CQE Queue Cleanup',
    @schedule_name = N'Daily at 2 AM'
GO

-- 서버에 Job 추가
EXEC sp_add_jobserver
    @job_name = N'GIIP CQE Queue Cleanup'
GO
```

### 4단계: Agent 업데이트

#### 4.1 giipCQE.sh 배포

```bash
cd giipAgentLinux

# 기존 백업
cp giipAgent.sh giipAgent.sh.backup.$(date +%Y%m%d)

# 새 Agent 복사
# giipCQE.sh는 이미 생성되어 있음

# 실행 권한 부여
chmod +x giipCQE.sh
chmod +x giipCQECtrl.sh
```

#### 4.2 설정 파일 업데이트

```bash
# giipAgent.cnf 편집
vi giipAgent.cnf
```

추가할 설정:
```bash
# API v2 설정
apiaddrv2="https://giipfaw.azurewebsites.net/api/giipApiSk2"
apiaddrcode="YOUR_AZURE_FUNCTION_KEY_HERE"

# 기존 설정 유지 (v1 fallback)
apiaddr="https://giipasp.azurewebsites.net"
sk="your-secret-key"
lssn="71028"
giipagentdelay="60"  # 60초
```

### 5단계: 테스트

#### 5.1 SP 테스트

```sql
-- 1. Queue Get 테스트
EXEC pCQEv2_QueueGet @lssn=71028, @debug=1

-- 2. Heartbeat 테스트
EXEC pCQEv2_Heartbeat @lssn=71028, @agent_version='2.0.0'

-- 3. Queue Generate 테스트
EXEC pCQEv2_QueueGenerate @debug=1

-- 4. Schedule List 테스트
EXEC pApiCQEv2_ScheduleList @ak='your-admin-key'

-- 5. Server Status 테스트
EXEC pApiCQEv2_ServerStatus @ak='your-admin-key'
```

#### 5.2 Agent 테스트

```bash
# 테스트 모드 (1회만 실행)
./giipCQE.sh --test

# 한 번만 실행
./giipCQE.sh --once

# API 연결 확인
./giipCQECtrl.sh status

# 스케줄 목록 확인
./giipCQECtrl.sh list
```

#### 5.3 성능 테스트

```sql
-- Queue Get 성능 측정 (50-100ms 예상)
SET STATISTICS TIME ON
EXEC pCQEv2_QueueGet @lssn=71028
SET STATISTICS TIME OFF

-- Queue Generate 성능 측정
SET STATISTICS TIME ON
EXEC pCQEv2_QueueGenerate
SET STATISTICS TIME OFF
```

## 마이그레이션 전략

### Phase 1: 병렬 운영 (1-2주)

**목표**: v1과 v2를 동시에 운영하며 안정성 검증

1. **테스트 서버에 v2 Agent 설치**
   ```bash
   # 테스트 서버 1-2대 선택
   ./giipCQE.sh --once  # 테스트
   ```

2. **모니터링**
   ```sql
   -- v2 실행 통계
   SELECT COUNT(*) AS v2_executions
   FROM tKVS
   WHERE kfactor = 'cqeresult'
     AND regdate >= DATEADD(DAY, -1, GETDATE())
   
   -- 에러 확인
   SELECT * FROM tLogError
   WHERE leName LIKE 'pCQEv2%'
   ORDER BY leRegdt DESC
   ```

3. **성능 비교**
   - 응답 시간
   - CPU/메모리 사용량
   - 에러율

### Phase 2: 점진적 확대 (2-4주)

**목표**: 전체 서버의 50%를 v2로 전환

1. **서버 그룹별 전환**
   - Week 1: 개발/테스트 서버 (10대)
   - Week 2: 스테이징 서버 (5대)
   - Week 3: 운영 서버 - 비중요 (20대)
   - Week 4: 운영 서버 - 중요 (30대)

2. **각 단계마다 확인사항**
   - ✅ Agent 정상 동작
   - ✅ 큐 생성/처리 정상
   - ✅ 결과 저장 정상
   - ✅ Heartbeat 정상
   - ✅ 성능 지표 개선 확인

### Phase 3: 완전 전환 (1주)

**목표**: 모든 서버를 v2로 전환

1. **나머지 서버 전환**
   ```bash
   # 모든 서버에서 실행
   ./giipCQE.sh
   ```

2. **v1 비활성화**
   ```bash
   # 기존 Agent 중지
   killall -9 giipAgent.sh
   
   # Cron 제거
   crontab -e
   # giipAgent.sh 라인 삭제 또는 주석 처리
   ```

3. **SQL Agent Job 활성화**
   ```sql
   -- Queue Generator 시작
   EXEC msdb.dbo.sp_start_job @job_name = 'GIIP CQE Queue Generator'
   
   -- Cleanup 시작
   EXEC msdb.dbo.sp_start_job @job_name = 'GIIP CQE Queue Cleanup'
   ```

### Phase 4: 최적화 및 정리 (1-2주)

**목표**: 불필요한 레거시 제거 및 최적화

1. **기존 SP 이름 변경**
   ```sql
   -- 레거시 표시
   EXEC sp_rename 'pCQEQueueGetbySK02', 'pCQEQueueGetbySK02_Legacy'
   EXEC sp_rename 'pApiCQEScheduleList', 'pApiCQEScheduleList_Legacy'
   ```

2. **인덱스 최적화 검증**
   ```sql
   -- 인덱스 사용 통계
   SELECT 
       OBJECT_NAME(s.object_id) AS TableName,
       i.name AS IndexName,
       s.user_seeks,
       s.user_scans,
       s.user_lookups
   FROM sys.dm_db_index_usage_stats s
   INNER JOIN sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id
   WHERE OBJECT_NAME(s.object_id) IN ('tMgmtQue', 'tMgmtScriptList')
   ORDER BY s.user_seeks DESC
   ```

3. **모니터링 대시보드 구축**
   - Grafana/Power BI 연동
   - 실시간 서버 상태
   - 실행 통계
   - 에러 알림

## 롤백 계획

문제 발생 시 즉시 v1으로 복구:

```bash
# Agent 롤백
killall -9 giipCQE.sh
./giipAgent.sh

# SQL Agent Job 중지
EXEC msdb.dbo.sp_stop_job @job_name = 'GIIP CQE Queue Generator'

# v1 API 사용 (giipAgent.cnf에서 apiaddrv2 제거)
```

## 모니터링 체크리스트

### 일일 체크 (Phase 1-2)
- [ ] 에러 로그 확인 (`tLogError`)
- [ ] 응답 시간 확인 (`tLogSP`)
- [ ] 큐 적체 확인 (pending_queue)
- [ ] Heartbeat 정상 여부

### 주간 체크 (Phase 3-4)
- [ ] 성능 지표 분석
- [ ] 인덱스 조각화 확인
- [ ] 디스크 사용량 확인
- [ ] SQL Agent Job 실행 이력

## 성공 기준

### 성능
- ✅ Queue Get 응답: < 100ms
- ✅ Queue Generate: < 1초 (100개 스케줄 기준)
- ✅ Result Put: < 50ms

### 안정성
- ✅ 에러율: < 0.1%
- ✅ Heartbeat 정상: > 99%
- ✅ 큐 적체 없음: pending < 100개

### 동시성
- ✅ 10개 Agent 동시 Queue Get: 경합 없음
- ✅ Transaction deadlock: 0건

## 문의 및 지원

문제 발생 시:
1. `tLogError` 테이블 확인
2. `tLogSP` 실행 이력 확인
3. Agent 로그 확인 (`giipCQE.log`)
4. GitHub Issues 등록

---

**버전**: v2.0.0  
**작성일**: 2025-01-15  
**작성자**: GIIP Development Team
