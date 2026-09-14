#!/bin/bash
#
# lib/scheduler_agent_register.sh - giip #2477 (csn=47)
#
# 목적:
#   1) tSchedulerAgent 등록(부트스트랩)의 단일 정본. 기존에는 이 로직이
#      lib/log_collector.sh 의 bootstrap_scheduler_agent() 안에만 있었고,
#      giipAgent3.sh 는 log_collector.sh 를 source 하지도 않았다.
#   2) giipApiSk2 디스패처의 "jsondata 자동추가(ISN 161)" 함정을 회피하는
#      SQL 리터럴 조립 헬퍼(sar_reg_sql_literal).
#   3) 미등록/실패 상태에서 서버 ErrorLogs 가 5분마다 영구히 쌓이는 것을
#      억제하는 실패 상태 추적 + 백오프.
#
# 배경 (giip #2477 장애, cctrank03 / lssn 71174 / csn 47):
#   giip #2390(커밋 3e635fce, 2026-09-13 04:23:40 UTC)이 giipAgent3.sh 에
#   lib/scheduler_agent_run.sh 의 sar_run_start / sar_run_end_trap 호출을
#   추가했다. 그런데
#     (a) tSchedulerAgent 행을 실제로 만드는 부트스트랩
#         (pApiSchedulerAgentUpsertBySK 호출)은 lib/log_collector.sh 안에만
#         있었고 giipAgent3.sh 는 그 파일을 source 하지 않으며,
#     (b) RunStart 호출이 text=파라미터이름 + jsondata=JSON 형태라
#         디스패처가 JSON 을 한 개 더 위치파라미터로 자동 추가해
#         @totalIssueCount INT 자리에 넣어 버렸다.
#   결과: 2026-09-13 04:30:02 UTC 부터 5분마다
#   "Error converting data type nvarchar to int" 가 쌓였다(8일 312건).
#
#   (a)는 자매 저장소 giipAgentWin 의 giip #2470(giipAgent3.ps1 ↔
#   lib/LogCollector.ps1)과 완전히 동일한 구조적 결함이며, 이 파일은 그
#   해법(lib/SchedulerAgentRegister.ps1, giipAgentWin PR #40)의 Linux 대칭
#   구현이다.
#
# ⚠️ giipApiSk2 디스패처(giipfaw/giipApiSk2/run.ps1) 계약 요약 - 이 파일과
#    lib/scheduler_agent_run.sh 를 고칠 때 반드시 지킬 것:
#   1) text 는 공백으로 토큰화되되, 작은따옴표로 감싼 토큰은 통째로 1개
#      토큰이다(정규식 `("[^"]*"|'[^']*'|\S+)`, L132). 따라서 값에 공백이
#      있어도 '...' 로 감싸면 안전하다.
#   2) 토큰은 SP 선언 순서 그대로 이름 없는(unnamed) 위치 파라미터가 된다.
#      중간을 건너뛸 수 없다. 숫자로만 이뤄진 값은 따옴표 없이(INT 로),
#      나머지는 N'...' 로 붙는다(L240-282).
#   3) **jsondata 가 비어있지 않으면** 디스패처가 원본 JSON 전체를 마지막
#      파라미터 뒤에 하나 더 자동 추가한다(L394-400, "ISN 161"). 이 추가는
#      앞에서 치환이 이미 끝났는지와 무관하게 무조건 일어나며, SP 이름에
#      Get/List 가 없고 KVSPut 도 아니면 예외가 없다.
#      => 값을 text 에 SQL 리터럴로 직접 박고 **jsondata 는 빈 문자열로**
#         보내는 것이 유일한 회피책이다(빈 문자열이면 falsy 로 판정돼
#         치환/자동추가 로직 전체가 꺼진다).
#
# 의존성: curl, jq. 전역 설정값 sk / apiaddrv2 / lssn / agent_name.
# 이 파일은 source 전용이며 source 시점에 부작용(네트워크/파일쓰기)이 없다.
#

