#!/bin/bash
# Test: scripts/cleanup_nameless_lssn.sh (giip 2948) - offline, curl stubbed, no network
#   (A) dryrun (jq and awk parsers): counts, skips, invalid escapes tolerated, no write call
#   (B) apply: rollback SQL before the first delete, exact LSvrDel request shape,
#       min-lssn / skip rows untouched, verify re-fetch, KVS summary, rc 0
#   (C) re-run apply is idempotent (nothing left -> no delete call)
#   (D) first 3 deletes fail -> abort rc 4 after exactly 3 calls
#   (E) 10 consecutive failures after successes -> abort rc 4
#   (F) time budget reached -> rc 3 "re-run apply"
#   (G) fail-closed: error response / empty data / unknown schema -> rc 2, no delete call
#   (H) unreplaced {{CustomVariables}} argument is ignored (-> dryrun)
#   (I) the SK never appears in the output
#   (J) CQE launcher body: missing script -> exit 1; present -> args passed, exit code kept
#   (K) scattered failures -> rc 5 (incomplete)
#
# Usage: bash tests/test-cleanup-nameless-lssn.sh

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TARGET="${SCRIPT_DIR}/../scripts/cleanup_nameless_lssn.sh"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/giip_cleanup_test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

TEST_SK="0123456789abcdef0123456789abcdef"
printf 'sk="%s"\r\nlssn="71295"\r\napiaddrv2="https://example.invalid/api/giipApiSk2"\r\n' "$TEST_SK" > "$WORK/giipAgent.cnf"

# --- curl stub -------------------------------------------------------------
# list  : built from $STUB_DIR/base minus $STUB_DIR/deleted (pretty JSON, CRLF, one invalid escape)
# LSvrDel: RstVal from $STUB_DEL_MODE: ok | fail | fail_from:<lssn> | fail_list:<l1,l2>
# KVSPut: RstVal 200
mkdir -p "$WORK/bin"
cat > "$WORK/bin/curl" <<'STUB'
#!/bin/bash
out=""; text=""; json=""; args="$*"
while [ $# -gt 0 ]; do
	case "$1" in
		-o) out="$2"; shift ;;
		--data-urlencode)
			case "$2" in text=*) text="${2#text=}" ;; jsondata=*) json="${2#jsondata=}" ;; esac
			shift ;;
	esac
	shift
done
echo "$args" >> "$STUB_DIR/calls.log"
emit() { if [ -n "$out" ]; then cat > "$out"; else cat; fi; }
case "$text" in
	LSvrListForIssue)
		[ -n "${STUB_LIST_RAW+x}" ] && { printf '%s' "$STUB_LIST_RAW" | emit; exit 0; }
		{
			printf '{\r\n  "debug": {\r\n    "_debug_originalText": "text=LSvrListForIssue&token=%s"\r\n  },\r\n  "data": [\r\n' "$STUB_SK"
			first=1
			while IFS='|' read -r l hb hn os; do
				grep -qx "$l" "$STUB_DIR/deleted" 2>/dev/null && continue
				[ $first -eq 1 ] || printf '    },\r\n'
				first=0
				# @DEB@ = the real-world broken value: raw backslash + LF inside the string (no CR)
				[ "$os" = "@DEB@" ] && os=$(printf '"Debian GNU/Linux 8 \\\n \\\\l"')
				printf '    {\r\n      "last_heartbeat": %s,\r\n      "hostname": %s,\r\n      "lssn": %s,\r\n      "os": %s\r\n' "$hb" "$hn" "$l" "$os"
			done < "$STUB_DIR/base"
			[ $first -eq 1 ] || printf '    }\r\n'
			printf '  ]\r\n}'
		} | emit
		;;
	"LSvrDel lssn")
		l=$(printf '%s' "$json" | grep -oE '[0-9]+')
		rv=200
		case "${STUB_DEL_MODE:-ok}" in
			fail) rv=404 ;;
			fail_from:*) [ "$l" -ge "${STUB_DEL_MODE#fail_from:}" ] && rv=404 ;;
			fail_list:*) echo ",${STUB_DEL_MODE#fail_list:}," | grep -q ",$l," && rv=404 ;;
		esac
		[ "$rv" = 200 ] && echo "$l" >> "$STUB_DIR/deleted"
		printf '{\r\n  "RstVal": %s,\r\n  "RstMsg": "x"\r\n}' "$rv" | emit
		;;
	"LsvrDetail lssn")
		l=$(printf '%s' "$json" | grep -oE '[0-9]+')
		if [ "${STUB_DETAIL:-ok}" = ok ]; then
			printf '{\r\n  "SKey": "groupsecret-must-not-leak",\r\n  "CSn": 70434,\r\n  "LSsn": %s\r\n}' "$l" | emit
		else
			printf 'Api executed successfully, but no results returned.' | emit
		fi
		;;
	"KVSPut kType kKey kFactor")
		echo "$json" >> "$STUB_DIR/kvs.log"
		printf '{"data":[{"RstVal":"200"}]}' | emit
		;;
	*) printf 'unexpected' | emit ;;
