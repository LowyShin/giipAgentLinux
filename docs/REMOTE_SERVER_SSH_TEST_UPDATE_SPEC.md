# 리모트 서버 SSH 접속 테스트 API 사양

> **📅 작성일**: 2025-11-22  
> **버전**: 1.0  
> **목적**: 리모트 서버 SSH 접속 테스트 후 LSChkdt 업데이트

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
  - SP 실행 로그 조회 방법
- **[ERROR_QUICK_REFERENCE.md](../../giipdb/docs/ERROR_QUICK_REFERENCE.md)** - 자주 발생하는 에러

### 🔍 관련 진단 문서
- **[LSChkdt_UPDATE_DIAGNOSIS_CURRENT_STATUS.md](./LSChkdt_UPDATE_DIAGNOSIS_CURRENT_STATUS.md)** ⭐ **현재 상황 분석 (2025-11-22)**
- **[LSChkdt_UPDATE_DIAGNOSIS.md](./LSChkdt_UPDATE_DIAGNOSIS.md)** - 6가지 원인 상세 분석
- **[REMOTE_SERVER_SSH_TEST_DETAILED_SPEC.md](./REMOTE_SERVER_SSH_TEST_DETAILED_SPEC.md)** - 상세 구현 명세

### 🛠️ DB 로그 조사 표준 방법
- **[STANDARD_WORK_PROMPT.md](../../giipdb/docs/STANDARD_WORK_PROMPT.md)** Line 220-280 - 표준 디버깅 3곳 (tLogSP, ErrorLogs, tKVS)
- **[DEBUG_LOGGING_GUIDE.md](../../giipdb/docs/DEBUG_LOGGING_GUIDE.md)** - 자동 로깅 방법론

---

## 📋 목차 & 관련 문서

