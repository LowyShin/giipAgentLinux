#!/bin/bash
# tests/test-scheduler-agent-run.sh - giip #2390 (csn=47)
#
# lib/scheduler_agent_run.sh 의 run start/end 기록 로직을 실제 네트워크 호출 없이
# 검증한다(curl을 로컬 shell function으로 override해서 mock).
#
# 스타일 참고: tests/test-log-collector-offset-rotation.sh 섹션 6
# (bootstrap_scheduler_agent) - 동일한 apiaddrv2 직접 호출 계약이라 mock 방식도 동일.
# 실행: bash tests/test-scheduler-agent-run.sh

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
PASS=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  ✅ PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  ❌ FAIL: $desc (expected='$expected' actual='$actual')"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  ✅ PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  ❌ FAIL: $desc (expected to contain '$needle', got '$haystack')"
        FAIL=$((FAIL + 1))
    fi
}

# --- source the script (defines functions only, no side effects at source time) ---
# shellcheck disable=SC1091
. "${REPO_ROOT}/lib/scheduler_agent_run.sh"
set +u  # sourcing does not set -u itself here, but keep the test driver relaxed for safety

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/scheduler_agent_run_test.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

sk="TEST_SK_DUMMY"
apiaddrv2="https://example.invalid/api/giipApiSk2"
logcollector_agentkey="test-fixed-agent-key"  # sar_resolve_agent_key: config override 최우선

MOCK_CURL_RESPONSE=""
MOCK_CURL_ARGS_FILE="${SANDBOX}/curl_last_args.txt"
# NOTE: sar_api_post captures curl's stdout via command substitution ($(...)), which
# forks a subshell - a plain variable assignment inside this mock would not survive
# back to the parent shell, so args are recorded to a file instead.
curl() {
    printf '%s' "$*" > "$MOCK_CURL_ARGS_FILE"
    printf '%s' "$MOCK_CURL_RESPONSE"
}
get_mock_curl_args() { cat "$MOCK_CURL_ARGS_FILE" 2>/dev/null; }

# giip #2477: 등록/백오프 상태파일은 반드시 샌드박스 안에 둔다(실 설치 경로 오염 방지).
export SAR_REG_STATE_PATH_OVERRIDE="${SANDBOX}/.giip_scheduler_agent_state.json"
reset_reg_state() { rm -f "$SAR_REG_STATE_PATH_OVERRIDE" 2>/dev/null; return 0; }

