# Linux Agent MSSQL 모니터링 기능 (2025-12-16)

## 개요
Linux Agent에 Windows Agent(`DbMonitor.ps1` 및 `dpa-put-mssql.ps1`)와 동일한 MSSQL 모니터링 기능을 추가했습니다. 이 모듈은 GIIP API를 통해 등록된 MSSQL 데이터베이스 목록을 동적으로 가져오고, `sqlcmd`를 사용하여 성능 지표를 수집합니다.

## 구현 상세

### 모듈: `lib/mssql.sh`
이 스크립트는 전체 모니터링 워크플로우를 처리합니다:
1.  **주기 확인**: 설정된 주기(기본값: 60초)마다 모니터링이 실행되도록 합니다.
2.  **전제 조건 확인**: `sqlcmd`가 설치되어 있는지 확인합니다. 설치되어 있지 않은 경우 `mssql-tools` 자동 설치를 시도합니다(`lib/common.sh`에 RHEL/CentOS 7 지원 포함).
3.  **대상 검색**:
    *   에이전트 자격 증명(`lssn`, `sk`)을 사용하여 `ManagedDatabaseListForAgent` API를 호출합니다.
    *   JSON 응답을 파싱하여 `db_type = 'MSSQL'`인 데이터베이스를 식별합니다.
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
