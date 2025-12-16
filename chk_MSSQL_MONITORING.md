# Linux Agent MSSQL 모니터링 기능 (2025-12-16)

## 개요
Linux Agent에 Windows Agent(`DbMonitor.ps1` 및 `dpa-put-mssql.ps1`)와 동일한 MSSQL 모니터링 기능을 추가했습니다. 이 모듈은 GIIP API를 통해 등록된 MSSQL 데이터베이스 목록을 동적으로 가져오고, `sqlcmd`를 사용하여 성능 지표를 수집합니다.

## 구현 상세

### 모듈: `lib/mssql.sh`
이 스크립트는 전체 모니터링 워크플로우를 처리합니다:
1.  **주기 확인**: 설정된 주기(기본값: 60초)마다 모니터링이 실행되도록 합니다.
2.  **전제 조건 확인**: `sqlcmd`가 설치되어 있는지 확인합니다. 설치되어 있지 않은 경우 `mssql-tools` 자동 설치를 시도합니다(`lib/common.sh`에 RHEL/CentOS 7 지원 포함).
3.  **대상 검색 (API 호출)**:
    *   **API 명세**: `ManagedDatabaseListForAgent`
    *   **요청 파라미터**:
        *   `text`: "ManagedDatabaseListForAgent lssn" (실행할 명령 및 파라미터 이름)
        *   `token`: 에이전트 인증 토큰 (`sk`)
        *   `jsondata`: `{"lssn": 71174}` (현재 에이전트의 LSSN)
    *   **응답 데이터 (JSON)**: 모니터링 대상 데이터베이스 목록을 반환합니다.
        *   `mdb_id`: 데이터베이스 고유 ID
        *   `db_type`: 데이터베이스 유형 (예: 'MSSQL', 'MySQL') - 본 모듈은 'MSSQL'만 처리
        *   `db_host`: 접속할 DB 서버 주소 (IP 또는 도메인)
        *   `db_port`: 접속 포트 (기본값: 1433)
        *   `db_user`: 접속 계정명
        *   `db_password`: 접속 비밀번호 (복호화된 상태로 전달됨)
    *   `giipAgent.cnf` 파일에 접속 정보를 하드코딩할 필요가 없습니다.
4.  **데이터 수집**:
    *   발견된 각 MSSQL 데이터베이스를 순회합니다.
    *   API에서 제공한 자격 증명(`db_host`, `db_port`, `db_user`, `db_password`)을 사용하여 접속합니다.
    *   T-SQL 쿼리를 실행하여 세션 및 성능 데이터(`sys.dm_exec_requests`, `sys.dm_exec_sessions`)를 수집합니다.
    *   쿼리는 `FOR JSON PATH`를 사용하여 출력을 JSON 형식으로 직접 포맷팅합니다.
5.  **데이터 업로드**:
    *   수집기 메타데이터와 가져온 SQL 데이터를 포함하는 JSON 페이로드를 생성합니다.
    *   `kFactor='sqlnetinv'`로 KVS에 페이로드를 업로드합니다.

### 종속성 관리
*   **`lib/common.sh`**: `check_mssql_tools` 함수 추가.
    *   `sqlcmd` 존재 여부를 확인합니다.
    *   RHEL/CentOS 7에서 패키지가 없는 경우 Microsoft 리포지토리에서 `mssql-tools` 및 `unixODBC-devel` 설치를 시도합니다.
    *   이미 설치된 경우 불필요한 `yum install` 호출을 피하도록 최적화되었습니다.

## 사용법
`giipAgent.cnf`에 DB 연결 문자열을 수동으로 설정할 필요가 **없습니다**.
1.  에이전트가 등록되어 있는지 확인하십시오(`lssn` 설정됨).
2.  `giipAgent3.sh` 또는 `normal_mode.sh` 스크립트가 자동으로 `lib/mssql.sh`를 로드하고 수집 주기를 실행합니다.
3.  대상 데이터베이스는 GIIP 시스템(웹 콘솔)에 등록되어 있어야 하며, 해당 에이전트의 CSN에 할당되어 있어야 합니다.

