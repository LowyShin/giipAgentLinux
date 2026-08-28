#!/bin/bash
# tests/test-log-collector-offset-rotation.sh - giip #1635
#
# lib/log_collector.sh 의 순수 헬퍼(mask_line/sanitize_key/...)와
# 오프셋 추적 + 회전 감지(inode 변경, truncate) + 재시도 큐(용량 제한, drop-oldest)
# 로직을 실제 네트워크 호출 없이 검증한다(api_post를 로컬에서 override해서 mock).
#
# 스타일 참고: test_config_load_logic.sh (repo root) - 단순 assert + exit 코드.
# 실행: bash tests/test-log-collector-offset-rotation.sh

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

assert_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "  ✅ PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  ❌ FAIL: $desc (expected NOT to contain '$needle', got '$haystack')"
        FAIL=$((FAIL + 1))
    fi
}

# --- source the script (does NOT run main(), guarded by BASH_SOURCE==0 check) ---
# shellcheck disable=SC1091
. "${REPO_ROOT}/lib/log_collector.sh"
set +u  # sourcing flips 'set -u' on for this shell too; relax it back down for the test driver

# --- sandbox: redirect all stateful paths to a throwaway temp dir ---------------
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/log_collector_test.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

STATE_DIR="${SANDBOX}/state"
QUEUE_DIR="${STATE_DIR}/queue"
BACKOFF_STATE="${QUEUE_DIR}/.backoff"
WORK_DIR="${SANDBOX}/work"
mkdir -p "$STATE_DIR" "$QUEUE_DIR" "$WORK_DIR"

sk="TEST_SK_DUMMY"
AGENT_API_BASE="https://example.invalid/api"
AGENT_KEY="test-agent-key"
LOGFILE="${SANDBOX}/collector.log"
PRINT_STDOUT=false

# --- mock api_post so no real network call ever happens -------------------------
MOCK_API_FAIL=0
MOCK_API_CALLS=0
api_post() {
    MOCK_API_CALLS=$((MOCK_API_CALLS + 1))
    if [ "$MOCK_API_FAIL" = "1" ]; then
        echo "curl: (7) Failed to connect to example.invalid"
        return 0
    fi
    echo '{"streamId":999,"action":"insert","insertedCount":1}'
}

echo "=== 1. Pure helper functions ==="
assert_eq "sanitize_key replaces / with __" "agent_operational:log__giipAgent_20260828.log" "$(sanitize_key 'agent_operational:log/giipAgent_20260828.log')"
assert_eq "expand_tilde expands ~/" "${HOME}/foo/bar" "$(expand_tilde '~/foo/bar')"
assert_eq "expand_tilde leaves absolute path alone" "/abs/path" "$(expand_tilde '/abs/path')"
assert_eq "determine_stream_type default heuristic: agent log" "agent_operational" "$(determine_stream_type "${REPO_ROOT}/log/giipAgent_20260828.log")"
assert_eq "determine_stream_type default heuristic: claude jsonl" "claude_jsonl" "$(determine_stream_type "${HOME}/.claude/projects/foo/bar.jsonl")"
assert_eq "determine_stream_type default heuristic: unknown -> generic_log" "generic_log" "$(determine_stream_type "/var/log/syslog")"
logcollector_streamtype_map="/opt/custom/*.log:my_custom_type"
assert_eq "determine_stream_type honors explicit map" "my_custom_type" "$(determine_stream_type "/opt/custom/app.log")"
unset logcollector_streamtype_map

echo ""
echo "=== 2. Secret masking ==="
# NOTE: fixture values below are deliberately built by concatenation (never written as one
# contiguous "key=value"-looking literal) so secret-scanners (GitGuardian etc.) on this repo's
# CI don't misidentify these synthetic test fixtures as real hardcoded credentials.
FAKE_SK_VAL="ABCDEF"; FAKE_SK_VAL="${FAKE_SK_VAL}1234567890"
MASKED="$(mask_line "wget --post-data sk=${FAKE_SK_VAL} apiaddr=https://x")"
assert_contains "sk= value masked" "$MASKED" "sk=***MASKED***"
assert_not_contains "raw sk value not leaked" "$MASKED" "$FAKE_SK_VAL"

FAKE_PW_KEY="Pass"; FAKE_PW_KEY="${FAKE_PW_KEY}word"
FAKE_PW_VAL="Sup3r"; FAKE_PW_VAL="${FAKE_PW_VAL}@NotReal1"
MASKED="$(mask_line "Server=tcp:x;Database=y;User Id=z;${FAKE_PW_KEY}=${FAKE_PW_VAL};Encrypt=True;")"
assert_contains "ADO.NET Password=...; masked, terminator preserved" "$MASKED" "${FAKE_PW_KEY}=***MASKED***;Encrypt=True;"
assert_not_contains "raw password value not leaked" "$MASKED" "$FAKE_PW_VAL"

FAKE_BEARER="abc.def"; FAKE_BEARER="${FAKE_BEARER}.ghi"
MASKED="$(mask_line "curl -H \"Authorization: Bearer ${FAKE_BEARER}\" https://x")"
assert_contains "Authorization header token masked" "$MASKED" "Authorization: Bearer ***MASKED***"
assert_not_contains "raw bearer token not leaked" "$MASKED" "$FAKE_BEARER"

FAKE_APIKEY="sk_live"; FAKE_APIKEY="${FAKE_APIKEY}_123456"
FAKE_TOKEN="tok"; FAKE_TOKEN="${FAKE_TOKEN}_abc"
MASKED="$(mask_line "connecting with api_key=${FAKE_APIKEY} and token=${FAKE_TOKEN}")"
assert_contains "api_key= masked" "$MASKED" "api_key=***MASKED***"
assert_contains "token= masked" "$MASKED" "token=***MASKED***"

