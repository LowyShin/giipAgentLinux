#!/bin/bash
#
# lib/log_collector.sh - giip #1635 (giip #1614 3단계: Linux FDE Box 로그 수집기)
#
# 목적:
#   FDE Box(giipAgentLinux가 도는 서버)의 로그 파일을 잘라읽어(tail) giipfaw의
#   agent-log-register / agent-log-ingest Function으로 전송한다. giipdb(SP)와
#   giipfaw(Function) 쪽에도 동일 계약으로 병렬 구현되어 있다(cSn=47, giip #1635).
#
#   조사 결과(giip #1635 코멘트 참고): giipAgentLinux 전체에 gissue 스케줄러가
#   없다(admin/../scripts/issue_workflow_runner.sh의 WORKFLOW 기본값 문자열
#   "gissue-proc" 하나뿐, Windows의 gissue_csn<csn>.log와는 무관). 따라서 1차
#   수집 대상은 giipAgentLinux 자신의 운영 로그(giipAgent.sh가 만드는
#   log/giipAgent_YYYYMMDD.log)이며, opt-in 설정으로 다른 파일(~/.claude/...,
#   ~/.codex/... 등)도 추가할 수 있게 해 두었다. 이 스코프 판단의 근거는
#   giipdb 스펙 문서(docs/30_Specs/AGENT_LOG_COLLECTOR_SPECIFICATION.md, 병렬
#   작업자 작성)에도 동일하게 기록된다.
#
#   ⚠️ 핵심 원칙(admin/giip-agent-command-poll.sh와 동일): giipAgent.sh/
#   giipAgent3.sh의 핵심 실행 흐름은 절대 건드리지 않는다. 이 스크립트는
#   완전히 독립된 신규 파일이며, admin/giipcronreg.sh가 등록하는 크론 목록에
#   신규 항목으로만 추가된다. 'logcollector_enabled'이 truthy가 아니면 아무
#   것도 하지 않고 조용히 종료한다(기존 설치를 깨지 않기 위함) - 즉 이 파일이
#   존재해도 cnf에 옵션을 추가하지 않는 한 완전히 no-op이다.
#
# 사용법:
#   bash lib/log_collector.sh          # 정상 실행 (cron에서 1분마다 기동, 내부에서
#                                       #  최대 logcollector_run_duration_sec초 루프 후 종료)
#   bash lib/log_collector.sh --once   # 배치 루프 없이 단발 1회 수집/전송 + stdout 로그
#                                       #  (수동 테스트/디버깅용)
#
# 필요 설정 (giipAgentLinux 부모 디렉토리의 giipAgent.cnf, giipAgent.cnf.example 참고):
#   sk, apiaddrv2      - 기존 필수값 재사용(별도 토큰 체계를 새로 만들지 않는다).
#                        agent-log-register/agent-log-ingest 호출 시 x-api-key: ${sk}
#                        헤더로 보낸다(SK 기반 SP를 호출하므로 'ak'가 아니라 'sk').
#   logcollector_enabled          - 1/true/yes 가 아니면 조용히 skip (기본: 비활성화)
#   logcollector_globs            - 콤마 구분 glob 목록. 기본값:
#                                    "${REPO_DIR}/log/giipAgent_*.log" 하나
#   logcollector_streamtype_map   - (선택) "glob:streamType,glob:streamType,..."
#                                    형태의 명시적 매핑. 매칭 안 되면 파일명 기반
#                                    휴리스틱으로 판단.
#   logcollector_agentkey         - (선택) tSchedulerAgent류 Box 식별에 쓸
#                                    agentKey 강제 지정. 비어있으면 hostname +
#                                    /etc/machine-id 기반으로 생성해
#                                    INSTALL_DIR/.giip_logcollector_agentkey 에
#                                    캐시한다(admin/giip-agent-command-poll.sh의
#                                    .giip_agent_id_cache와 동일 관례). giipAgentWin/
#                                    giipfaw 어디에도 기존 agentKey 발급 경로가 없어
#                                    (2026-08-28 grep 확인) 이 스크립트가 자체 생성.
#   logcollector_batch_interval_sec - 배치 전송 주기(초). 기본 2
#   logcollector_batch_max_bytes    - 배치 최대 바이트(대략치, content 길이 합산
#                                      기준). 기본 131072 (128KB)
#   logcollector_run_duration_sec   - 1회 cron tick 내에서 루프 지속 시간(초).
#                                      기본 50 (다음 분 크론 tick 전에 종료)
#   logcollector_queue_max_batches  - 전송 실패시 로컬 큐에 쌓아둘 최대 배치 수. 기본 500
#   logcollector_queue_max_mb       - 로컬 큐 최대 용량(MB, gzip 압축 후 기준). 기본 20
#   agentapibase       - (선택) agent-* Function들의 base URL. 기본값은
#                        apiaddrv2에서 마지막 path segment를 뗀 값
#                        (admin/giip-agent-command-poll.sh와 동일 로직)
#
# 설계상 알려진 단순화(스코프 내 판단, PR 설명에도 명시):
#   - 배치 트리거는 "바이트 임계값 도달 시 분할" + "루프 주기(batch_interval_sec)마다
#     그 시점까지 쌓인 새 데이터를 모두 flush" 조합으로 구현했다. 엄격한 실시간
#     1~2초 배치가 아니라 "최대 대기시간 = batch_interval_sec" 근사치다.
#   - 전송은 compression:"none" (평문 JSON)을 사용한다. 로컬 재시도 큐 파일은
#     디스크 절약을 위해 gzip으로 저장하되, 전송 시점에는 압축을 풀어
#     compression:"none"으로 재전송한다(gzip+linesGzB64 경로도 계약상 유효하지만,
#     1차 구현은 구현 단순성을 위해 이 경로를 택했다).
#   - 라인별 "ts"는 실제 로그 라인에 찍힌 시각을 파싱한 값이 아니라 "이 라인을
#     읽어 전송 준비한 시각"이다(수집 시각). 이벤트 발생 시각이 필요하면 뷰어
#     쪽에서 content를 파싱해야 한다 - 로그 포맷이 제각각이라 이번 스코프에서는
#     파싱하지 않는다.
#   - offset/sequence는 "파일을 읽은 진행도" 체크포인트이고, 전송 성공 여부와는
#     분리되어 있다: 전송 실패분은 로컬 큐(용량 제한)에서 재시도하고, 큐가 꽉 차면
#     가장 오래된 배치부터 드롭한다(로그에 남김). 큐가 무한정 쌓이는 것을 막기
#     위한 의도적 트레이드오프다.