# giip #2477: jsondata 가 비어 있는지(= ISN 161 자동추가가 꺼지는지) 검사한다.
assert_jsondata_empty() {
    local desc="$1" args
    args="$(get_mock_curl_args)"
    if [[ "$args" == *"jsondata="* ]] && [[ "$args" != *"jsondata={"* ]]; then
        echo "  ✅ PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  ❌ FAIL: $desc (args='$args')"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== 1. sar_resolve_agent_key ==="
assert_eq "config override (logcollector_agentkey) wins" "test-fixed-agent-key" "$(sar_resolve_agent_key)"

echo ""
echo "=== 1b. sar_reg_sql_literal (giip #2477 - 디스패처 토큰 안전성) ==="
assert_eq "wraps a plain value in single quotes" "'abc'" "$(sar_reg_sql_literal "abc")"
assert_eq "empty value becomes an empty literal" "''" "$(sar_reg_sql_literal "")"
assert_eq "strips single quotes inside the value (token boundary)" "'its ok'" "$(sar_reg_sql_literal "it's ok")"
assert_eq "collapses newlines to spaces (text must stay one line)" "'a b'" "$(sar_reg_sql_literal "$(printf 'a\nb')")"
assert_eq "keeps spaces (quoted token survives dispatcher tokenizer)" "'a b c'" "$(sar_reg_sql_literal "a b c")"

echo ""
echo "=== 2. sar_run_start ==="
reset_reg_state
MOCK_CURL_RESPONSE='{"data":[{"RstVal":200,"run_id":1,"agent_id":1,"action":"insert"}]}'
SAR_STARTED=0
sar_run_start "scheduled"
assert_eq "sar_run_start sets SAR_STARTED=1 on RstVal=200" "1" "$SAR_STARTED"
assert_contains "curl called with SchedulerAgentRunStart + SQL literals" "$(get_mock_curl_args)" "text=SchedulerAgentRunStart '${SAR_RUN_ID_KEY}' 'test-fixed-agent-key' 'scheduled'"
assert_contains "curl called with token=sk" "$(get_mock_curl_args)" "token=${sk}"
# giip #2477 회귀 가드: 옛 형태(파라미터 이름 + jsondata)로 되돌아가면 @totalIssueCount
# INT 자리에 JSON 이 들어가 "Error converting data type nvarchar to int" 가 재발한다.
if [[ "$(get_mock_curl_args)" == *"text=SchedulerAgentRunStart runIdKey"* ]]; then
    echo "  ❌ FAIL: regression - parameter-NAME form is back (ISN 161 auto-append would fire)"
    FAIL=$((FAIL + 1))
else
    echo "  ✅ PASS: parameter-NAME form is not used"
    PASS=$((PASS + 1))
fi
assert_jsondata_empty "run start sends an empty jsondata"
FIRST_RUN_ID_KEY="$SAR_RUN_ID_KEY"
[ -n "$FIRST_RUN_ID_KEY" ] && { echo "  ✅ PASS: SAR_RUN_ID_KEY populated (non-empty)"; PASS=$((PASS+1)); } || { echo "  ❌ FAIL: SAR_RUN_ID_KEY empty"; FAIL=$((FAIL+1)); }

echo ""
echo "=== 3. sar_run_end (after successful start) ==="
MOCK_CURL_RESPONSE='{"data":[{"RstVal":200}]}'
sar_run_end "SUCCEEDED" "0"
assert_contains "curl called with SchedulerAgentRunEnd + SQL literals in SP order" "$(get_mock_curl_args)" "text=SchedulerAgentRunEnd '${FIRST_RUN_ID_KEY}' 'test-fixed-agent-key' 'SUCCEEDED' '0' '0' '0' '0'"
assert_jsondata_empty "run end sends an empty jsondata"

echo ""
echo "=== 4. sar_run_end with non-zero exit code ==="
SAR_STARTED=1  # simulate a prior successful start
sar_run_end "FAILED" "17"
assert_contains "status=FAILED and exitCode=17 land in the right positions" "$(get_mock_curl_args)" "'FAILED' '0' '0' '0' '17'"
sar_run_end "FAILED" "not-a-number"
assert_contains "non-numeric exit code falls back to 1" "$(get_mock_curl_args)" "'FAILED' '0' '0' '0' '1'"

echo ""
echo "=== 5. sar_run_end is a no-op when start never succeeded ==="
SAR_STARTED=0
: > "$MOCK_CURL_ARGS_FILE"
sar_run_end "SUCCEEDED" "0"
assert_eq "no curl call recorded when SAR_STARTED=0" "" "$(get_mock_curl_args)"

echo ""
echo "=== 6. sar_run_start fails gracefully on non-200 RstVal ==="
reset_reg_state
MOCK_CURL_RESPONSE='{"data":[{"RstVal":401,"RstMsg":"Unauthorized"}]}'
SAR_STARTED=0
SAR_RC=0
sar_run_start "scheduled" || SAR_RC=$?
assert_eq "sar_run_start returns 1 on non-200" "1" "$SAR_RC"
assert_eq "SAR_STARTED stays 0 on failure" "0" "$SAR_STARTED"

echo ""
echo "=== 6b. giip #2477: 404 -> tSchedulerAgent 자가등록 + 1회 재시도 ==="
reset_reg_state
# 1번째 호출(RunStart)=404, 2번째(SchedulerAgentUpsert)=200, 3번째(RunStart 재시도)=200
MOCK_SEQ_FILE="${SANDBOX}/mock_seq.txt"
MOCK_CALLS_FILE="${SANDBOX}/mock_calls.txt"
echo 0 > "$MOCK_SEQ_FILE"
: > "$MOCK_CALLS_FILE"
curl() {
    local n
    n="$(cat "$MOCK_SEQ_FILE")"
    n=$((n + 1))
    echo "$n" > "$MOCK_SEQ_FILE"
    printf '%s' "$*" > "$MOCK_CURL_ARGS_FILE"
    printf '%s\n' "$*" >> "$MOCK_CALLS_FILE"
    case "$n" in
        1) printf '%s' '{"data":[{"RstVal":404,"RstMsg":"Agent not found"}]}' ;;
        2) printf '%s' '{"data":[{"RstVal":200,"RstMsg":"Agent registered"}]}' ;;
        *) printf '%s' '{"data":[{"RstVal":200,"run_id":9,"agent_id":9,"action":"insert"}]}' ;;
    esac
}
SAR_STARTED=0
SAR_RC=0
sar_run_start "scheduled" || SAR_RC=$?
assert_eq "sar_run_start succeeds after self-registration retry" "0" "$SAR_RC"
assert_eq "SAR_STARTED=1 after self-registration retry" "1" "$SAR_STARTED"
assert_eq "exactly 3 API calls (start -> upsert -> start retry)" "3" "$(cat "$MOCK_SEQ_FILE")"
assert_contains "2nd call is SchedulerAgentUpsert" "$(sed -n '2p' "$MOCK_CALLS_FILE")" "text=SchedulerAgentUpsert 'test-fixed-agent-key'"
assert_contains "3rd call is the SchedulerAgentRunStart retry" "$(sed -n '3p' "$MOCK_CALLS_FILE")" "text=SchedulerAgentRunStart"
[ -f "$SAR_REG_STATE_PATH_OVERRIDE" ] && { echo "  ❌ FAIL: no failure state should be written on recovery"; FAIL=$((FAIL+1)); } || { echo "  ✅ PASS: no failure state written when recovery succeeds"; PASS=$((PASS+1)); }

