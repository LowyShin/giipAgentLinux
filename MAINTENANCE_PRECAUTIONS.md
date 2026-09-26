# giipAgentLinux Maintenance & Development Precautions

이 문서는 `giipAgentLinux`를 유지보수하거나 기능을 확장할 때 반드시 준수해야 하는 기술적 주의사항을 정리한 것입니다. AI 코딩 어시스턴트는 작업 전 이 문서를 반드시 숙지해야 합니다.

## 1. 설정 파일 관리 (giipAgent.cnf)

*   **더미 파일 사용 금지**: 리포지토리 루트(`~/giipAgent/giipAgent.cnf`)에 있는 설정 파일은 **템플릿/더미** 파일입니다. 실제 운영 환경의 비밀 키(sk)와 설정은 이 파일에 저장되지 않습니다.
*   **운영 설정 경로**: 실제 운영 서버에서 사용되는 설정 파일은 항상 **리포지토리 루트의 한 단계 상위 디렉토리**에 위치합니다.
    *   `scripts/` 내 스크립트에서 참조 시: `../../giipAgent.cnf`
    *   루트 스크립트(`giipAgent3.sh` 등)에서 참조 시: `../giipAgent.cnf`
*   **환경 변수 우선순위**: `agent_env.json` 파일이 존재하는 경우 이를 우선적으로 참조하며, 이 역시 운영 환경에서는 상위 디렉토리에 위치할 수 있습니다.
*   **lssn=0 자동등록 사양 (2026-09-24)**:
    *   등록은 `giipAgent3.sh` → `lib/lssn_register.sh` `register_server()` **한 곳에서만** 한다.
        `text=CQEQueueGet lssn hostname os op` + jq 로 만든 `jsondata`(`lssn:0`)를 `curl --data-urlencode` 로 보낸다.
        `text` 에 파라미터명이 없으면 giipApiSk2 가 값을 SP 에 넘기지 않아 `@lsSn=0, @hostname=NULL` 로 실행된다.
    *   응답은 giipApiSk2 JSON(`{"data":[{"RstVal":"201","lssn":N,...}]}`)이다. `RstVal` 200(기존 hostname) /
        201(신규) 이고 `lssn` 이 양의 정수일 때만 성공. plain-text 로 `cat` 해서 읽지 말 것(v2 ASP 시절 방식).
    *   저장은 `lib/common.sh` `persist_lssn()`: `^[[:space:]]*lssn[[:space:]]*=` 줄을 따옴표/공백/CRLF 무관하게
        치환 → 임시파일 → `cat tmp > cnf`(inode 유지) → 재독 검증. **`sed -i`/`mv` 로 cnf 를 교체하지 말 것**
        (Docker 단일파일 bind mount 에서 EBUSY, 그리고 `sed` 는 미매칭이어도 exit 0).
    *   cnf 쓰기 불가 시 같은 디렉토리 `giipAgent.lssn` 사이드카에 기록하고, `load_config()` 는 cnf lssn 이
        0/빈값이면 사이드카의 양의 정수를 쓴다(cnf 값이 있으면 cnf 우선).
    *   등록 실패 시 `giipAgent3.sh` 는 exit 1 — lssn=0 으로 net3d/gateway/normal 모드에 들어가지 않는다.
    *   **CQEQueueGet 을 lssn=0 으로 호출하면 SP 가 tLSvr 에 행을 INSERT 한다.** 그래서 `lib/cqe.sh queue_get()`,
        `scripts/normal_mode.sh`, `cqe/giipCQE.sh` 는 자기 lssn 이 0/비정수면 호출하지 않는다. 새 호출 지점도 같은 가드를 둘 것.
    *   회귀 테스트: `bash tests/test-lssn0-registration.sh` (네트워크 불필요).

## 2. 운영 환경 호환성 (CentOS 7.x 대응)

*   **CentOS 7.x 지원**: 주요 서버인 `cctrank03` (LSSN 71174) 등은 CentOS 7.x 환경입니다. 최신 명령어 옵션이 동작하지 않을 수 있음을 항상 고려해야 합니다.
*   **명령어 결과 파싱 주의**:
    *   `top`, `free`, `df` 등의 명령어는 OS 버전마다 출력 형식이 다를 수 있습니다.
    *   가급적 `/proc/stat`, `/proc/meminfo`, `/proc/net/dev` 등 커널 인터페이스를 직접 읽어 처리하는 것을 권장합니다.
