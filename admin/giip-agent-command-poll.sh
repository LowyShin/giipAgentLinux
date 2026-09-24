#!/bin/bash
#
# giip-agent-command-poll.sh - giip #1172 (slack-bot 에이전트 관리 Phase 1)
#
# 목적:
#   slack-bot -> giipfaw(agent-command) 로 발급된 "restart/stop/start/status" 명령은
#   지금까지 tAgentCommandLog에 pending 행만 남기고 끝났다(giipfaw PR #82 확인).
#   giipAgentLinux는 상시 리스닝 데몬이 아니라 giipAgent3.sh가 root crontab에 주기
#   등록되어 도는 구조라(README, admin/giipcronreg.sh), giipfaw가 에이전트로 직접
#   REST 콜을 거는 push 모델이 성립하지 않는다.
#
#   이 스크립트는 그 대신 "폴링 모델"로 실행 경로를 완성한다:
#     1) agent-register  로 자기 자신을 등록/갱신하고 agentId 확보
#     2) agent-heartbeat 로 현재 running/stopped 상태 보고
#     3) agent-command-poll 로 자기 앞으로 온 pending 명령 조회
#     4) 명령 실행 (admin/giiprecycle.sh 와 동일한 kill 패턴 - cron이 재기동을 맡음)
#     5) agent-command-complete 로 실행 결과 보고
#
#   ⚠️ 핵심 원칙: giipAgent3.sh/giipAgent.sh 의 핵심 실행 흐름은 건드리지 않는다.
#   이 스크립트는 완전히 독립된 신규 파일이며, admin/giipcronreg.sh 가 등록하는
#   크론 목록에 신규 항목으로만 추가된다.
#
# 사용법:
#   bash admin/giip-agent-command-poll.sh          # 정상 실행 (cron에서 사용)
#   bash admin/giip-agent-command-poll.sh --once    # 로그를 stdout에도 출력(수동 테스트용)
#
# 필요 설정 (giipAgentLinux 부모 디렉토리의 giipAgent.cnf):
#   ak                 - 에이전트 관리 API용 access token (uAccesstoken).
#                         기존 "sk"(서버별 secret key)와는 별개의 값이다 — corp user의
#                         AK(로그인 세션 토큰)가 필요하다. 비어있으면 이 스크립트는
#                         아무 것도 하지 않고 조용히 종료한다(기존 설치를 깨지 않기 위함).
#   agent_name          - (선택) tAgentRegistry.agentName 으로 쓸 이름.
#                         기본값: "giipAgentLinux-$(hostname)"
#   agentapibase         - (선택) agent-* Function들의 base URL.
#                         기본값: apiaddrv2 에서 마지막 path segment(giipApiSk2)를 뗀 값
#                         예: apiaddrv2=https://giipfaw.azurewebsites.net/api/giipApiSk2
#                             -> agentapibase=https://giipfaw.azurewebsites.net/api
#   agentfunctionkey     - (선택) agent-* Function이 authLevel=function 이라 Azure
#                         Functions key가 필요할 경우 사용(x-functions-key 헤더 +
#                         ?code= 쿼리 둘 다 시도). 비어있으면 생략.
#
# 알려진 제약 (설계 문서/이슈 코멘트에 명시):
#   - "stop" 명령: giipAgent3.sh crontab 항목(* * * * *)은 이 스크립트가 건드리지
#     않으므로, kill 이후 최대 60초 내에 cron이 다시 기동시킨다. 진짜 영구 중지는
#     crontab 항목 자체를 비활성화해야 하며 이 스크립트의 책임 범위 밖이다.
#   - "start": 별도 죽여야 할 데몬이 없다 — cron이 이미 1분 주기로 기동을 보장한다.
#     이미 실행 중이면 멱등 success, 아니면 "다음 cron tick에 기동됨" 안내와 함께 success.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# cnf는 레포지토리 부모 디렉토리에 위치 (다른 admin/scripts 스크립트와 동일 관례)
INSTALL_DIR="$(dirname "$REPO_DIR")"
CONFIG_FILE="${INSTALL_DIR}/giipAgent.cnf"
if [ ! -f "$CONFIG_FILE" ]; then
    # Fallback: cnf가 레포 루트 안에 있는 경우
    CONFIG_FILE="${REPO_DIR}/giipAgent.cnf"
fi

LOG_DIR="/var/log"
if [ ! -w "$LOG_DIR" ]; then
    LOG_DIR="/tmp"
fi
LOGFILE="${LOG_DIR}/giip-agent-command-poll.log"
CACHE_FILE="${INSTALL_DIR}/.giip_agent_id_cache"

PRINT_STDOUT=false
if [ "${1:-}" = "--once" ]; then
    PRINT_STDOUT=true
fi