## 문제 해결
*   **로그**: `log/giipAgent2_YYYYMMDD.log` 파일에서 `[MSSQL]` 태그가 붙은 항목을 확인하십시오.
*   **디버그 모드**: 개발 중 에이전트를 수동으로 실행할 때 즉각적인 확인을 위해 `mssql.sh`가 `stderr`로 주요 단계를 출력합니다.
*   **도구 누락**: `sqlcmd` 자동 설치가 실패할 경우, Linux 호스트에 `mssql-tools`를 수동으로 설치하십시오.

---

## 🛑 개발 히스토리 및 주요 이슈 해결 (Lessons Learned)

본 기능을 개발하는 과정에서 발생한 주요 이슈와 해결 방법을 기록합니다. 추후 유지보수 시 동일한 실수를 반복하지 않기 위함입니다.

### 1. 연결 정보 정적 설정 → 동적 API 전환
*   **초기 시도**: `giipAgent.cnf`에 `SqlConnectionString`을 수동 설정하여 `sqlcmd`를 실행하려 함.
*   **문제**: Windows Agent는 API(`ManagedDatabaseListForAgent`)를 통해 대상을 동적으로 받아옴. Linux Agent만 정적 설정을 쓰면 일관성이 깨지고 관리 포인트가 늘어남.
*   **해결**: `lib/mssql.sh` 내에서 `ManagedDatabaseListForAgent` API를 호출하고, Python으로 JSON 응답을 파싱하여 접속 정보(`HOST`, `PORT`, `USER`, `PASS`)를 추출해 사용하는 방식으로 전면 수정.

### 2. 무한 루프(Infinite Loop) 사건 (DDoS 유사 동작)
*   **발생 상황**: 개발 중 디버깅 편의를 위해 `should_run_mssql` (실행 주기 체크) 함수를 주석 처리하고 배포함.
*   **증상**: `normal_mode.sh` 루프 내에서 차단막 없이 `mssql.sh`가 밀리초 단위로 반복 실행됨. 순식간에 수천 건의 API 요청과 KVS 업로드가 발생하여 서버 부하 유발.
*   **해결**: 
    1.  `should_run_mssql` 체크 로직을 최상단에 **강제 복구**.
    2.  `PROHIBITED_ACTIONS_AGENT.md` 문서 생성하여 "주기 체크 비활성화 금지"를 명문화.

### 3. 프로세스 폭주 (Shell Loop 이슈)
*   **발생 상황**: `while read line; do ... done <<< "$variable"` 구문 사용 시, 변수 내용이 비정상이거나 특수문자가 섞여 쉘이 루프 종료 조건을 제대로 인식하지 못하고 무한 회전.
*   **증상**: API 호출은 멈췄으나 로컬 프로세스가 종료되지 않고 계속 `sleep` 없이 루프를 돎.
*   **해결**: 
    1.  불안정한 "Here String"(`<<<`) 방식 대신, 데이터를 `/tmp/giip_mssql_targets.txt` **임시 파일**에 저장한 후 `while read ... < file` 방식으로 변경하여 안정성 확보.
    2.  `giipAgent3.sh` 시작 시 `pgrep`을 사용하여 이전에 실행된 **자신의 좀비 프로세스를 찾아 강제 종료(Self-Cleanup)** 하는 로직 추가.

### 4. 프로세스 멈춤 (Hang) 현상
*   **발생 상황**: 무한 루프는 해결했으나, 간혹 로그가 멈춘 채 에이전트가 동작하지 않음.
*   **원인**: 네트워크 방화벽 등의 이슈로 `curl`이 API 서버에 접속을 시도하다가 응답을 받지 못하고 무한 대기(Hang) 상태에 빠짐.
*   **해결**: `curl` 명령어에 `--connect-timeout 10` (연결 10초) 및 `--max-time 30` (전체 30초) 옵션을 추가하여, 응답이 없으면 즉시 에러를 뱉고 다음 주기로 넘어가도록 수정.

### 5. "먹통" 오해 방지 로그
*   **상황**: 실행 주기가 도래하지 않아 스크립트가 `return 0`으로 조용히 종료될 때, 사용자 입장에서는 에이전트가 멈춘 것처럼 보임.
*   **해결**: `should_run_mssql` 체크 실패 시(아직 실행 시간이 아닐 때) `[MSSQL] ⏳ Skipping due to interval` 로그를 남겨(주석 처리됨) 동작 중임을 인지할 수 있게 함(필요 시 주석 해제).