set -u
shopt -s nullglob globstar 2>/dev/null

# ============================================================================
# Path resolution (admin/giip-agent-command-poll.sh와 동일 관례)
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../giipAgentLinux/lib
REPO_DIR="$(dirname "$SCRIPT_DIR")"                            # .../giipAgentLinux
INSTALL_DIR="$(dirname "$REPO_DIR")"                            # cnf가 있는 부모 디렉토리
CONFIG_FILE="${INSTALL_DIR}/giipAgent.cnf"
if [ ! -f "$CONFIG_FILE" ]; then
    # Fallback: cnf가 레포 루트 안에 있는 경우
    CONFIG_FILE="${REPO_DIR}/giipAgent.cnf"
fi

DEFAULT_GLOB="${REPO_DIR}/log/giipAgent_*.log"
STATE_DIR="${REPO_DIR}/log/.collector_state"
QUEUE_DIR="${STATE_DIR}/queue"
BACKOFF_STATE="${QUEUE_DIR}/.backoff"
AGENTKEY_CACHE="${INSTALL_DIR}/.giip_logcollector_agentkey"

LOG_DIR="/var/log"
if [ ! -w "$LOG_DIR" ]; then
    LOG_DIR="/tmp"
fi
LOGFILE="${LOG_DIR}/giip-log-collector.log"

ONCE_MODE=false
PRINT_STDOUT=false
if [ "${1:-}" = "--once" ]; then
    ONCE_MODE=true
    PRINT_STDOUT=true
fi

# ============================================================================
# Logging
# ============================================================================
log() {
    local line="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$line" >> "$LOGFILE" 2>/dev/null
    if [ "$PRINT_STDOUT" = true ]; then echo "$line" >&2; fi
}
log_warn()  { log "WARN: $*"; }
log_error() { log "ERROR: $*"; }
log_ok()    { log "OK: $*"; }