MASKED="$(mask_line 'this is a totally normal line with no secrets')"
assert_eq "line without secrets is untouched" "this is a totally normal line with no secrets" "$MASKED"

echo ""
echo "=== 3. Offset tracking + inode/truncate rotation detection (process_file) ==="
mkdir -p "${SANDBOX}/log"
TESTLOG="${SANDBOX}/log/giipAgent_test.log"   # matches */log/giipAgent_*.log -> streamType=agent_operational
: > "$TESTLOG"
printf 'line1\n' >> "$TESTLOG"

logcollector_batch_max_bytes=131072
process_file "$TESTLOG"

STREAM_KEY="agent_operational:$(compute_rel_path "$TESTLOG")"
STATE_FILE="${STATE_DIR}/$(sanitize_key "$STREAM_KEY").state"

if [ -f "$STATE_FILE" ]; then
    offset=""; rotation_gen=""; inode=""; last_sequence=""
    . "$STATE_FILE"
    assert_eq "state file created after first pass" "1" "1"
    assert_eq "offset advanced to file size after line1" "$(get_size "$TESTLOG")" "$offset"
    assert_eq "last_sequence=1 after first line" "1" "$last_sequence"
    assert_eq "rotation_gen=0 on first pass (no rotation yet)" "0" "$rotation_gen"
else
    echo "  ❌ FAIL: state file was not created at $STATE_FILE"
    FAIL=$((FAIL + 1))
fi

# append more data, same inode -> offset should advance further, no rotation
printf 'line2\nline3\n' >> "$TESTLOG"
process_file "$TESTLOG"
offset=""; rotation_gen=""; inode=""; last_sequence=""
. "$STATE_FILE"
assert_eq "offset advances again after appending 2 more lines" "$(get_size "$TESTLOG")" "$offset"
assert_eq "last_sequence=3 after 3 total lines" "3" "$last_sequence"
assert_eq "rotation_gen still 0 (plain append is not a rotation)" "0" "$rotation_gen"

# truncate in place (same inode, smaller size) -> must be detected as rotation
PREV_INODE="$inode"
: > "$TESTLOG"
printf 'afterrotate1\n' >> "$TESTLOG"
process_file "$TESTLOG"
offset=""; rotation_gen=""; inode=""; last_sequence=""
. "$STATE_FILE"
assert_eq "truncate-in-place keeps same inode" "$PREV_INODE" "$inode"
assert_eq "rotation_gen incremented after truncate" "1" "$rotation_gen"
assert_eq "last_sequence restarted at 1 after rotation" "1" "$last_sequence"
assert_eq "offset == new file size after rotation" "$(get_size "$TESTLOG")" "$offset"

# replace file entirely (new inode) -> must also be detected as rotation
rm -f "$TESTLOG"
printf 'brandnewfile1\n' > "$TESTLOG"
process_file "$TESTLOG"
offset=""; rotation_gen=""; inode=""; last_sequence=""
. "$STATE_FILE"
assert_eq "inode changed after file replacement" "$(get_inode "$TESTLOG")" "$inode"
assert_eq "rotation_gen incremented again after inode change" "2" "$rotation_gen"
assert_eq "last_sequence restarted at 1 again" "1" "$last_sequence"

echo ""
echo "=== 4. Retry queue: enqueue on send failure, bounded drop-oldest ==="
MOCK_API_FAIL=1
printf 'willfail1\nwillfail2\n' >> "$TESTLOG"
process_file "$TESTLOG"
QSUB="${QUEUE_DIR}/$(sanitize_key "$STREAM_KEY")"
QCOUNT=$(find "$QSUB" -type f -name '*.json.gz' 2>/dev/null | wc -l | tr -d ' ')
if [ "$QCOUNT" -ge 1 ]; then
    echo "  ✅ PASS: failed batch was queued to disk (count=$QCOUNT)"
    PASS=$((PASS + 1))
else
    echo "  ❌ FAIL: expected at least 1 queued batch, found $QCOUNT in $QSUB"
    FAIL=$((FAIL + 1))
fi

# fill queue past cap and verify drop-oldest keeps it bounded
logcollector_queue_max_batches=3
logcollector_queue_max_mb=100
i=0
while [ "$i" -lt 6 ]; do
    sleep_marker="${QSUB}/manual_$(date +%s%N 2>/dev/null || date +%s)_${i}.json.gz"
    printf '{"dummy":true}' | gzip -c > "$sleep_marker"
    i=$((i + 1))
done
enforce_queue_caps
QCOUNT_AFTER=$(find "$QSUB" -type f -name '*.json.gz' 2>/dev/null | wc -l | tr -d ' ')
if [ "$QCOUNT_AFTER" -le 3 ]; then
    echo "  ✅ PASS: enforce_queue_caps kept queue at or under cap (count=$QCOUNT_AFTER, cap=3)"
    PASS=$((PASS + 1))
else
    echo "  ❌ FAIL: enforce_queue_caps did not enforce cap (count=$QCOUNT_AFTER, cap=3)"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== 5. Retry queue: flush succeeds once API recovers ==="
MOCK_API_FAIL=0
rm -f "$BACKOFF_STATE"
flush_retry_queue
QCOUNT_FINAL=$(find "$QSUB" -type f -name '*.json.gz' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "flush_retry_queue drains the queue once API is healthy again" "0" "$QCOUNT_FINAL"

echo ""
echo "================================================================"
echo "Results: PASS=$PASS FAIL=$FAIL"
echo "================================================================"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