# ----------------------------------------------------------------------------
# 로깅 - 호출자 컨텍스트에 맞춰 자동 선택(giipAgent3.sh=log_message,
# log_collector.sh=log, 그 외=stderr).
# ----------------------------------------------------------------------------
sar_reg_log() {
    local level="${1:-INFO}"
    shift || true
    if command -v log_message >/dev/null 2>&1; then
        log_message "$level" "[scheduler_agent_register] $*"
    elif command -v log >/dev/null 2>&1; then
        log "${level}: [scheduler_agent_register] $*"
    else
        echo "[scheduler_agent_register] ${level}: $*" >&2
    fi
}

# ----------------------------------------------------------------------------
# sar_reg_sql_literal <value>
#   디스패처 text 토큰으로 안전한 SQL 리터럴을 만든다.
#   giipAgentWin lib/Common.ps1 의 ConvertTo-DispatcherSqlLiteral 과 동일 규칙:
#     - 작은따옴표는 **제거**한다(이스케이프가 아니라 제거 - 토큰 경계가
#       작은따옴표라서 값 안에 남으면 토큰이 잘린다).
#     - CR/LF 는 공백으로 바꾼다(text 는 한 줄이어야 한다).
#   stdout: '<cleaned>'
# ----------------------------------------------------------------------------
sar_reg_sql_literal() {
    local v="${1-}"
    v="${v//\'/}"
    v="$(printf '%s' "$v" | tr '\r\n' '  ')"
    printf "'%s'" "$v"
}

# ----------------------------------------------------------------------------
# apiaddrv2 에 SK 인증으로 POST 하되 **jsondata 를 항상 비워** 보낸다.
# stdout: 응답 본문. 반환값은 curl 자체의 성공/실패이며 RstVal 판정은 호출부 책임.
# ----------------------------------------------------------------------------
sar_reg_api_post() {
    local sp_text="$1"
    curl -sS --max-time 15 --connect-timeout 5 -X POST "${apiaddrv2}" \
        --data-urlencode "text=${sp_text}" \
        --data-urlencode "token=${sk}" \
        --data-urlencode "jsondata=" \
        2>&1
}

# ============================================================================
# 실패 상태 추적 + 백오프
# ============================================================================

# 상태파일 경로. 테스트는 SAR_REG_STATE_PATH_OVERRIDE 로 샌드박스를 지정한다.
# 기본 위치는 agentKey 캐시(.giip_logcollector_agentkey)와 같은 INSTALL_DIR.
sar_reg_state_path() {
    if [ -n "${SAR_REG_STATE_PATH_OVERRIDE:-}" ]; then
        printf '%s' "$SAR_REG_STATE_PATH_OVERRIDE"
        return 0
    fi
    local script_dir repo_dir install_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    repo_dir="$(dirname "$script_dir")"
    install_dir="$(dirname "$repo_dir")"
    printf '%s' "${install_dir}/.giip_scheduler_agent_state.json"
}

# 연속 실패 n회 -> 다음 재시도까지 기다릴 분.
# cron 트리거가 5분이므로 5분 미만은 의미가 없다. 5/10/20/40/60(상한) 으로
# 늘려 최악의 경우에도 서버 에러 기록이 시간당 12건 -> 1건 수준이 된다.
# ⚠️ 0 을 반환하지 않는다(n>=1 에서). 억제하더라도 백오프 창이 끝나면 반드시
#    다시 시도해서, 등록이 뒤늦게 이뤄지면 스스로 정상 복귀하게 한다(자가치유).
sar_reg_backoff_minutes() {
    local n="${1:-0}"
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    if [ "$n" -le 0 ]; then
        printf '0'
        return 0
    fi
    local e=$(( n - 1 ))
    [ "$e" -gt 4 ] && e=4
    local m=5 i=0
    while [ "$i" -lt "$e" ]; do
        m=$(( m * 2 ))
        i=$(( i + 1 ))
    done
    [ "$m" -gt 60 ] && m=60
    printf '%s' "$m"
}

# 상태파일에서 필드 1개를 읽는다. 파일이 없거나 JSON 이 깨졌으면 기본값.
sar_reg_state_get() {
    local path="$1" field="$2" def="${3:-}"
    local v=""
    if [ -f "$path" ]; then
        v="$(jq -r --arg f "$field" '.[$f] // empty' "$path" 2>/dev/null)" || v=""
    fi
    [ -z "$v" ] && v="$def"
    printf '%s' "$v"
}