log() {
    local line="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$line" >> "$LOGFILE"
    # NOTE: stderr only, never stdout — several functions below (register_agent,
    # execute_command, ...) return their result via `echo` + command substitution,
    # and a stdout-mirrored log line would silently corrupt that captured value.
    if [ "$PRINT_STDOUT" = true ]; then echo "$line" >&2; fi
}
log_error() { log "❌ ERROR: $*"; }
log_warn()  { log "⚠️  WARNING: $*"; }
log_ok()    { log "✅ $*"; }

if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi
# shellcheck disable=SC1090
. "$CONFIG_FILE"

if [ -z "${apiaddrv2:-}" ]; then
    log_error "Missing required configuration: apiaddrv2"
    exit 1
fi

# --- ak 미설정 시: 조용히 스킵 (기존 설치를 깨지 않는다) ---------------------
if [ -z "${ak:-}" ]; then
    log "ℹ️  'ak' not configured in $CONFIG_FILE — skipping agent command management (see giipAgent.cnf.example for provisioning notes). This is expected until an AK is issued for this install."
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required but not found. Run: sudo bash admin/giipinstmodule.sh jq"
    exit 1
fi

AGENT_API_BASE="${agentapibase:-}"
if [ -z "$AGENT_API_BASE" ]; then
    AGENT_API_BASE="$(dirname "$apiaddrv2")"
fi

AGENT_NAME="${agent_name:-giipAgentLinux-$(hostname)}"
FUNCTION_KEY="${agentfunctionkey:-}"

# --- curl 헬퍼: x-api-key(AK) + (선택) Azure Functions key -----------------
agent_get() {
    local path="$1"
    local url="${AGENT_API_BASE}${path}"
    if [ -n "$FUNCTION_KEY" ]; then
        if [[ "$url" == *"?"* ]]; then url="${url}&code=${FUNCTION_KEY}"; else url="${url}?code=${FUNCTION_KEY}"; fi
    fi
    curl -sS -X GET "$url" \
        -H "x-api-key: ${ak}" \
        -H "x-functions-key: ${FUNCTION_KEY}" \
        2>&1
}

agent_post() {
    local path="$1"
    local json="$2"
    local url="${AGENT_API_BASE}${path}"
    if [ -n "$FUNCTION_KEY" ]; then
        url="${url}?code=${FUNCTION_KEY}"
    fi
    curl -sS -X POST "$url" \
        -H "x-api-key: ${ak}" \
        -H "x-functions-key: ${FUNCTION_KEY}" \
        -H "Content-Type: application/json" \
        -d "$json" \
        2>&1
}

# --- 1. 자기 등록/갱신 (agentId 확보) ---------------------------------------
register_agent() {
    local json
    json=$(jq -n --arg agentName "$AGENT_NAME" --arg agentType "linux" --arg hostName "$(hostname)" \
        '{agentName:$agentName, agentType:$agentType, hostName:$hostName}')

    local response
    response=$(agent_post "/agent-register" "$json")

    if echo "$response" | jq -e '.agentId' >/dev/null 2>&1; then
        local agentId
        agentId=$(echo "$response" | jq -r '.agentId')
        echo "$agentId" > "$CACHE_FILE" 2>/dev/null
        log "register_agent: agentId=$agentId action=$(echo "$response" | jq -r '.action // "?"')"
        echo "$agentId"
        return 0
    fi

    log_warn "register_agent failed, response=$response"
    if [ -f "$CACHE_FILE" ]; then
        local cached
        cached=$(cat "$CACHE_FILE" 2>/dev/null)
        if [ -n "$cached" ]; then
            log_warn "Falling back to cached agentId=$cached"
            echo "$cached"
            return 0
        fi
    fi
    return 1
}

# --- 현재 giipAgent3.sh 프로세스 실행 여부 (admin/giiprecycle.sh 와 동일 패턴) ---
detect_running_count() {
    ps aux | grep giipAgent3.sh | grep -v grep | wc -l
}

# --- 2. 하트비트 보고 (실패해도 치명적이지 않음) ----------------------------
heartbeat_agent() {
    local agent_id="$1"
    local status="$2"
    local json
    json=$(jq -n --arg agentId "$agent_id" --arg status "$status" --arg hostName "$(hostname)" \
        '{agentId:($agentId|tonumber), status:$status, hostName:$hostName}')
    local response
    response=$(agent_post "/agent-heartbeat" "$json")
    if echo "$response" | jq -e '.agentId' >/dev/null 2>&1; then
        log "heartbeat_agent: agentId=$agent_id status=$status OK"
    else
        log_warn "heartbeat_agent failed (non-fatal), response=$response"
    fi
}

# --- 3. pending 명령 폴링 ----------------------------------------------------
poll_commands() {
    local agent_id="$1"
    agent_get "/agent-command-poll?agentId=${agent_id}"
}

