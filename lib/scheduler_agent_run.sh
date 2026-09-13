#!/bin/bash
#
# lib/scheduler_agent_run.sh - giip #2390 (csn=47)
#
# 목적:
#   tSchedulerAgentRun 테이블에 "이 스케줄러(cron)가 언제 시작해서 언제 어떤 결과로
#   끝났는지" 1회 실행 단위 이력을 남긴다. giipdb SP pApiSchedulerAgentRunStartBySK /
#   pApiSchedulerAgentRunEndBySK(giip #1558로 이미 배포됨)를 호출한다. 두 SP 모두
#   csn+agentKey 기준으로 tSchedulerAgent 행을 조회하므로, 그 행이 먼저 존재해야
#   한다 - lib/log_collector.sh의 bootstrap_scheduler_agent()가 그 등록(upsert)을
#   이미 담당하고 있다. 자매 저장소 giipAgentWin(별도 giip #2390 작업, LogCollector.ps1)
#   의 대칭 구현이다.
#
# 사용법 (giipAgent3.sh에서 config 로드 + check_jq 이후에 source):
#   . "${LIB_DIR}/scheduler_agent_run.sh"
#   sar_run_start "scheduled"       # 실제 작업 시작 직전 1회
#   trap 'sar_run_end_trap' EXIT    # 스크립트 종료 시(성공/실패 모두) run end 자동 기록
#
# 설계 원칙:
#   - API 호출 실패가 본 실행(giipAgent3.sh의 실제 수집/보고 작업)에 영향을 주면 안
#     된다 - 모든 실패는 WARN 로그만 남기고 return 1로 조용히 넘어간다. 이 파일
#     안에서는 exit를 호출하지 않는다.
#   - 이 파일은 giipAgent3.sh 등 호출자 스크립트에 source되므로 set -e/-u/shopt 등
#     셸 옵션을 여기서 바꾸지 않는다 - 바꾸면 호출자 전체의 동작이 달라질 위험이
#     있다(giipAgent3.sh 핵심 실행 흐름 불가침 원칙).
#   - agentKey는 lib/log_collector.sh의 resolve_agent_key()와 동일한 결정론적 생성
#     규칙(설정값 logcollector_agentkey > 캐시파일 > hostname+/etc/machine-id)을 쓰고,
#     같은 캐시 파일 경로(INSTALL_DIR/.giip_logcollector_agentkey)를 공유한다 - 두
#     스크립트 중 어느 쪽이 먼저 실행되어도 같은 Box에 대해 항상 같은 agentKey로
#     수렴하게 하기 위함이다(같은 tSchedulerAgent 행을 가리켜야 하므로).
#   - pApiSchedulerAgentRunStartBySK/RunEndBySK는 giipfaw/giipApiSk2 디스패처가 순수
#     위치기반이라는 제약(lib/log_collector.sh의 bootstrap_scheduler_agent 주석 참고)
#     에 걸리지 않는다 - 우리가 생략하는 파라미터(totalIssueCount, processedCount 등
#     일부, summary)가 전부 SP 선언 순서상 "끝쪽" 옵션 파라미터라 중간을 건너뛸 필요가
#     없기 때문이다.

sar_deps_ok() {
    command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1
}

sar_log_warn() {
    if command -v log_message >/dev/null 2>&1; then
        log_message "WARN" "[scheduler_agent_run] $*"
    else
        echo "[scheduler_agent_run] WARN: $*" >&2
    fi
}

sar_log_info() {
    if command -v log_message >/dev/null 2>&1; then
        log_message "INFO" "[scheduler_agent_run] $*"
    else
        echo "[scheduler_agent_run] INFO: $*" >&2
    fi
}

# lib/log_collector.sh의 resolve_agent_key()와 동일 규칙 + 동일 캐시 파일 경로를
# 사용해, 두 스크립트가 항상 같은 agentKey로 수렴하도록 한다.
sar_resolve_agent_key() {
    local script_dir repo_dir install_dir cache_file
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    repo_dir="$(dirname "$script_dir")"
    install_dir="$(dirname "$repo_dir")"
    cache_file="${install_dir}/.giip_logcollector_agentkey"

    if [ -n "${logcollector_agentkey:-}" ]; then
        printf '%s' "$logcollector_agentkey"
        return 0
    fi
    if [ -f "$cache_file" ]; then
        cat "$cache_file"
        return 0
    fi
    local key hn
    hn="$(hostname 2>/dev/null || echo unknown-host)"
    if [ -r /etc/machine-id ]; then
        key="${hn}-$(cut -c1-12 /etc/machine-id)"
    else
        key="${hn}-$(date +%s%N 2>/dev/null || date +%s)-$$"
        key="${key:0:60}"
    fi
    echo "$key" > "$cache_file" 2>/dev/null
    printf '%s' "$key"
}