# ============================================================================
# Small pure helpers (test 대상 - lib/log_collector.sh를 source해서 직접 호출 가능)
# ============================================================================

# stdout: inode number, or empty if stat fails
get_inode() {
    stat -c '%i' "$1" 2>/dev/null
}

# stdout: file size in bytes, or empty if stat fails
get_size() {
    stat -c '%s' "$1" 2>/dev/null
}

# "~/foo" -> "$HOME/foo" (eval 없이 안전하게 tilde만 확장)
expand_tilde() {
    local p="$1"
    case "$p" in
        "~/"*) printf '%s' "${HOME}/${p#\~/}" ;;
        "~")   printf '%s' "$HOME" ;;
        *)     printf '%s' "$p" ;;
    esac
}

# streamKey를 안전한 상태 파일명으로 변환 ('/' -> '__')
sanitize_key() {
    local key="$1"
    key="${key//\//__}"
    key="${key// /_}"
    printf '%s' "$key"
}

# 파일 절대경로를 $HOME 기준 상대경로로(가능하면), 아니면 절대경로(선행 '/' 제거)로
compute_rel_path() {
    local file="$1"
    local dir base abs
    dir="$(cd "$(dirname "$file")" 2>/dev/null && pwd)"
    base="$(basename "$file")"
    if [ -z "$dir" ]; then
        printf '%s' "$file"
        return
    fi
    abs="${dir}/${base}"
    case "$abs" in
        "$HOME"/*) printf '%s' "${abs#"$HOME"/}" ;;
        *) printf '%s' "${abs#/}" ;;
    esac
}

# streamType 결정: logcollector_streamtype_map(있으면) -> 파일명 휴리스틱
determine_stream_type() {
    local file="$1"
    local map="${logcollector_streamtype_map:-}"
    if [ -n "$map" ]; then
        local -a pairs
        IFS=',' read -ra pairs <<< "$map"
        local pair pat typ
        for pair in "${pairs[@]}"; do
            pat="${pair%%:*}"
            typ="${pair#*:}"
            [ "$pat" = "$pair" ] && continue  # ':' 없는 잘못된 항목은 skip
            pat="$(expand_tilde "$pat")"
            if [[ "$file" == $pat ]]; then
                printf '%s' "$typ"
                return 0
            fi
        done
    fi
    case "$file" in
        */log/giipAgent_*.log) printf 'agent_operational' ;;
        *"/.claude/projects/"*.jsonl) printf 'claude_jsonl' ;;
        *"/.codex/sessions/"*.jsonl) printf 'codex_jsonl' ;;
        *) printf 'generic_log' ;;
    esac
}

# 비밀 마스킹: sk=/password=/passwd=/pwd=/secret=/token=/api[_-]?key=, Authorization: 헤더
# (완벽한 DLP 아님 - 명백한 패턴만 정규식으로 가림, 대소문자 무시)
mask_line() {
    local line="$1"
    printf '%s' "$line" | sed -E \
        -e 's/\b(sk=)[^ ,;&]+/\1***MASKED***/Ig' \
        -e 's/\b(password=|passwd=|pwd=)[^ ,;&]+/\1***MASKED***/Ig' \
        -e 's/\b(secret=)[^ ,;&]+/\1***MASKED***/Ig' \
        -e 's/\b(token=)[^ ,;&]+/\1***MASKED***/Ig' \
        -e 's/\b(api[_-]?key=)[^ ,;&]+/\1***MASKED***/Ig' \
        -e 's/(Authorization:[[:space:]]*[A-Za-z]+[[:space:]]+)[^ ,;]+/\1***MASKED***/Ig'
}

iso8601_now() {
    date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ
}

# logcollector_agentkey > 캐시 파일 > (hostname + /etc/machine-id 앞 12자) 생성 후 캐시
resolve_agent_key() {
    if [ -n "${logcollector_agentkey:-}" ]; then
        printf '%s' "$logcollector_agentkey"
        return 0
    fi
    if [ -f "$AGENTKEY_CACHE" ]; then
        cat "$AGENTKEY_CACHE"
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
    echo "$key" > "$AGENTKEY_CACHE" 2>/dev/null
    printf '%s' "$key"
}