# epoch -> ISO8601 UTC (로그 가독성용. 실패해도 치명적이지 않다)
sar_reg_epoch_to_utc() {
    local e="${1:-0}"
    date -u -d "@${e}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -r "${e}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || printf ''
}

# 실패 1건 기록 + 다음 재시도 시각 계산.
# firstSeenUtc(첫 발생)와 totalCount(누적)는 절대 리셋하지 않는다 - "억제는
# 하되 조용히 버리지는 않는다".
sar_reg_add_failure() {
    local reason="${1:-unknown}"
    local path now_epoch first total consec wait_min next_epoch next_utc tmp
    path="$(sar_reg_state_path)"
    now_epoch="$(date -u +%s 2>/dev/null || echo 0)"

    first="$(sar_reg_state_get "$path" firstSeenUtc "")"
    total="$(sar_reg_state_get "$path" totalCount 0)"
    consec="$(sar_reg_state_get "$path" consecutiveCount 0)"
    case "$total" in ''|*[!0-9]*) total=0 ;; esac
    case "$consec" in ''|*[!0-9]*) consec=0 ;; esac
    [ -z "$first" ] && first="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

    total=$(( total + 1 ))
    consec=$(( consec + 1 ))
    wait_min="$(sar_reg_backoff_minutes "$consec")"
    next_epoch=$(( now_epoch + wait_min * 60 ))
    next_utc="$(sar_reg_epoch_to_utc "$next_epoch")"

    tmp="${path}.tmp.$$"
    if jq -n \
        --arg firstSeenUtc "$first" \
        --argjson totalCount "$total" \
        --argjson consecutiveCount "$consec" \
        --argjson nextAttemptEpoch "$next_epoch" \
        --arg nextAttemptUtc "$next_utc" \
        --arg lastReason "$reason" \
        '{firstSeenUtc:$firstSeenUtc, totalCount:$totalCount, consecutiveCount:$consecutiveCount,
          nextAttemptEpoch:$nextAttemptEpoch, nextAttemptUtc:$nextAttemptUtc, lastReason:$lastReason}' \
        > "$tmp" 2>/dev/null && mv -f "$tmp" "$path" 2>/dev/null; then
        :
    else
        rm -f "$tmp" 2>/dev/null
        sar_reg_log "WARN" "state save failed ($path)"
    fi

    sar_reg_log "WARN" "registration failure recorded: reason=${reason} firstSeenUtc=${first} totalCount=${total} consecutive=${consec} nextAttemptUtc=${next_utc}"
    return 0
}

# 정상 복귀 시 호출. 백오프는 풀되 통계(firstSeenUtc/totalCount)는 남긴다.
sar_reg_clear_backoff() {
    local path first total tmp
    path="$(sar_reg_state_path)"
    [ -f "$path" ] || return 0
    first="$(sar_reg_state_get "$path" firstSeenUtc "")"
    total="$(sar_reg_state_get "$path" totalCount 0)"
    case "$total" in ''|*[!0-9]*) total=0 ;; esac
    if [ -z "$first" ] && [ "$total" -le 0 ]; then
        return 0
    fi
    tmp="${path}.tmp.$$"
    if jq -n \
        --arg firstSeenUtc "$first" \
        --argjson totalCount "$total" \
        '{firstSeenUtc:$firstSeenUtc, totalCount:$totalCount, consecutiveCount:0,
          nextAttemptEpoch:0, nextAttemptUtc:"", lastReason:"recovered"}' \
        > "$tmp" 2>/dev/null && mv -f "$tmp" "$path" 2>/dev/null; then
        return 0
    fi
    rm -f "$tmp" 2>/dev/null
    sar_reg_log "WARN" "state save failed on recover ($path)"
    return 0
}

