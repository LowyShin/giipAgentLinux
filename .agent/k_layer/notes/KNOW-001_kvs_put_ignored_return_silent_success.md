# KNOW-001: kvs_put 반환값 미확인 + 무조건 성공 로그 패턴 (giipAgentWin과 동일 클래스)

> 자동 생성: 2026-09-26 | source: giip 3079(csn 70418 실측), giipAgentWin PR #52와 짝

## CLAIM-001

- **주장**: `kvs_put()`(`lib/kvs.sh`)은 이미 실패 시 0이 아닌 값을 반환하고 `[KVS-Put]` 오류를
  stderr에 자체적으로 남기는 잘 설계된 함수지만, 일부 호출부가 그 반환값(`$?`)을 확인하지 않고
  무조건 "✅ ... uploaded" 성공 메시지를 남기고 있었다 - giipAgentWin `Invoke-GiipKvsPut` 호출부
  (`CollectDockerMetrics.ps1` 등)에서 csn 70418이 실측한 것과 정확히 같은 클래스의 버그다.
- **관측**: `scripts/collect_enhanced_metrics.sh`(6개 kvs_put 호출), `scripts/check_agent_health.sh`
  (2개 kvs_put 호출) 2곳에서 확인. 레포 전체 `kvs_put` 호출부는 99건(26개 파일)이라 같은 패턴이
  더 있을 가능성이 높다.
- **source**: giip 3079 작업 세션(2026-09-26)
- **status**: partially resolved (giipAgentLinux PR #42 - 2개 스크립트만 수정, 나머지는
  https://giip.littleworld.net/ko/admin/giip-issues/3081 로 분리)
- **대응책**:
  1. `kvs_put` 호출 후 반드시 종료 코드를 확인한다(`kvs_put ... || upload_failed=1` 패턴).
  2. 실패 시 `lib/common.sh`의 기존 `log_error()`(`ErrorLogCreate` SP - 이 레포 전역에서 이미
     널리 쓰이는 채널)로 giip 서버에도 보고한다.
  3. `kvs_put()` 자체의 시그니처/내부 로직은 `lib/kvs.sh` 상단 "DO NOT MODIFY" 규칙에 따라
     손대지 않는다 - 호출부만 고친다.

## 적용 규칙

- giipAgentLinux에 `kvs_put`을 호출하는 새 코드를 추가하거나 기존 코드를 리뷰할 때 → 반환값을
  실제로 확인하는지 먼저 본다.
- git pull(자기 업데이트) 독립성은 이미 만족돼 있었다: `admin/giipcronreg.sh`가
  `git-auto-sync.sh`를 `giipAgent3.sh`와 완전히 별도의 crontab 라인(독립 프로세스)으로 등록한다.
  giipAgentWin은 같은 프로세스 안에서 순차 실행하는 구조라 별도로 손봤다(giipAgentWin PR #52,
  giipAgentWin KNOW-001 참고).
- 참조: `MAINTENANCE_PRECAUTIONS.md` 섹션 6.