# 콤마구분 glob 목록 -> 실제 존재하는 파일 목록(줄바꿈 구분, 중복 없음)
discover_files() {
    local globs="$1"
    local -a patterns
    IFS=',' read -ra patterns <<< "$globs"
    local pat p
    local -A seen=()
    for pat in "${patterns[@]}"; do
        pat="$(expand_tilde "$pat")"
        [ -z "$pat" ] && continue
        for p in $pat; do
            [ -f "$p" ] || continue
            if [ -z "${seen[$p]:-}" ]; then
                seen[$p]=1
                printf '%s\n' "$p"
            fi
        done
    done
}

# ============================================================================
# API helpers
# ============================================================================
api_post() {
    local path="$1" json="$2"
    curl -sS --max-time 15 --connect-timeout 5 -X POST "${AGENT_API_BASE}${path}" \
        -H "x-api-key: ${sk}" \
        -H "Content-Type: application/json" \
        -d "$json" \
        2>&1
}

# tSchedulerAgent 부트스트랩 (giip #1638)
#
# 배경: agent-log-register / agent-log-ingest Function은 호출 전에 csn+agentKey로
# tSchedulerAgent 행이 이미 존재해야 한다 - 없으면 "Agent not found - register via
# pApiSchedulerAgentUpsertBySK first" 404가 난다. giipAgentWin 쪽 LogCollector.ps1이
# giip #1637(PR #33)로 먼저 발견/수정한 것과 동일한 갭이며, 이 함수는 그 대칭
# 구현이다. SP(pApiSchedulerAgentUpsertBySK, giip #1634로 giipdb에 이미 배포됨)는
# csn+agentKey 기준 idempotent upsert이므로, 이번 tick의 부트스트랩이 실패해도
# 다음 tick에서 안전하게 재시도된다 - 그래서 실패를 치명적으로 취급하지 않고
# WARN만 남긴 뒤 계속 진행한다.
#
# NOT NULL 파라미터(agentKey, displayName)만 넘긴다: giipApiSk2 디스패처(apiaddrv2)는
# text에 나열한 파라미터 이름 순서대로 positional 처리하기 때문에 나머지 옵션
# 파라미터(hostIdentifier 등)에 NULL 리터럴을 안전하게 끼워 넣을 방법이 없다 -
# giipAgentWin의 Invoke-SchedulerAgentBootstrap이 두 개만 넘기는 것과 같은 이유.
#
# 호출 규약은 lib/kvs_standard.sh의 kvs_send()/lib/kvs.sh의 save_execution_log()와
# 동일: apiaddrv2에 form-encoded text(파라미터 이름만)/token(=sk)/jsondata(실제 값)를
# POST하고, 응답은 .data[0].RstVal == 200 으로 판정한다. (agent-log-register/ingest가
# 쓰는 AGENT_API_BASE + x-api-key 방식과는 다른, apiaddrv2 직접 호출 방식이다.)
bootstrap_scheduler_agent() {
    local agent_key="$1"
    local display_name="${agent_name:-giipAgentLinux-$(hostname)}"
    local jsondata resp

    jsondata="$(jq -n --arg agentKey "$agent_key" --arg displayName "$display_name" \
        '{agentKey:$agentKey, displayName:$displayName}')"

    resp="$(curl -sS --max-time 15 --connect-timeout 5 -X POST "${apiaddrv2}" \
        --data-urlencode "text=SchedulerAgentUpsert agentKey displayName" \
        --data-urlencode "token=${sk}" \
        --data-urlencode "jsondata=${jsondata}" \
        2>&1)"

    if echo "$resp" | jq -e '.data[0].RstVal == 200' >/dev/null 2>&1; then
        log_ok "bootstrap_scheduler_agent OK agentKey=$agent_key"
        return 0
    fi
    log_warn "bootstrap_scheduler_agent failed agentKey=$agent_key resp=$resp"
    return 1
}