# 백오프 창 안이면 0(true) - 이번 tick 은 API 호출 자체를 건너뛴다.
sar_reg_backoff_active() {
    local path next now first total
    path="$(sar_reg_state_path)"
    [ -f "$path" ] || return 1
    next="$(sar_reg_state_get "$path" nextAttemptEpoch 0)"
    case "$next" in ''|*[!0-9]*) return 1 ;; esac
    [ "$next" -le 0 ] && return 1
    now="$(date -u +%s 2>/dev/null || echo 0)"
    if [ "$now" -lt "$next" ]; then
        first="$(sar_reg_state_get "$path" firstSeenUtc "")"
        total="$(sar_reg_state_get "$path" totalCount 0)"
        sar_reg_log "INFO" "backoff active - skipping this run (firstSeenUtc=${first} totalCount=${total} nextAttemptUtc=$(sar_reg_state_get "$path" nextAttemptUtc "")). Log flood suppressed; first-seen and cumulative count are preserved."
        return 0
    fi
    return 1
}

# ============================================================================
# sar_reg_upsert <agentKey>
#   pApiSchedulerAgentUpsertBySK 호출. lib/log_collector.sh 의
#   bootstrap_scheduler_agent() 에 있던 구현을 옮겨 온 정본이다.
#
#   ⚠️ 값 순서는 SP 선언 순서(@agentKey, @displayName, @hostIdentifier,
#      @windowsTaskName, @projectName, @scheduleDesc, @isActive, @lssn,
#      @osType, @agentType, ...)를 그대로 따른다. unnamed EXEC 라 중간을
#      건너뛸 수 없으므로 lssn/osType/agentType 앞의 값들도 전부 채운다.
#      순서를 바꾸지 말 것.
#   ⚠️ jsondata 는 항상 비워 보낸다(파일 상단 계약 3번).
#      과거 구현은 jsondata 를 채워 보내서, 디스패처가 JSON 전체를 12번째
#      위치 파라미터(@version VARCHAR(50))에 자동으로 덧붙이고 있었다.
#
#   SP 는 csn+agentKey 기준 idempotent upsert 이므로 이번 tick 실패는
#   다음 tick 에서 안전하게 재시도된다.
# ============================================================================
sar_reg_upsert() {
    local agent_key="${1:-}"
    local display_name host_identifier lssn_val cmd_text resp

    if [ -z "$agent_key" ]; then
        sar_reg_log "WARN" "sar_reg_upsert called without agentKey"
        return 1
    fi
    if [ -z "${sk:-}" ] || [ -z "${apiaddrv2:-}" ]; then
        sar_reg_log "WARN" "sk/apiaddrv2 not set - skipping tSchedulerAgent upsert"
        return 1
    fi

    display_name="${agent_name:-giipAgentLinux-$(hostname 2>/dev/null || echo unknown-host)}"
    host_identifier="$(hostname 2>/dev/null || echo unknown-host)"
    lssn_val="${lssn:-0}"
    case "$lssn_val" in ''|*[!0-9]*) lssn_val=0 ;; esac

    cmd_text="SchedulerAgentUpsert"
    cmd_text="${cmd_text} $(sar_reg_sql_literal "$agent_key")"        # @agentKey
    cmd_text="${cmd_text} $(sar_reg_sql_literal "$display_name")"     # @displayName
    cmd_text="${cmd_text} $(sar_reg_sql_literal "$host_identifier")"  # @hostIdentifier
    cmd_text="${cmd_text} $(sar_reg_sql_literal "")"                  # @windowsTaskName (Linux 해당 없음)
    cmd_text="${cmd_text} $(sar_reg_sql_literal "")"                  # @projectName
    cmd_text="${cmd_text} $(sar_reg_sql_literal "")"                  # @scheduleDesc
    cmd_text="${cmd_text} $(sar_reg_sql_literal "1")"                 # @isActive
    cmd_text="${cmd_text} $(sar_reg_sql_literal "$lssn_val")"         # @lssn
    cmd_text="${cmd_text} $(sar_reg_sql_literal "Linux")"             # @osType
    cmd_text="${cmd_text} $(sar_reg_sql_literal "giipAgentLinux")"    # @agentType

    resp="$(sar_reg_api_post "$cmd_text")"
    if echo "$resp" | jq -e '.data[0].RstVal == 200' >/dev/null 2>&1; then
        sar_reg_log "INFO" "SchedulerAgentUpsert OK agentKey=${agent_key} lssn=${lssn_val}"
        return 0
    fi
    sar_reg_log "WARN" "SchedulerAgentUpsert non-200 agentKey=${agent_key} resp=${resp}"
    return 1
}