esac
exit 0
STUB
chmod +x "$WORK/bin/curl"
export PATH="$WORK/bin:$PATH"
export STUB_SK="$TEST_SK"
export GIIP_CLEANUP_SLEEP=0
export TMPDIR="$WORK"   # per-lssn result files land inside $WORK
unset sk lssn apiaddrv2

# base list: 71290..71295 normal, 71296..71315 nameless except 71300 (has hostname)
# and 71305 (has heartbeat); 71311 has an empty-string hostname/os (still a target);
# one old row with the real-world invalid escape (raw backslash + newline, see @DEB@ in the stub).
reset_state() {
	export STUB_DIR="$WORK/state$1"; mkdir -p "$STUB_DIR"; : > "$STUB_DIR/deleted"; : > "$STUB_DIR/calls.log"; : > "$STUB_DIR/kvs.log"
	{
		echo '417|null|"martmoa-pm01"|@DEB@'
		for l in 71290 71291 71292 71293 71294; do echo "$l|\"2026-09-20T00:00:00\"|\"host$l\"|\"Ubuntu\""; done
		echo '71295|"2026-09-24T03:00:00"|"LOWYDN01"|"windows 10.0"'
		for l in $(seq 71296 71315); do
			case $l in
				71300) echo "$l|null|\"real-host\"|null" ;;
				71305) echo "$l|\"2026-09-24T01:00:00\"|null|null" ;;
				71311) echo "$l|null|\"\"|\"\"" ;;
				*) echo "$l|null|null|null" ;;
			esac
		done
	} > "$STUB_DIR/base"
}
EXPECTED_TARGETS=18   # 71296..71315 = 20, minus 71300 and 71305

PASS=0; FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS+1)); }
ng() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
dels() { grep -c 'text=LSvrDel lssn' "$STUB_DIR/calls.log"; }
run() { bash "$TARGET" --config "$WORK/giipAgent.cnf" "$@" > "$STUB_DIR/out" 2>&1; echo $? > "$STUB_DIR/rc"; }
rc() { cat "$STUB_DIR/rc"; }