register_stream() {
    local stream_key="$1" stream_type="$2" inode="$3" rotation_gen="$4"
    local body resp
    body="$(jq -n \
        --arg agentKey "$AGENT_KEY" \
        --arg streamKey "$stream_key" \
        --arg streamType "$stream_type" \
        --arg fileFingerprint "inode:${inode}" \
        --argjson rotationGen "$rotation_gen" \
        '{agentKey:$agentKey, streamKey:$streamKey, streamType:$streamType, fileFingerprint:$fileFingerprint, rotationGen:$rotationGen}')"
    resp="$(api_post "/agent-log-register" "$body")"
    if echo "$resp" | jq -e '.streamId' >/dev/null 2>&1; then
        log_ok "register_stream stream=$stream_key streamId=$(echo "$resp" | jq -r '.streamId') action=$(echo "$resp" | jq -r '.action // "?"')"
        return 0
    fi
    log_warn "register_stream failed stream=$stream_key response=$resp"
    return 1
}

# ============================================================================
# Local state persistence
# ============================================================================
save_state() {
    local state_file="$1" offset="$2" rotation_gen="$3" inode="$4" last_sequence="$5"
    mkdir -p "$(dirname "$state_file")" 2>/dev/null
    cat > "$state_file" <<EOF
offset=$offset
rotation_gen=$rotation_gen
inode=$inode
last_sequence=$last_sequence
EOF
}

# ============================================================================
# Retry queue (전송 실패분 gzip 저장, 용량 제한 + 지수 백오프)
# ============================================================================
enforce_queue_caps() {
    mkdir -p "$QUEUE_DIR" 2>/dev/null
    local max_batches="${logcollector_queue_max_batches:-500}"
    local max_mb="${logcollector_queue_max_mb:-20}"
    local max_kb=$((max_mb * 1024))
    local total_count total_kb
    total_count=$(find "$QUEUE_DIR" -type f -name '*.json.gz' 2>/dev/null | wc -l | tr -d ' ')
    total_kb=$(du -sk "$QUEUE_DIR" 2>/dev/null | awk '{print $1}')
    [ -z "$total_kb" ] && total_kb=0

    while [ "$total_count" -gt "$max_batches" ] || [ "$total_kb" -gt "$max_kb" ]; do
        local oldest
        oldest=$(find "$QUEUE_DIR" -type f -name '*.json.gz' -printf '%T@ %p\n' 2>/dev/null | sort -n | head -1 | cut -d' ' -f2-)
        [ -z "$oldest" ] && break
        log_warn "retry queue over capacity (count=$total_count/$max_batches, size_kb=$total_kb/$max_kb) - dropping oldest: $oldest"
        rm -f "$oldest"
        total_count=$(find "$QUEUE_DIR" -type f -name '*.json.gz' 2>/dev/null | wc -l | tr -d ' ')
        total_kb=$(du -sk "$QUEUE_DIR" 2>/dev/null | awk '{print $1}')
        [ -z "$total_kb" ] && total_kb=0
    done
}

enqueue_retry() {
    local stream_key="$1" body="$2"
    local qsub="${QUEUE_DIR}/$(sanitize_key "$stream_key")"
    mkdir -p "$qsub" 2>/dev/null
    local fname="${qsub}/$(date +%s%N 2>/dev/null || date +%s)_$$_${RANDOM}.json.gz"
    printf '%s' "$body" | gzip -c > "$fname" 2>/dev/null
    log_warn "enqueue_retry: queued failed batch for stream=$stream_key -> $fname"
    enforce_queue_caps
}

flush_retry_queue() {
    mkdir -p "$QUEUE_DIR" 2>/dev/null
    local now backoff_until=0 backoff_sec=5
    now=$(date +%s)
    if [ -f "$BACKOFF_STATE" ]; then
        backoff_until=""
        backoff_sec=""
        # shellcheck disable=SC1090
        . "$BACKOFF_STATE"
        backoff_until="${backoff_until:-0}"
        backoff_sec="${backoff_sec:-5}"
    fi
    if [ "$now" -lt "$backoff_until" ]; then
        return 0
    fi

    local files
    files=$(find "$QUEUE_DIR" -type f -name '*.json.gz' 2>/dev/null | sort)
    [ -z "$files" ] && { rm -f "$BACKOFF_STATE"; return 0; }

    local any_failed=0 f body resp
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        body="$(gzip -dc "$f" 2>/dev/null)"
        if [ -z "$body" ]; then
            log_warn "flush_retry_queue: corrupt/empty queued batch, dropping: $f"
            rm -f "$f"
            continue
        fi
        resp="$(api_post "/agent-log-ingest" "$body")"
        if echo "$resp" | jq -e '.streamId' >/dev/null 2>&1; then
            rm -f "$f"
            log_ok "flush_retry_queue: resent $f"
        else
            log_warn "flush_retry_queue: resend still failing for $f, response=$resp"
            any_failed=1
            break
        fi
    done <<< "$files"

    if [ "$any_failed" -eq 1 ]; then
        backoff_sec=$((backoff_sec * 2))
        [ "$backoff_sec" -gt 300 ] && backoff_sec=300
        {
            echo "backoff_until=$(( $(date +%s) + backoff_sec ))"
            echo "backoff_sec=$backoff_sec"
        } > "$BACKOFF_STATE"
    else
        rm -f "$BACKOFF_STATE"
    fi
}