echo ""
echo "=== 6c. giip #2477: 자가등록도 실패하면 실패 누적 + 백오프 ==="
reset_reg_state
curl() {
    printf '%s' "$*" > "$MOCK_CURL_ARGS_FILE"
    printf '%s' '{"data":[{"RstVal":404,"RstMsg":"Agent not found"}]}'
}
SAR_STARTED=0
SAR_RC=0
sar_run_start "scheduled" || SAR_RC=$?
assert_eq "sar_run_start returns 1 when self-registration also fails" "1" "$SAR_RC"
assert_eq "failure state records consecutiveCount=1" "1" "$(jq -r '.consecutiveCount' "$SAR_REG_STATE_PATH_OVERRIDE")"
assert_eq "failure state records totalCount=1" "1" "$(jq -r '.totalCount' "$SAR_REG_STATE_PATH_OVERRIDE")"
assert_contains "failure reason is recorded" "$(jq -r '.lastReason' "$SAR_REG_STATE_PATH_OVERRIDE")" "404"
FIRST_SEEN="$(jq -r '.firstSeenUtc' "$SAR_REG_STATE_PATH_OVERRIDE")"
[ -n "$FIRST_SEEN" ] && [ "$FIRST_SEEN" != "null" ] && { echo "  ✅ PASS: firstSeenUtc recorded"; PASS=$((PASS+1)); } || { echo "  ❌ FAIL: firstSeenUtc missing"; FAIL=$((FAIL+1)); }

# 백오프 창 안에서는 API 호출 자체를 하지 않는다(서버 로그 폭주 억제)
: > "$MOCK_CURL_ARGS_FILE"
SAR_STARTED=0
SAR_RC=0
sar_run_start "scheduled" || SAR_RC=$?
assert_eq "backoff window suppresses the call entirely" "" "$(get_mock_curl_args)"
assert_eq "suppressed run still returns 1" "1" "$SAR_RC"
assert_eq "suppressed run does not inflate totalCount" "1" "$(jq -r '.totalCount' "$SAR_REG_STATE_PATH_OVERRIDE")"

