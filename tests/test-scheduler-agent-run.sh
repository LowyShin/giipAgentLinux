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

echo "=== 1. sar_resolve_agent_key ==="
assert_eq "config override (logcollector_agentkey) wins" "test-fixed-agent-key" "$(sar_resolve_agent_key)"

echo ""
echo "=== 2. sar_run_start ==="
MOCK_CURL_RESPONSE='{"data":[{"RstVal":200,"run_id":1,"agent_id":1,"action":"insert"}]}'
SAR_STARTED=0
sar_run_start "scheduled"
assert_eq "sar_run_start sets SAR_STARTED=1 on RstVal=200" "1" "$SAR_STARTED"
assert_contains "curl called with SchedulerAgentRunStart text param" "$(get_mock_curl_args)" "text=SchedulerAgentRunStart runIdKey agentKey executionMode"
assert_contains "curl called with token=sk" "$(get_mock_curl_args)" "token=${sk}"
assert_contains "jsondata carries agentKey from sar_resolve_agent_key" "$(get_mock_curl_args)" "\"agentKey\": \"test-fixed-agent-key\""
assert_contains "jsondata carries executionMode=scheduled" "$(get_mock_curl_args)" "\"executionMode\": \"scheduled\""
FIRST_RUN_ID_KEY="$SAR_RUN_ID_KEY"
[ -n "$FIRST_RUN_ID_KEY" ] && { echo "  ✅ PASS: SAR_RUN_ID_KEY populated (non-empty)"; PASS=$((PASS+1)); } || { echo "  ❌ FAIL: SAR_RUN_ID_KEY empty"; FAIL=$((FAIL+1)); }

echo ""
echo "=== 3. sar_run_end (after successful start) ==="
MOCK_CURL_RESPONSE='{"data":[{"RstVal":200}]}'
sar_run_end "SUCCEEDED" "0"
assert_contains "curl called with SchedulerAgentRunEnd text param" "$(get_mock_curl_args)" "text=SchedulerAgentRunEnd runIdKey agentKey status processedCount skippedCount failedCount exitCode"
assert_contains "jsondata carries same runIdKey as start" "$(get_mock_curl_args)" "\"runIdKey\": \"${FIRST_RUN_ID_KEY}\""
assert_contains "jsondata carries status=SUCCEEDED" "$(get_mock_curl_args)" "\"status\": \"SUCCEEDED\""
assert_contains "jsondata carries exitCode=0" "$(get_mock_curl_args)" "\"exitCode\": 0"

echo ""
echo "=== 4. sar_run_end with non-zero exit code ==="
SAR_STARTED=1  # simulate a prior successful start
sar_run_end "FAILED" "17"
assert_contains "jsondata carries status=FAILED" "$(get_mock_curl_args)" "\"status\": \"FAILED\""
assert_contains "jsondata carries exitCode=17" "$(get_mock_curl_args)" "\"exitCode\": 17"

echo ""
echo "=== 5. sar_run_end is a no-op when start never succeeded ==="
SAR_STARTED=0
: > "$MOCK_CURL_ARGS_FILE"
sar_run_end "SUCCEEDED" "0"
assert_eq "no curl call recorded when SAR_STARTED=0" "" "$(get_mock_curl_args)"

echo ""
echo "=== 6. sar_run_start fails gracefully on non-200 RstVal ==="
MOCK_CURL_RESPONSE='{"data":[{"RstVal":404,"RstMsg":"Agent not found"}]}'
SAR_STARTED=0
SAR_RC=0
sar_run_start "scheduled" || SAR_RC=$?
assert_eq "sar_run_start returns 1 on non-200" "1" "$SAR_RC"
assert_eq "SAR_STARTED stays 0 on failure" "0" "$SAR_STARTED"

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
assert_contains "trap with exit 0 reports SUCCEEDED" "$(get_mock_curl_args)" "\"status\": \"SUCCEEDED\""
( exit 3 ) ; sar_run_end_trap
assert_contains "trap with exit 3 reports FAILED" "$(get_mock_curl_args)" "\"status\": \"FAILED\""
assert_contains "trap with exit 3 reports exitCode=3" "$(get_mock_curl_args)" "\"exitCode\": 3"

unset -f curl

echo ""
echo "================================================================"
echo "Results: PASS=$PASS FAIL=$FAIL"
echo "================================================================"
[ "$FAIL" -eq 0 ]