# ============================================================================
# 배치 분할(대략 바이트 임계값 기준) + 전송
# ============================================================================
split_ndjson_into_batches() {
    local ndjson_file="$1" max_bytes="$2" out_prefix="$3"
    awk -v max="$max_bytes" -v prefix="$out_prefix" '
        BEGIN { idx=0; bytes=0; outfile=sprintf("%s_%05d.ndjson", prefix, idx) }
        {
            lb = length($0) + 1
            if (bytes > 0 && bytes + lb > max) {
                close(outfile)
                idx++
                outfile=sprintf("%s_%05d.ndjson", prefix, idx)
                bytes=0
            }
            print $0 >> outfile
            bytes += lb
        }
        END { if (bytes > 0) close(outfile) }
    ' "$ndjson_file"
}

send_ingest_batch() {
    local ndjson_file="$1" stream_key="$2" rotation_gen="$3"
    local from_seq to_seq lines_json sent_at body resp
    from_seq="$(jq -r '.seq' "$ndjson_file" | head -1)"
    to_seq="$(jq -r '.seq' "$ndjson_file" | tail -1)"
    lines_json="$(jq -s '.' "$ndjson_file")"
    sent_at="$(iso8601_now)"
    body="$(jq -n \
        --arg agentKey "$AGENT_KEY" \
        --arg streamKey "$stream_key" \
        --argjson rotationGen "$rotation_gen" \
        --argjson fromSequence "$from_seq" \
        --argjson toSequence "$to_seq" \
        --arg sentAt "$sent_at" \
        --argjson lines "$lines_json" \
        '{agentKey:$agentKey, streamKey:$streamKey, rotationGen:$rotationGen, fromSequence:$fromSequence, toSequence:$toSequence, sentAt:$sentAt, compression:"none", lines:$lines, linesGzB64:null}')"

    resp="$(api_post "/agent-log-ingest" "$body")"
    if echo "$resp" | jq -e '.streamId' >/dev/null 2>&1; then
        log_ok "ingest stream=$stream_key seq=${from_seq}-${to_seq} insertedCount=$(echo "$resp" | jq -r '.insertedCount // "?"')"
        return 0
    fi
    log_warn "ingest failed stream=$stream_key seq=${from_seq}-${to_seq} response=$resp"
    enqueue_retry "$stream_key" "$body"
    return 1
}