*   **로케일 고정**: 일본어/한국어 환경에서도 파싱 에러가 발생하지 않도록 스크립트 상단에 `export LC_ALL=C` 또는 `export LANG=en_US.UTF-8`을 명시해야 합니다.

## 3. KVS 데이터 표준 준수

*   **RAW JSON 원칙**: `kvs_put`을 통해 전송되는 `kValue`는 항상 **RAW JSON** 객체 형태여야 합니다. 이스케이프된 문자열로 전송하지 마십시오.
*   **라이브러리 활용**: `lib/kvs.sh`에 정의된 `kvs_put()` 함수를 사용하고, 해당 함수의 시그니처나 내부 로직을 사용자 승인 없이 수정하지 마십시오.
*   **팩터 명칭**: 신규 지표 추가 시 기존에 정의된 팩터 명칭과 중복되지 않는지, 그리고 시각화 대시보드 사양과 일치하는지 확인하십시오.

## 4. 프로세스 관리 및 싱글톤

*   **중복 실행 방지**: 주기적으로 실행되는 스크립트는 `pgrep` 등을 사용하여 이전 인스턴스가 실행 중인지 확인해야 합니다.
*   **Stale 프로세스 정리**: 5분(300초) 이상 종료되지 않고 남아있는(hung) 프로세스는 자동으로 정리하는 로직을 포함해야 합니다.

## 5. 보안 및 무결성

*   **비밀 키(sk) 노출 금지**: 로그 파일이나 KVS 전송 데이터에 `sk` 값이 평문으로 노출되지 않도록 주의하십시오.
*   **임시 파일 정리**: `/tmp` 등에 생성하는 임시 파일은 작업 완료 후 반드시 삭제하거나, `cleanup_all_temp_files` 함수를 호출하여 정리하십시오.

## 6. API 호출 실패 보고 원칙 (giip 3079, 2026-09-26)

*   **문제(csn 70418 실측, giipAgentWin에서 발견된 것과 동일 클래스)**: `kvs_put()`(`lib/kvs.sh`)은
    이미 실패 시 0이 아닌 값을 반환하고 `[KVS-Put]` 오류를 stderr에 자체적으로 남기지만, 일부
    호출부가 그 반환값을 확인하지 않고 무조건 "✅ ... uploaded" 성공 메시지를 남기고 있었다
    (예: `scripts/collect_enhanced_metrics.sh`, `scripts/check_agent_health.sh`).
*   **원칙**: `kvs_put`을 호출하는 모든 코드는 종료 코드(`$?` 또는 `kvs_put ... || ...`)를 실제로
    확인한 뒤에만 성공 메시지를 남긴다. 실패 시 `lib/common.sh`의 기존 `log_error()`
    (`ErrorLogCreate` SP 호출 - 이미 이 레포 전역에서 널리 쓰이는 채널)로 giip 서버에도 보고한다.
    `kvs_put()` 자체의 시그니처/내부 로직은 (규칙 3에 따라) 손대지 않는다 - 호출부만 고친다.
*   **잔여 범위**: `kvs_put` 호출부가 레포 전체에 99건(26개 파일, 2026-09-26 실측) 있다. 위 두
    스크립트만 우선 수정했고 나머지 전수 점검은 후속 이슈로 분리했다:
    https://giip.littleworld.net/ko/admin/giip-issues/3081
*   **git pull(자기 업데이트) 독립성**: `admin/giipcronreg.sh`가 `git-auto-sync.sh`를
    `giipAgent3.sh`와 **완전히 별도의 crontab 라인**(둘 다 독립 프로세스)으로 등록하므로, 에이전트
    본 로직이 죽거나 멈춰도 git pull 크론은 영향받지 않는다 - 이미 만족된 상태이며 이번에 코드
    변경은 하지 않았다.

---
**마지막 업데이트**: 2026-09-26
**준수 대상**: 모든 유지보수 개발자 및 AI 어시스턴트