echo "=== (A) dryrun ==="
for parser in jq awk; do
	if [ "$parser" = jq ] && ! command -v jq >/dev/null 2>&1; then echo "  SKIP: jq not installed"; continue; fi
	reset_state "A$parser"
	if [ "$parser" = awk ]; then export GIIP_CLEANUP_NO_JQ=1; else unset GIIP_CLEANUP_NO_JQ; fi
	# prove the stub really emits JSON that strict parsers reject
	if [ "$parser" = jq ]; then
		curl -X POST x --data-urlencode text=LSvrListForIssue -o "$STUB_DIR/raw.json"
		jq . "$STUB_DIR/raw.json" >/dev/null 2>&1 && ng "stub list should be invalid JSON" || ok "stub list is invalid JSON for jq (raw backslash+newline)"
		: > "$STUB_DIR/calls.log"
	fi
	run
	line=$(grep '\[before\]' "$STUB_DIR/out" | head -1)
	[ "$(rc)" = 0 ] && ok "[$parser] rc=0" || ng "[$parser] rc=$(rc)"
	echo "$line" | grep -q "parser=$parser total=27 rows_with_all_keys=27 targets=$EXPECTED_TARGETS skips_in_range=2 min_target=71296 max_target=71315" \
		&& ok "[$parser] counts: $line" || { ng "[$parser] counts: $line"; cat "$STUB_DIR/out"; }
	grep -q '71300 hostname' "$STUB_DIR/out" && grep -q '71305 heartbeat' "$STUB_DIR/out" && ok "[$parser] skips with reasons" || ng "[$parser] skip reasons missing"
	grep -q 'target ranges: 71296-71299,71301-71304,71306-71315' "$STUB_DIR/out" && ok "[$parser] compact ranges" || ng "[$parser] ranges: $(grep 'target ranges' "$STUB_DIR/out")"
	[ "$(dels)" = 0 ] && [ ! -s "$STUB_DIR/kvs.log" ] && [ "$(grep -c . "$STUB_DIR/calls.log")" = 2 ] \
		&& grep -q 'text=LsvrDetail lssn' "$STUB_DIR/calls.log" \
		&& ok "[$parser] only read calls (list + LsvrDetail preflight), no delete, no KVS" || ng "[$parser] unexpected calls: $(cat "$STUB_DIR/calls.log")"
	grep -q 'auth preflight (read-only LsvrDetail 71296): .*CSn=70434) - OK' "$STUB_DIR/out" && ok "[$parser] auth preflight OK line" || ng "[$parser] preflight: $(grep preflight "$STUB_DIR/out")"
done
unset GIIP_CLEANUP_NO_JQ

echo "=== (B) apply, all succeed ==="
reset_state B; run --action apply
[ "$(rc)" = 0 ] && ok "rc=0" || { ng "rc=$(rc)"; cat "$STUB_DIR/out"; }
[ "$(dels)" = "$EXPECTED_TARGETS" ] && ok "$EXPECTED_TARGETS LSvrDel calls" || ng "LSvrDel calls=$(dels)"
grep -q 'UPDATE tLSvr SET lsDeldt = NULL WHERE lsDeldt IS NOT NULL AND (LSsn BETWEEN 71296 AND 71299 OR LSsn BETWEEN 71301 AND 71304 OR LSsn BETWEEN 71306 AND 71315);' "$STUB_DIR/out" \
	&& ok "rollback SQL with compact ranges" || ng "rollback SQL: $(grep UPDATE "$STUB_DIR/out")"
[ "$(grep -n 'ROLLBACK SQL' "$STUB_DIR/out" | cut -d: -f1)" -lt "$(grep -n 'APPLY loop' "$STUB_DIR/out" | cut -d: -f1)" ] && ok "rollback printed before deletes" || ng "rollback order"
first_del=$(grep 'text=LSvrDel lssn' "$STUB_DIR/calls.log" | head -1)
for want in "https://giipfaw.azurewebsites.net/api/giipApi?code=" "--data-urlencode text=LSvrDel lssn" "--data-urlencode token=$TEST_SK" "--data-urlencode usertoken=$TEST_SK" '--data-urlencode jsondata={"lssn":71296}'; do
	case "$first_del" in *"$want"*) ok "request has: ${want//$TEST_SK/<sk>}" ;; *) ng "request lacks: ${want//$TEST_SK/<sk>}" ;; esac
done
grep -qx -e 71295 -e 71300 -e 71305 -e 417 "$STUB_DIR/deleted" && ng "non-target deleted" || ok "71295/71300/71305/417 untouched"
grep -q 'VERIFY: deleted-but-still-listed=0 remaining_targets=0 new_targets_since_start=0' "$STUB_DIR/out" && ok "verify after re-fetch" || ng "verify: $(grep VERIFY "$STUB_DIR/out")"
grep -q '"deleted":18,"failed":0,"still_listed":0,"remaining":0' "$STUB_DIR/kvs.log" && grep -q '"kFactor":"cleanup_nameless_lssn"' "$STUB_DIR/kvs.log" \
	&& ok "KVS summary stored" || ng "kvs: $(cat "$STUB_DIR/kvs.log")"

reset_state B2; GIIP_CLEANUP_NO_JQ=1 run --action apply
[ "$(rc)" = 0 ] && [ "$(dels)" = "$EXPECTED_TARGETS" ] && grep -q 'parser=awk' "$STUB_DIR/out" && ok "apply with awk parser (no jq): rc=0, $EXPECTED_TARGETS deletes" || ng "awk apply rc=$(rc) dels=$(dels)"