# ============================================================================
# 파일에서 새로 추가된 "완결된 라인"만 읽기 (마지막 미종료 라인은 다음 패스로 미룸)
# 결과는 전역변수로 리턴: NEW_OFFSET, NEW_LAST_SEQUENCE
# ============================================================================
collect_and_send_new_data() {
    local file="$1" offset="$2" stream_key="$3" rotation_gen="$4" last_sequence="$5"

    local target_size
    target_size="$(get_size "$file")"
    if [ -z "$target_size" ]; then
        NEW_OFFSET=$offset
        NEW_LAST_SEQUENCE=$last_sequence
        return 0
    fi
    local remain=$((target_size - offset))
    if [ "$remain" -le 0 ]; then
        NEW_OFFSET=$offset
        NEW_LAST_SEQUENCE=$last_sequence
        return 0
    fi
    local read_cap="${logcollector_max_read_bytes:-4194304}"  # 한 패스 최대 4MB (메모리 보호)
    if [ "$remain" -gt "$read_cap" ]; then
        remain=$read_cap
    fi

    local uniq="$$_${RANDOM}_$(date +%s%N 2>/dev/null || date +%s)"
    local chunk_file="${WORK_DIR}/chunk_${uniq}.bin"
    tail -c +"$((offset+1))" "$file" 2>/dev/null | head -c "$remain" > "$chunk_file"
    local actual_size
    actual_size="$(get_size "$chunk_file")"
    if [ -z "$actual_size" ] || [ "$actual_size" -eq 0 ]; then
        rm -f "$chunk_file"
        NEW_OFFSET=$offset
        NEW_LAST_SEQUENCE=$last_sequence
        return 0
    fi

    local ends_with_nl=0
    if [ "$(tail -c1 "$chunk_file" | wc -l)" -eq 1 ]; then
        ends_with_nl=1
    fi

    local consumed complete_file="${WORK_DIR}/complete_${uniq}.bin"
    if [ "$ends_with_nl" -eq 1 ]; then
        consumed=$actual_size
        mv "$chunk_file" "$complete_file"
    else
        local last_nl_pos
        last_nl_pos="$(grep -abo $'\n' "$chunk_file" | tail -1 | cut -d: -f1)"
        if [ -z "$last_nl_pos" ]; then
            # 아직 개행 없는 라인 하나뿐 - 이번 패스는 건너뜀
            rm -f "$chunk_file"
            NEW_OFFSET=$offset
            NEW_LAST_SEQUENCE=$last_sequence
            return 0
        fi
        consumed=$((last_nl_pos + 1))
        head -c "$consumed" "$chunk_file" > "$complete_file"
        rm -f "$chunk_file"
    fi

    # 1) 완결 라인들을 순번 매겨 NDJSON으로 마스킹 후 기록
    local ndjson_file="${WORK_DIR}/lines_${uniq}.ndjson"
    : > "$ndjson_file"
    local seq=$last_sequence
    local raw_line masked ts
    while IFS= read -r raw_line || [ -n "$raw_line" ]; do
        seq=$((seq + 1))
        masked="$(mask_line "$raw_line")"
        ts="$(iso8601_now)"
        jq -n --argjson seq "$seq" --arg ts "$ts" --arg content "$masked" \
            '{seq:$seq, ts:$ts, content:$content}' >> "$ndjson_file"
    done < "$complete_file"
    rm -f "$complete_file"

    # 2) 바이트 임계값으로 배치 분할 후 순서대로 전송
    if [ -s "$ndjson_file" ]; then
        local batch_max_bytes="${logcollector_batch_max_bytes:-131072}"
        local batch_prefix="${WORK_DIR}/batch_${uniq}"
        split_ndjson_into_batches "$ndjson_file" "$batch_max_bytes" "$batch_prefix"
        local bf
        for bf in "${batch_prefix}"_*.ndjson; do
            [ -f "$bf" ] || continue
            send_ingest_batch "$bf" "$stream_key" "$rotation_gen"
            rm -f "$bf"
        done
    fi
    rm -f "$ndjson_file"

    NEW_OFFSET=$((offset + consumed))
    NEW_LAST_SEQUENCE=$seq
}

# ============================================================================
# 파일 단위 처리: 회전 감지 -> (필요시) register -> 신규 라인 수집/전송 -> 상태 저장
# ============================================================================
process_file() {
    local file="$1"
    local stream_type stream_key state_file
    stream_type="$(determine_stream_type "$file")"
    stream_key="${stream_type}:$(compute_rel_path "$file")"
    state_file="${STATE_DIR}/$(sanitize_key "$stream_key").state"

    local offset=0 rotation_gen=0 inode="" last_sequence=0
    local is_new=0
    if [ ! -f "$state_file" ]; then
        is_new=1
    else
        # shellcheck disable=SC1090
        . "$state_file"
        offset="${offset:-0}"
        rotation_gen="${rotation_gen:-0}"
        last_sequence="${last_sequence:-0}"
    fi

    local current_inode current_size
    current_inode="$(get_inode "$file")"
    current_size="$(get_size "$file")"
    if [ -z "$current_inode" ] || [ -z "$current_size" ]; then
        log_warn "stat failed for $file, skipping this pass"
        return 0
    fi

    local need_register=0
    if [ "$is_new" -eq 1 ]; then
        need_register=1
    elif [ "$current_inode" != "$inode" ] || [ "$current_size" -lt "$offset" ]; then
        log "rotation detected stream=$stream_key (inode ${inode:-<none>}->${current_inode}, size=${current_size} offset=${offset})"
        rotation_gen=$((rotation_gen + 1))
        offset=0
        last_sequence=0
        need_register=1
    fi

    if [ "$need_register" -eq 1 ]; then
        if ! register_stream "$stream_key" "$stream_type" "$current_inode" "$rotation_gen"; then
            log_warn "register_stream failed, will retry stream=$stream_key next pass (state not advanced)"
            return 0
        fi
    fi

    collect_and_send_new_data "$file" "$offset" "$stream_key" "$rotation_gen" "$last_sequence"

    save_state "$state_file" "$NEW_OFFSET" "$rotation_gen" "$current_inode" "$NEW_LAST_SEQUENCE"
}