# apiaddrv2(giipApiSk2)에 SK 인증으로 POST. stdout으로 응답 본문을 그대로 출력한다.
# 반환값은 curl 자체의 성공/실패(0/!=0)이며, API 레벨 RstVal 판정은 호출부 책임이다.
sar_api_post() {
    local sp_text="$1" jsondata="$2"
    curl -sS --max-time 15 --connect-timeout 5 -X POST "${apiaddrv2}" \
        --data-urlencode "text=${sp_text}" \
        --data-urlencode "token=${sk}" \
        --data-urlencode "jsondata=${jsondata}" \
        2>&1
}

# stdout: 이번 실행에 쓸 고유 run 식별자(UTC 타임스탬프 + PID, runIdKey 멱등키로 사용)
sar_new_run_id_key() {
    local ts
    ts="$(date -u +%Y%m%dT%H%M%S 2>/dev/null || date +%s)"
    printf '%s-%s' "$ts" "$$"
}

# 이번 프로세스 실행 전체에서 재사용할 상태(전역 변수) - sar_run_end/trap에서 읽는다.
SAR_STARTED=0
SAR_AGENT_KEY=""
SAR_RUN_ID_KEY=""

# 실행 시작 기록. 실패해도 본 실행은 계속 진행된다(WARN만 남김).
# Usage: sar_run_start <executionMode: scheduled|manual>
sar_run_start() {
    local execution_mode="${1:-scheduled}"

    if [ -z "${sk:-}" ] || [ -z "${apiaddrv2:-}" ]; then
        sar_log_warn "sk/apiaddrv2 not set - skipping run start tracking"
        return 1
    fi
    if ! sar_deps_ok; then
        sar_log_warn "curl/jq not available - skipping run start tracking"
        return 1
    fi

    SAR_AGENT_KEY="$(sar_resolve_agent_key)"
    SAR_RUN_ID_KEY="$(sar_new_run_id_key)"

    local jsondata resp
    jsondata="$(jq -n \
        --arg runIdKey "$SAR_RUN_ID_KEY" \
        --arg agentKey "$SAR_AGENT_KEY" \
        --arg executionMode "$execution_mode" \
        '{runIdKey:$runIdKey, agentKey:$agentKey, executionMode:$executionMode}')"

    resp="$(sar_api_post "SchedulerAgentRunStart runIdKey agentKey executionMode" "$jsondata")"

    if echo "$resp" | jq -e '.data[0].RstVal == 200' >/dev/null 2>&1; then
        SAR_STARTED=1
        sar_log_info "run start OK runIdKey=$SAR_RUN_ID_KEY agentKey=$SAR_AGENT_KEY mode=$execution_mode"
        return 0
    fi
    sar_log_warn "run start failed runIdKey=$SAR_RUN_ID_KEY agentKey=$SAR_AGENT_KEY resp=$resp"
    return 1
}

# 실행 종료 기록. Usage: sar_run_end <status: SUCCEEDED|FAILED> <exitCode>
sar_run_end() {
    local status="${1:-UNKNOWN}" exit_code="${2:-0}"

    if [ "$SAR_STARTED" -ne 1 ]; then
        # start가 기록되지 않았으면(설정 누락/start 실패 등) end도 만들지 않는다
        # - 시작 없는 종료 기록(짝 없는 run)을 방지한다.
        return 0
    fi
    if ! sar_deps_ok; then
        sar_log_warn "curl/jq not available - skipping run end tracking"
        return 1
    fi
    case "$exit_code" in
        ''|*[!0-9]*) exit_code=1 ;;  # 방어적 fallback: 숫자가 아니면 jq --argjson 실패 방지
    esac

    local jsondata resp
    jsondata="$(jq -n \
        --arg runIdKey "$SAR_RUN_ID_KEY" \
        --arg agentKey "$SAR_AGENT_KEY" \
        --arg status "$status" \
        --argjson processedCount 0 \
        --argjson skippedCount 0 \
        --argjson failedCount 0 \
        --argjson exitCode "$exit_code" \
        '{runIdKey:$runIdKey, agentKey:$agentKey, status:$status, processedCount:$processedCount,
          skippedCount:$skippedCount, failedCount:$failedCount, exitCode:$exitCode}')"

    resp="$(sar_api_post "SchedulerAgentRunEnd runIdKey agentKey status processedCount skippedCount failedCount exitCode" "$jsondata")"

    if echo "$resp" | jq -e '.data[0].RstVal == 200' >/dev/null 2>&1; then
        sar_log_info "run end OK runIdKey=$SAR_RUN_ID_KEY status=$status exitCode=$exit_code"
        return 0
    fi
    sar_log_warn "run end failed runIdKey=$SAR_RUN_ID_KEY status=$status resp=$resp"
    return 1
}

# trap 'sar_run_end_trap' EXIT 용 헬퍼. 반드시 트랩 핸들러의 "첫 명령"으로 $?를
# 캡처해야 스크립트의 실제 종료 코드를 얻을 수 있다(그 다음 명령부터는 $?가 바뀐다).
sar_run_end_trap() {
    local ec=$?
    if [ "$ec" -eq 0 ]; then
        sar_run_end "SUCCEEDED" "$ec"
    else
        sar_run_end "FAILED" "$ec"
    fi
}