echo "=== (C) idempotent re-run ==="
: > "$STUB_DIR/calls.log"; run --action apply
[ "$(rc)" = 0 ] && [ "$(dels)" = 0 ] && grep -q 'APPLY: nothing to delete' "$STUB_DIR/out" && ok "second apply: nothing to do, 0 deletes" || ng "rerun rc=$(rc) dels=$(dels)"

echo "=== (D) first 3 fail -> abort ==="
reset_state D; STUB_DEL_MODE=fail run --action apply
[ "$(rc)" = 4 ] && [ "$(dels)" = 3 ] && grep -q 'stop=first3' "$STUB_DIR/out" && ok "rc=4 after 3 calls" || ng "rc=$(rc) dels=$(dels)"
grep -q 'RstVal=404 count=3: 71296 71297 71298' "$STUB_DIR/out" && ok "failures listed with RstVal" || ng "failure list: $(grep RstVal= "$STUB_DIR/out")"

echo "=== (E) 10 consecutive failures -> abort ==="
reset_state E; STUB_DEL_MODE=fail_from:71302 run --action apply
# 71296-71299,71301 ok (5), then 71302-71304,71306-71312 fail (10)
[ "$(rc)" = 4 ] && [ "$(dels)" = 15 ] && grep -q 'stop=consecutive10' "$STUB_DIR/out" && ok "rc=4 after 5 ok + 10 failures" || ng "rc=$(rc) dels=$(dels)"

echo "=== (F) time budget ==="
reset_state F; GIIP_CLEANUP_SLEEP=1 run --action apply --budget 2
n=$(dels)
[ "$(rc)" = 3 ] && [ "$n" -ge 1 ] && [ "$n" -lt "$EXPECTED_TARGETS" ] && grep -q 'RE-RUN APPLY' "$STUB_DIR/out" && ok "rc=3 after $n deletes, says re-run apply" || ng "rc=$(rc) dels=$n"
grep -q "remaining_targets=$((EXPECTED_TARGETS - n)) " "$STUB_DIR/out" && ok "remaining counted from re-fetch" || ng "remaining: $(grep VERIFY "$STUB_DIR/out")"
: > "$STUB_DIR/calls.log"; run --action apply
[ "$(rc)" = 0 ] && [ "$(dels)" = "$((EXPECTED_TARGETS - n))" ] && ok "re-run handles only the rest ($((EXPECTED_TARGETS - n)))" || ng "rerun rc=$(rc) dels=$(dels)"

echo "=== (G) fail-closed ==="
for raw in '{"data":[{"RstVal":401,"Proc_MSG":"Invalid session"}]}' '{"debug":{},"data":[]}' '{"data":[{"lssn":71296},{"lssn":71297}]}' 'Error executing api' ''; do
	reset_state G; STUB_LIST_RAW="$raw" run --action apply
	[ "$(rc)" = 2 ] && [ "$(dels)" = 0 ] && ok "rc=2, no delete for: ${raw:-<empty>}" || ng "rc=$(rc) dels=$(dels) for: $raw"
done
reset_state G2; run --action apply --max-targets 5
[ "$(rc)" = 2 ] && [ "$(dels)" = 0 ] && ok "rc=2 when targets > --max-targets" || ng "max-targets rc=$(rc)"

echo "=== (H) placeholder / bad args ==="
reset_state H; run '{{CustomVariables}}'
[ "$(rc)" = 0 ] && [ "$(dels)" = 0 ] && grep -q 'action=dryrun' "$STUB_DIR/out" && ok "unreplaced placeholder -> dryrun" || ng "placeholder rc=$(rc)"
run --action delete
[ "$(rc)" = 1 ] && ok "invalid --action -> rc=1" || ng "invalid action rc=$(rc)"

reset_state H2; STUB_DETAIL=none run
grep -q 'row NOT visible to this token' "$STUB_DIR/out" && [ "$(rc)" = 0 ] && ok "preflight reports a token that cannot see the row" || ng "preflight none: $(grep preflight "$STUB_DIR/out")"