# --- kill giipAgent3.sh 프로세스 (admin/giiprecycle.sh 와 동일 패턴, 재사용 목적으로 새 함수로 분리) ---
kill_giipagent_processes() {
    local cnt
    cnt=$(detect_running_count)
    if [ "$cnt" -gt 0 ]; then
        ps aux | grep giipAgent3.sh | grep -v grep | awk '{ print "kill -9", $2 }' | sh
        echo "$cnt"
    else
        echo "0"
    fi
}

# --- 4. 명령 실행 ------------------------------------------------------------
# stdout: "<result>|<resultMessage>"  (result = success|failure)
execute_command() {
    local command="$1"
    case "$command" in
        restart)
            local killed
            killed=$(kill_giipagent_processes)
            if [ "$killed" -gt 0 ]; then
                echo "success|Killed ${killed} giipAgent3.sh process(es). Crontab (* * * * *) will relaunch within ~60s."
            else
                echo "success|No running giipAgent3.sh process found; crontab (* * * * *) will (re)launch within ~60s regardless."
            fi
            ;;
        stop)
            local killed
            killed=$(kill_giipagent_processes)
            echo "success|Killed ${killed} process(es). NOTE: giipAgent3.sh crontab entry runs every 1 minute and is NOT disabled by this command — it will auto-relaunch within ~60s. True permanent stop requires manually removing the crontab entry (out of scope for this remote command)."
            ;;
        start)
            local cnt
            cnt=$(detect_running_count)
            if [ "$cnt" -gt 0 ]; then
                echo "success|Idempotent: giipAgent3.sh already running (${cnt} process(es))."
            else
                echo "success|No persistent daemon to start directly; crontab (* * * * *) will launch giipAgent3.sh within ~60s."
            fi
            ;;
        status)
            local cnt
            cnt=$(detect_running_count)
            if [ "$cnt" -gt 0 ]; then
                echo "success|giipAgent3.sh is running (${cnt} process(es))."
            else
                echo "success|giipAgent3.sh is not running."
            fi
            ;;
        *)
            echo "failure|Unknown command: ${command}"
            ;;
    esac
}

# --- 5. 완료 보고 ------------------------------------------------------------
complete_command() {
    local cmd_id="$1"
    local result="$2"
    local message="$3"
    local json
    json=$(jq -n --arg cmdId "$cmd_id" --arg result "$result" --arg resultMessage "$message" \
        '{cmdId:($cmdId|tonumber), result:$result, resultMessage:$resultMessage}')
    local response
    response=$(agent_post "/agent-command-complete" "$json")
    if echo "$response" | jq -e '.cmdId' >/dev/null 2>&1; then
        log_ok "complete_command: cmdId=$cmd_id result=$result agentStatus=$(echo "$response" | jq -r '.agentStatus // "?"')"
    else
        log_error "complete_command failed for cmdId=$cmd_id, response=$response"
    fi
}

# ============================================================================
# Main
# ============================================================================
log "=== giip-agent-command-poll: start (agent_name=$AGENT_NAME, api_base=$AGENT_API_BASE) ==="

AGENT_ID="$(register_agent)"
if [ -z "$AGENT_ID" ]; then
    log_error "Could not resolve agentId (register failed, no cache). Aborting this run."
    exit 1
fi

RUNNING_CNT=$(detect_running_count)
if [ "$RUNNING_CNT" -gt 0 ]; then
    CURRENT_STATUS="running"
else
    CURRENT_STATUS="stopped"
fi
heartbeat_agent "$AGENT_ID" "$CURRENT_STATUS"

POLL_RESPONSE=$(poll_commands "$AGENT_ID")
if ! echo "$POLL_RESPONSE" | jq -e '.commands' >/dev/null 2>&1; then
    log_error "poll_commands failed or returned unexpected shape: $POLL_RESPONSE"
    exit 1
fi

CMD_COUNT=$(echo "$POLL_RESPONSE" | jq -r '.count // 0')
log "Polled ${CMD_COUNT} pending command(s) for agentId=$AGENT_ID"

if [ "$CMD_COUNT" -gt 0 ]; then
    echo "$POLL_RESPONSE" | jq -c '.commands[]' | while read -r cmd_json; do
        CMD_ID=$(echo "$cmd_json" | jq -r '.cmdId')
        COMMAND=$(echo "$cmd_json" | jq -r '.command')
        log "Executing cmdId=$CMD_ID command=$COMMAND"

        OUT=$(execute_command "$COMMAND")
        RESULT="${OUT%%|*}"
        MESSAGE="${OUT#*|}"

        log "cmdId=$CMD_ID result=$RESULT message=$MESSAGE"
        complete_command "$CMD_ID" "$RESULT" "$MESSAGE"
    done
fi

log "=== giip-agent-command-poll: done ==="