process_all_streams() {
    local globs="${logcollector_globs:-$DEFAULT_GLOB}"
    local files
    files="$(discover_files "$globs")"
    [ -z "$files" ] && return 0
    local f
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        process_file "$f"
    done <<< "$files"
}

# ============================================================================
# Main
# ============================================================================
main() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"

    if [ -z "${sk:-}" ] || [ -z "${apiaddrv2:-}" ]; then
        log_error "Missing required configuration (sk, apiaddrv2) in $CONFIG_FILE"
        exit 1
    fi

    # --- opt-in gate: 조용히 스킵 (기존 설치를 깨지 않는다) ------------------
    case "${logcollector_enabled:-}" in
        1|true|TRUE|yes|YES) : ;;
        *)
            log "logcollector_enabled not truthy (value='${logcollector_enabled:-<unset>}') - skipping (opt-in, see giipAgent.cnf.example)."
            exit 0
            ;;
    esac

    local dep
    for dep in jq curl gzip stat awk; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            log_error "$dep is required but not found. Aborting."
            exit 1
        fi
    done

    AGENT_API_BASE="${agentapibase:-}"
    if [ -z "$AGENT_API_BASE" ]; then
        AGENT_API_BASE="$(dirname "$apiaddrv2")"
    fi
    AGENT_KEY="$(resolve_agent_key)"

    # tSchedulerAgent 부트스트랩 (giip #1638) - 루프 시작 전 1회만 (loop iteration마다 아님)
    bootstrap_scheduler_agent "$AGENT_KEY" || \
        log_warn "bootstrap_scheduler_agent unsuccessful this pass - stream register/ingest will likely 404 until this succeeds (SP is idempotent; will retry next tick). continuing this pass anyway."

    # --- self-count guard: 이전 실행이 아직 도는 중이면 이번 tick은 skip -----
    local self_count
    self_count=$(ps aux 2>/dev/null | grep "[l]og_collector.sh" | wc -l | tr -d ' ')
    if [ -n "$self_count" ] && [ "$self_count" -gt 1 ]; then
        log "another log_collector.sh instance already running (count=$self_count) - skipping this invocation."
        exit 0
    fi

    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/giip_log_collector.XXXXXX" 2>/dev/null || echo "/tmp/giip_log_collector.$$")"
    mkdir -p "$WORK_DIR" 2>/dev/null
    trap 'rm -rf "$WORK_DIR"' EXIT
    mkdir -p "$STATE_DIR" "$QUEUE_DIR" 2>/dev/null

    local run_duration="${logcollector_run_duration_sec:-50}"
    local batch_interval="${logcollector_batch_interval_sec:-2}"

    log "=== log_collector: start (agentKey=$AGENT_KEY api_base=$AGENT_API_BASE once=$ONCE_MODE) ==="

    if [ "$ONCE_MODE" = true ]; then
        flush_retry_queue
        process_all_streams
        log "=== log_collector: single pass complete (--once) ==="
        exit 0
    fi

    local start_ts now_ts elapsed=0
    start_ts=$(date +%s)
    while :; do
        flush_retry_queue
        process_all_streams
        now_ts=$(date +%s)
        elapsed=$((now_ts - start_ts))
        if [ "$elapsed" -ge "$run_duration" ]; then
            break
        fi
        sleep "$batch_interval"
    done
    log "=== log_collector: run loop finished (elapsed=${elapsed}s) ==="
}

# 직접 실행될 때만 main 호출 - source해서 개별 함수 단위 테스트 가능하게 함
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