### 📚 메인 문서 (이 파일)
- **[개요](#개요)** - 목적, 호출자
- **[아키텍처](#아키텍처)** - 시스템 다이어그램
- **[로깅 포인트](#로깅-포인트)** - 28개 로깅 지점
- **[배포 체크리스트](#배포-체크리스트)** - 배포 항목

### 📖 상세 문서

#### 1️⃣ [REMOTE_SERVER_SSH_TEST_DETAILED_SPEC.md](./REMOTE_SERVER_SSH_TEST_DETAILED_SPEC.md)
- API 요청/응답 상세 (40+ 항목)
- Stored Procedure 완전 코드
- DB 스키마 확장
- 에러 처리 (3가지 시나리오)
- KVS 로깅 상세
- 실행 흐름 (2가지 시나리오)
- 향후 확장 계획

#### 2️⃣ [REMOTE_SERVER_SSH_TEST_TROUBLESHOOTING.md](./REMOTE_SERVER_SSH_TEST_TROUBLESHOOTING.md)
- **5가지 원인 분석**: API 실패, SP 미배포, SSH 설정, 컬럼 없음, API 미호출
- **진단 방법**: Agent 로그, KVS 데이터, DB 테이블 확인
- **해결 방법**: 각 원인별 구체적 해결책
- **플로우차트**: 진단 의사결정 트리
- **최종 확인**: 수동 테스트, DB 확인, Web UI 확인

### 🔗 참고 문서

#### 3️⃣ [GIIPAGENT3_SPECIFICATION.md](./GIIPAGENT3_SPECIFICATION.md)
- giipAgent3.sh 모듈 구조
- 로깅 포인트 #5.1-#5.13
- Gateway 모드 실행 흐름

#### 4️⃣ [GATEWAY_AUTO_REFRESH_SPEC.md](./GATEWAY_AUTO_REFRESH_SPEC.md)
- Web UI 자동 새로고침
- 로깅 포인트 #1.4-#1.6
- LSChkdt 갱신 메커니즘

#### 5️⃣ [DEBUG_LOGGING_GUIDE.md](../../giipdb/docs/DEBUG_LOGGING_GUIDE.md)
- 자동 로깅 방법론
- debugLogger 패턴
- PowerShell 디버깅

#### 6️⃣ **🚨 [LSChkdt_UPDATE_DIAGNOSIS_CURRENT_STATUS.md](./LSChkdt_UPDATE_DIAGNOSIS_CURRENT_STATUS.md)** (신규)
- **현재 상황 분석 (2025-11-22)**
- **문제**: lsvrdetail 페이지에서 LSChkdt가 표시 안 됨
- **원인 가설**: API 호출 미실행 (70%), LSChkdt 컬럼 부재 (10%), API 응답 에러 (15%)
- **로깅 포인트별 진단 체크리스트**: Phase 1-4 확인 방법
- **다음 단계**: 직접 확인할 SQL 쿼리 및 스크립트 명령어 제시

#### 6️⃣ [TLOGSP_LOGGING_GUIDE.md](../../giipdb/docs/TLOGSP_LOGGING_GUIDE.md)
- SP 로깅 규칙
- tLogSP 테이블 스키마
- 로깅 포인트 네이밍

---

## 개요

### 목적

**리모트 서버** (Gateway를 경유하는 서버)에 대한 SSH 접속 테스트:
- ✅ Gateway가 리모트 서버에 **실제로 접근 가능**한지 검증
- ✅ 접속 성공/실패, 응답 시간, SSH 인증 방식 기록
- ✅ **LSChkdt (최종 체크 완료 날짜)** 자동 업데이트

### 호출자

1. **Gateway Agent** (`giipAgent3.sh`)
   - 정기적으로 리모트 서버 목록 조회
   - 각 서버에 SSH 테스트 실행
   - 결과를 RemoteServerSSHTest API로 전송

2. **웹 UI** (`lsvrdetail` 페이지)
   - "연결 테스트" 버튼 클릭 시 API 호출
   - 테스트 결과 즉시 표시

3. **정기 모니터링**
   - 주기적으로 리모트 서버 연결 상태 갱신
   - 문제 발생 시 알림

---

## 🚀 자동 진단 스크립트 (신규)

### ✨ 특징

**당신이 할 일 없음** (완전 자동화):
- ❌ 로그 직접 검토 금지
- ❌ DB 쿼리 수동 실행 금지
- ❌ 원인 분석 수동 작업 금지
- ✅ 스크립트 1개만 실행

### 파일

```
giipdb/mgmt/diagnose-remote-server-lschkdt.ps1
```

### 기능

**자동 데이터 수집** (당신이 안 해도 됨):
1. SQL Server 연결 테스트
2. KVS 테이블에서 SSH 테스트 기록 조회 (50개)
3. tLSvr 테이블에서 LSChkdt, gateway_ssh_* 컬럼 확인
4. pApiRemoteServerSSHTestbyAK SP 배포 상태 확인
5. tLSvr 신규 컬럼 (5개) 존재 여부 확인

**자동 원인 분석** (당신이 결정 안 해도 됨):
- #1: API 호출 실패
- #2: SP 미배포
- #3: SSH 설정 불완전
- #4: tLSvr 신규 컬럼 없음
- #5: Agent가 API 안 호출

**자동 해결 방법 제시**:
- 원인별 구체적 해결 명령어
- SQL 스크립트
- PowerShell 수정 스크립트
- 배포 방법

### 사용 방법

```powershell
# 간단하게: 기본값으로 실행 (Gateway LSSN 71174, 리모트 LSSN 71221)
cd c:\Users\lowys\Downloads\projects\giipprj\giipdb
pwsh .\mgmt\diagnose-remote-server-lschkdt.ps1

# 또는: 다른 LSSN으로 진단
pwsh .\mgmt\diagnose-remote-server-lschkdt.ps1 -GatewayLssn 71174 -RemoteLssn 71221

# 또는: 다른 SQL Server로 진단
pwsh .\mgmt\diagnose-remote-server-lschkdt.ps1 -GatewayLssn 71174 -RemoteLssn 71221 -ServerName "192.168.1.10"
```

### 출력 예시

```
════════════════════════════════════════════════════════
  Step 1/4: SQL Server 연결 테스트
════════════════════════════════════════════════════════

  [✅ PASS] SQL Server 연결 성공 localhost\giipdb
  
════════════════════════════════════════════════════════
  Step 2/4: KVS 데이터 수집 (SQL Server)
════════════════════════════════════════════════════════

  [✅ PASS] KVS 기록 조회 성공 (15개 레코드)
  [✅ PASS] SSH 테스트 기록 있음 (3개)
  [✅ PASS] 마지막 테스트: 2025-11-22 15:30:45 UTC
  
════════════════════════════════════════════════════════
  진단 결과 분석
════════════════════════════════════════════════════════

✅ 통과 항목: 8
❌ 실패 항목: 0
⚠️  경고 항목: 0

🔍 진단된 원인: 불명 (모든 항목이 정상입니다)

🎉 진단 완료! 모든 항목이 정상입니다.
```

### 워크플로우

```
1️⃣  진단 실행
    ↓
    pwsh .\mgmt\diagnose-remote-server-lschkdt.ps1
    ↓
    
2️⃣  문제 식별됨?
    ├─ 문제 없음 → 끝
    └─ 문제 있음 → 3️⃣
    
3️⃣  자동 해결 스크립트 실행 (개발 예정)
    ↓
    pwsh .\mgmt\fix-remote-server-lschkdt.ps1
    ↓
    
4️⃣  진단 재실행해서 확인
    ↓
    pwsh .\mgmt\diagnose-remote-server-lschkdt.ps1
    ↓
    
5️⃣  완료 ✅
```

### 참고

- 더 자세한 진단 방법은 [REMOTE_SERVER_SSH_TEST_TROUBLESHOOTING.md](./REMOTE_SERVER_SSH_TEST_TROUBLESHOOTING.md) 참고
- 자동 해결 스크립트 `fix-remote-server-lschkdt.ps1`은 개발 중입니다

---