echo "=== (I) secrets never printed ==="
if grep -rq "$TEST_SK" "$WORK"/state*/out; then ng "SK found in output"; else ok "SK absent from all outputs"; fi
if grep -rq "groupsecret" "$WORK"/state*/out; then ng "SKey from LsvrDetail leaked"; else ok "LsvrDetail SKey never printed"; fi

echo "=== (J) CQE launcher body ==="
sed -n '/---- launcher begin ----/,/---- launcher end ----/p' "$TARGET" | sed '1d;$d' | sed 's/^# \{0,1\}//' > "$WORK/launcher.tpl"
grep -q 'bash "$S" {{CustomVariables}}' "$WORK/launcher.tpl" && ok "launcher template extracted" || ng "launcher template: $(cat "$WORK/launcher.tpl")"
# the CQE agent (cqe/giipCQE.sh validate_script) blocks bodies containing these fixed strings
bad=0; for p in "rm -rf /" "dd if=/dev/zero" "mkfs" "format" "> /dev/sda"; do grep -qF "$p" "$WORK/launcher.tpl" && bad=1; done
[ $bad = 0 ] && ok "launcher passes giipCQE.sh dangerous-pattern check" || ng "launcher contains a blocked pattern"
sed 's/{{CustomVariables}}/--action dryrun --min-lssn 71296/' "$WORK/launcher.tpl" > "$WORK/launcher.sh"
mkdir -p "$WORK/empty"; (cd "$WORK/empty" && sh "$WORK/launcher.sh" > out 2>&1); r=$?
[ $r = 1 ] && grep -q FATAL "$WORK/empty/out" && ok "missing script -> exit 1" || ng "missing script rc=$r"
mkdir -p "$WORK/agent/giipAgentLinux/scripts" && cp "$TARGET" "$WORK/agent/giipAgentLinux/scripts/" && ln -s "${SCRIPT_DIR}/../lib" "$WORK/agent/giipAgentLinux/lib"
cp "$WORK/giipAgent.cnf" "$WORK/agent/giipAgent.cnf"
reset_state J; (cd "$WORK/agent/giipAgentLinux" && sh "$WORK/launcher.sh" > "$STUB_DIR/out" 2>&1); r=$?
[ $r = 0 ] && grep -q "targets=$EXPECTED_TARGETS" "$STUB_DIR/out" && [ "$(dels)" = 0 ] && ok "launcher (sh, cwd=agent dir, default cnf) -> dryrun rc=0" || ng "launcher rc=$r: $(head -5 "$STUB_DIR/out")"
sed 's/{{CustomVariables}}/--action apply/' "$WORK/launcher.tpl" > "$WORK/launcher2.sh"
reset_state J2; (cd "$WORK/agent/giipAgentLinux" && STUB_DEL_MODE=fail sh "$WORK/launcher2.sh" > "$STUB_DIR/out" 2>&1); r=$?
[ $r = 4 ] && ok "launcher propagates exit code (4)" || ng "launcher rc=$r"
# exported sk/apiaddrv2 without a cnf (normal_mode.sh exports them before running a CQE body)
rm -f "$WORK/agent/giipAgent.cnf"
reset_state J3; (cd "$WORK/agent/giipAgentLinux" && sk="$TEST_SK" apiaddrv2="https://example.invalid/api/giipApiSk2" lssn=71295 sh "$WORK/launcher.sh" > "$STUB_DIR/out" 2>&1); r=$?
[ $r = 0 ] && grep -q "targets=$EXPECTED_TARGETS" "$STUB_DIR/out" && ok "no cnf -> exported sk/apiaddrv2 used" || ng "env fallback rc=$r: $(head -3 "$STUB_DIR/out")"

echo "=== (K) scattered failures -> rc 5 ==="
reset_state K; STUB_DEL_MODE=fail_list:71298,71310 run --action apply
[ "$(rc)" = 5 ] && [ "$(dels)" = "$EXPECTED_TARGETS" ] && grep -q 'remaining_targets=2 ' "$STUB_DIR/out" && ok "rc=5, 2 remaining" || ng "rc=$(rc) $(grep VERIFY "$STUB_DIR/out")"

echo ""
echo "Result: PASS=$PASS FAIL=$FAIL"
[ $FAIL -eq 0 ]