# 백오프 만료 -> 반드시 다시 시도한다(영구 침묵 금지). 성공하면 백오프만 해제되고
# firstSeenUtc/totalCount 통계는 보존된다.
jq '.nextAttemptEpoch = 1' "$SAR_REG_STATE_PATH_OVERRIDE" > "${SAR_REG_STATE_PATH_OVERRIDE}.new" && mv -f "${SAR_REG_STATE_PATH_OVERRIDE}.new" "$SAR_REG_STATE_PATH_OVERRIDE"
curl() {
    printf '%s' "$*" > "$MOCK_CURL_ARGS_FILE"
    printf '%s' '{"data":[{"RstVal":200,"run_id":5}]}'
}
SAR_STARTED=0
sar_run_start "scheduled"
assert_eq "retries once the backoff window expires" "1" "$SAR_STARTED"
assert_eq "backoff cleared on recovery" "0" "$(jq -r '.consecutiveCount' "$SAR_REG_STATE_PATH_OVERRIDE")"
assert_eq "cumulative totalCount is preserved (not silently dropped)" "1" "$(jq -r '.totalCount' "$SAR_REG_STATE_PATH_OVERRIDE")"
assert_eq "firstSeenUtc is preserved" "$FIRST_SEEN" "$(jq -r '.firstSeenUtc' "$SAR_REG_STATE_PATH_OVERRIDE")"

echo ""
echo "=== 6d. giip #2477: 백오프 곡선 5/10/20/40/60(상한), 0 반환 금지 ==="
assert_eq "0 failures -> 0 minutes" "0" "$(sar_reg_backoff_minutes 0)"
assert_eq "1st failure -> 5 minutes" "5" "$(sar_reg_backoff_minutes 1)"
assert_eq "2nd failure -> 10 minutes" "10" "$(sar_reg_backoff_minutes 2)"
assert_eq "3rd failure -> 20 minutes" "20" "$(sar_reg_backoff_minutes 3)"
assert_eq "4th failure -> 40 minutes" "40" "$(sar_reg_backoff_minutes 4)"
assert_eq "5th failure -> capped at 60 minutes" "60" "$(sar_reg_backoff_minutes 5)"
assert_eq "50th failure -> still capped at 60 minutes" "60" "$(sar_reg_backoff_minutes 50)"

echo ""
echo "=== 6e. giip #2477: 상태파일이 깨져 있어도 죽지 않는다 ==="
printf 'not a json' > "$SAR_REG_STATE_PATH_OVERRIDE"
assert_eq "corrupt state file is treated as 'no backoff'" "1" "$(sar_reg_backoff_active; echo $?)"
curl() {
    printf '%s' "$*" > "$MOCK_CURL_ARGS_FILE"
    printf '%s' '{"data":[{"RstVal":401}]}'
}
SAR_STARTED=0
sar_run_start "scheduled" || true
assert_eq "corrupt state file is rebuilt on the next failure" "1" "$(jq -r '.totalCount' "$SAR_REG_STATE_PATH_OVERRIDE")"

# 이후 섹션은 원래의 단순 mock 으로 되돌린다
reset_reg_state
curl() {
    printf '%s' "$*" > "$MOCK_CURL_ARGS_FILE"
    printf '%s' "$MOCK_CURL_RESPONSE"
}

echo ""
echo "=== 7. sar_run_start / sar_run_end skip cleanly when sk/apiaddrv2 missing ==="
(
    unset sk apiaddrv2
    SAR_STARTED=0
    RC=0
    sar_run_start "scheduled" || RC=$?
    assert_eq "sar_run_start returns 1 when sk/apiaddrv2 unset" "1" "$RC"
)

echo ""
echo "=== 8. sar_run_end_trap maps exit code to SUCCEEDED/FAILED ==="
MOCK_CURL_RESPONSE='{"data":[{"RstVal":200}]}'
SAR_STARTED=1
SAR_RUN_ID_KEY="trap-test-run"
SAR_AGENT_KEY="trap-test-agent"
( exit 0 ) ; sar_run_end_trap
assert_contains "trap with exit 0 reports SUCCEEDED" "$(get_mock_curl_args)" "'trap-test-run' 'trap-test-agent' 'SUCCEEDED'"
( exit 3 ) ; sar_run_end_trap
assert_contains "trap with exit 3 reports FAILED" "$(get_mock_curl_args)" "'trap-test-run' 'trap-test-agent' 'FAILED'"
assert_contains "trap with exit 3 reports exitCode=3" "$(get_mock_curl_args)" "'FAILED' '0' '0' '0' '3'"

unset -f curl

echo ""
echo "================================================================"
echo "Results: PASS=$PASS FAIL=$FAIL"
echo "================================================================"
[ "$FAIL" -eq 0 ]
