#!/bin/bash
################################################################################
# cleanup_nameless_lssn.sh - soft-delete the nameless tLSvr rows created by the
#                            old lssn=0 self-registration loop (giip 2948)
#
# Issue : https://giip.littleworld.net/ko/admin/giip-issues/2948
# Cause : giip 2928 - an agent with lssn=0 in giipAgent.cnf called CQEQueueGet with
#         lssn=0 every run; pApiCQEQueueGetbySK registered a new tLSvr row each time
#         and the new lssn was never persisted. Fixed in giipAgentLinux PR #35/#36
#         (lib/cqe.sh / cqe/giipCQE.sh lssn=0 guards, lib/lssn_register.sh).
#         The rows left behind have hostname/os/last_heartbeat all NULL.
#
# What it does
#   1. Lists the servers visible to this agent's SK:
#        POST ${apiaddrv2}  text=LSvrListForIssue  token=<sk>
#        (giipApiSk2 -> pApiLSvrListForIssuebySK; csn is taken from the SK)
#      The response can contain INVALID JSON escapes (e.g. an os value with a raw
#      backslash + newline: "Debian GNU/Linux 8 \<LF> \\l"), so the body is
#      sanitised before jq; without jq an awk extractor is used. Both paths only
#      accept a row as a target when all four keys are present with explicit values.
#   2. Target rule: lssn >= --min-lssn AND hostname null/empty AND os null/empty
#      AND last_heartbeat null. Rows in range that miss the rule are listed as skips.
#   3. Read-only auth hint: POST giipApi text=LsvrDetail lssn for the lowest target with the
#      same token (pApiLsvrDetailbyAk -> lwGetUSNbyat), reports whether the row is visible.
#      dryrun (default): prints counts and ranges. NO write call of any kind.
#      apply: prints the rollback SQL, then per lssn
#        POST ${GIIP_API_URL}?code=<function code>
#             text=LSvrDel lssn  token=<sk>  usertoken=<sk>  jsondata={"lssn":N}
#        (giipApi -> pApiLSvrDelbyAK @ak=<token>, @lssn=N). The SP resolves the
#        caller with dbo.lwGetUSNbyat(@ak), which also accepts an SK (tCorpUser.
#        uSecretKey, or tSecretKey -> the csn's isPay user), requires that usn to be
#        in tCorpUserRel for a csn linked to the lssn, then sets tLSvr.lsDeldt =
#        getdate() and hard-deletes tIP/tLSvrNIC/tLSvrDiskStat/tLSvrPort rows of that
#        lssn. Returns RstVal 200 (done) or 404 (not linked / not found).
#      After the loop the list is fetched again and deleted/failed/still-present
#      are reported. Idempotent: a re-run only handles what is still listed.
#
# Usage
#   bash scripts/cleanup_nameless_lssn.sh [--action dryrun|apply] [--min-lssn N]
#        [--budget SEC] [--max-targets N] [--config FILE] [--kvs|--no-kvs]
#
#   --action       dryrun (default) | apply
#   --min-lssn     lowest lssn that may be touched (default 71296; 71295 LOWYDN01
#                  is the last normal server)
#   --budget       apply time budget in seconds (default 220). CQE runs the body
#                  under `timeout 300` (cqe/giipCQE.sh SCRIPT_TIMEOUT=300) and
#                  scripts/normal_mode.sh kill -9's a normal_mode.sh older than 300s,
#                  so budget + one curl (15s) + re-fetch (60s max) stays below that.
#   --max-targets  fail closed (exit 2) if more targets than this (default 3000)
#   --config       giipAgent.cnf path (default: <agent dir>/../giipAgent.cnf).
#                  If sk/apiaddrv2 are already exported (normal_mode.sh does that
#                  before running a CQE body) and no cnf is found, those are used.
#   --kvs/--no-kvs store the summary in tKVS (kType=lssn, kKey=<agent lssn>,
#                  kFactor=cleanup_nameless_lssn). Default: on for apply, off for
#                  dryrun (dryrun makes no write call at all).
#   Arguments that look like an unreplaced CQE placeholder ({{...}}) are ignored.
#
# Environment overrides (no secrets are stored in this file)
#   GIIP_API_URL     AK-style API (default https://giipfaw.azurewebsites.net/api/giipApi)
#   GIIP_AZURE_CODE  Function key for giipApi. Default is the public key that giipv3
#                    ships in its browser bundle (src/config/api.ts AZURE_FUNCTION_API.code),
#                    same default as lowyworkenv/scripts/gissue/get-ak.sh. Not an SK/AK.
#   GIIP_CLEANUP_NO_JQ=1   force the awk parser (tests)
#   GIIP_CLEANUP_SLEEP     pause between deletes (default 0.15)
#
# Exit codes
#   0  dryrun finished / apply finished: nothing failed, nothing deleted is still listed and
#      no target is left (rows created during the run count as left -> 5)
#   1  usage or configuration error (script not run)
#   2  FAIL-CLOSED: list fetch failed, 0 servers parsed, unrecognised schema, too many targets
#   3  PARTIAL: time budget reached -> re-run apply
#   4  ABORTED: first 3 deletes all failed, or 10 consecutive failures
#   5  apply finished but some deletes failed or deleted rows are still listed -> re-run apply
#
# CQE msBody launcher (script_type=sh). The agent runs the body with `sh` (lib/normal.sh
# execute_script) or `timeout 300 bash` (cqe/giipCQE.sh); in both the working directory is
# the giipAgentLinux dir (cron: `cd ${giippath}; bash giipAgent3.sh`, admin/giipcronreg.sh).
# custom_values examples: `--action dryrun`  |  `--action apply --min-lssn 71296`
# ---- launcher begin ----
# # CQE launcher (giip 2948) - canonical: giipAgentLinux/scripts/cleanup_nameless_lssn.sh
# # Do not put logic here. custom_values -> args, e.g. --action apply --min-lssn 71296
# S="./scripts/cleanup_nameless_lssn.sh"
# if [ ! -f "$S" ]; then
#   echo "FATAL: $S not found (cwd=$(pwd)); refusing to run"
#   exit 1
# fi
# bash "$S" {{CustomVariables}}
# exit $?
# ---- launcher end ----
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="${AGENT_DIR}/lib"

ACTION="dryrun"
MIN_LSSN=71296
BUDGET=220
MAX_TARGETS=3000
CONFIG_FILE=""
KVS_REPORT=""
GIIP_API_URL="${GIIP_API_URL:-https://giipfaw.azurewebsites.net/api/giipApi}"
GIIP_AZURE_CODE="${GIIP_AZURE_CODE:-A-NKqA90-xgw_fu0V6CneCnFrJrv6qvusWtDel7MJegTAzFu0E6mYw==}"
SLEEP_SEC="${GIIP_CLEANUP_SLEEP:-0.15}"
KFACTOR="cleanup_nameless_lssn"

say() { echo "[cleanup-lssn] $*"; }
die_usage() { say "ERROR: $*"; exit 1; }

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
	case "$1" in
		*"{{"*"}}"*) shift; continue ;;   # unreplaced CQE placeholder
		--action) ACTION="${2:-}"; shift 2 ;;
		--action=*) ACTION="${1#*=}"; shift ;;
		--min-lssn) MIN_LSSN="${2:-}"; shift 2 ;;
		--min-lssn=*) MIN_LSSN="${1#*=}"; shift ;;
		--budget) BUDGET="${2:-}"; shift 2 ;;
		--budget=*) BUDGET="${1#*=}"; shift ;;
		--max-targets) MAX_TARGETS="${2:-}"; shift 2 ;;
		--max-targets=*) MAX_TARGETS="${1#*=}"; shift ;;
		--config) CONFIG_FILE="${2:-}"; shift 2 ;;
		--config=*) CONFIG_FILE="${1#*=}"; shift ;;
		--kvs) KVS_REPORT=1; shift ;;
		--no-kvs) KVS_REPORT=0; shift ;;
		-h|--help) sed -n '2,/^####*$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) die_usage "unknown argument: $1" ;;
	esac
done

case "$ACTION" in dryrun|apply) ;; *) die_usage "--action must be dryrun or apply (got '$ACTION')" ;; esac
for v in MIN_LSSN BUDGET MAX_TARGETS; do
	eval "val=\${$v}"
	[[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -gt 0 ] || die_usage "$v must be a positive integer (got '$val')"
done
if [ -z "$KVS_REPORT" ]; then
	if [ "$ACTION" = "apply" ]; then KVS_REPORT=1; else KVS_REPORT=0; fi
fi

# ---------------------------------------------------------------------------
# Configuration (sk, apiaddrv2, lssn) via lib/common.sh load_config
# ---------------------------------------------------------------------------
[ -z "$CONFIG_FILE" ] && CONFIG_FILE="${AGENT_DIR}/../giipAgent.cnf"
if [ -f "$CONFIG_FILE" ]; then
	if [ ! -f "${LIB_DIR}/common.sh" ]; then die_usage "lib/common.sh not found in ${LIB_DIR}"; fi
	# shellcheck source=../lib/common.sh
	. "${LIB_DIR}/common.sh"
	load_config "$CONFIG_FILE" >/dev/null || die_usage "load_config failed for $CONFIG_FILE (needs sk, lssn, apiaddrv2)"
elif [ -n "${sk:-}" ] && [ -n "${apiaddrv2:-}" ]; then
	say "config file not found ($CONFIG_FILE); using exported sk/apiaddrv2 from the agent"
else
	die_usage "config file not found: $CONFIG_FILE and sk/apiaddrv2 not in environment"
fi
[ -n "${sk:-}" ] || die_usage "sk is empty"
[ -n "${apiaddrv2:-}" ] || die_usage "apiaddrv2 is empty"
command -v curl >/dev/null 2>&1 || die_usage "curl not found"

USE_JQ=0
if [ "${GIIP_CLEANUP_NO_JQ:-0}" != "1" ] && command -v jq >/dev/null 2>&1; then USE_JQ=1; fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/giip_cleanup_lssn.XXXXXX") || die_usage "mktemp failed"
trap 'rm -rf "$WORK"' EXIT
RESULT_FILE="${TMPDIR:-/tmp}/giip_cleanup_nameless_lssn_$(date +%Y%m%d%H%M%S).tsv"
START_EPOCH=$(date +%s)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# "71296\n71297\n71299" (sorted numeric) -> "71296-71297,71299"
compact_ranges() {
	awk 'NF{ n=$1+0
		if (s=="") { s=n; p=n; next }
		if (n==p+1) { p=n; next }
		out = out (out==""?"":",") (s==p ? s : s "-" p); s=n; p=n }
		END{ if (s!="") out = out (out==""?"":",") (s==p ? s : s "-" p); print out }'
}

# same input -> SQL predicate "LSsn BETWEEN a AND b OR LSsn IN (x,y)"
sql_ranges() {
	awk 'NF{ n=$1+0
		if (s=="") { s=n; p=n; next }
		if (n==p+1) { p=n; next }
		emit(); s=n; p=n }
		function emit() { if (s==p) singles = singles (singles==""?"":",") s
			else ranges = ranges (ranges==""?"":" OR ") "LSsn BETWEEN " s " AND " p }
		END{ if (s!="") emit()
			if (singles!="") ranges = ranges (ranges==""?"":" OR ") "LSsn IN (" singles ")"
			print ranges }'
}

# Print at most $2 chars of $1 (CQE keeps only the first 10KB of stdout)
clip() { local s="$1" max="$2"; if [ "${#s}" -gt "$max" ]; then echo "${s:0:$max}...(+$(( ${#s} - max )) chars, see result file)"; else echo "$s"; fi; }

# Fetch the server list into $1. Never prints the body (it echoes the SK in "debug").
fetch_list() {
	local out="$1" code
	code=$(curl -sS -X POST "$apiaddrv2" \
		-H 'Content-Type: application/x-www-form-urlencoded' \
		--data-urlencode 'text=LSvrListForIssue' \
		--data-urlencode "token=${sk}" \
		--connect-timeout 10 --max-time 60 \
		-o "$out" -w '%{http_code}' 2>"$WORK/curl.err")
	local rc=$?
	if [ $rc -ne 0 ] || [ ! -s "$out" ]; then
		say "list fetch failed: curl exit=$rc http=${code:-?} $(head -c 200 "$WORK/curl.err" 2>/dev/null)"
		return 1
	fi
	return 0
}

# Parse a list response ($1) into "lssn<TAB>hostname<TAB>os<TAB>last_heartbeat" where each
# field is one of: null | empty | set | missing. Returns 2 when the schema is not recognised.
parse_list() {
	local in="$1" flat="$WORK/flat.json"
	# Flatten (drops CR/LF - a raw newline can only occur inside a broken string value),
	# turn tabs into spaces, and double every backslash that does not start a valid JSON
	# escape so jq accepts the body (e.g. "8 \ \\l" -> "8 \\ \\l").
	tr -d '\r\n' < "$in" | tr '\t' ' ' | tr -d '\000-\010\013\014\016-\037' \
		| sed -e 's/\\\\/\n/g' -e 's/\\\([^"\/bfnrtu]\)/\\\\\1/g' -e 's/\n/\\\\/g' > "$flat"

	grep -q '"data"[[:space:]]*:[[:space:]]*\[' "$flat" || return 2

	if [ "$USE_JQ" = "1" ]; then
		if jq -r '
			def st($k): if has($k) | not then "missing"
				elif .[$k] == null then "null"
				elif (.[$k] | type) == "string" and (.[$k] | gsub("\\s"; "")) == "" then "empty"
				else "set" end;
			.data | if type == "array" then . else error("data is not an array") end
			| .[] | select(type == "object" and (.lssn | type) == "number")
			| [(.lssn | tostring), st("hostname"), st("os"), st("last_heartbeat")] | @tsv
		' "$flat" 2>"$WORK/jq.err"; then
			return 0
		fi
		say "WARN: jq could not parse the sanitised list ($(head -c 120 "$WORK/jq.err")); using awk parser" >&2
	fi

	# awk parser: one record per "{". A record is only usable when it carries all four keys;
	# a string that happens to contain "{" splits a row into parts that miss keys -> never a target.
	awk 'BEGIN{ RS="{" }
		function st(k,   re) {
			if (match($0, "\"" k "\"[ ]*:[ ]*null")) return "null"
			if (match($0, "\"" k "\"[ ]*:[ ]*\"[ ]*\"")) return "empty"
			if (match($0, "\"" k "\"[ ]*:")) return "set"
			return "missing"
		}
		{
			if (!match($0, /"lssn"[ ]*:[ ]*[0-9]+/)) next
			v = substr($0, RSTART, RLENGTH); sub(/.*:[ ]*/, "", v)
			printf "%s\t%s\t%s\t%s\n", v, st("hostname"), st("os"), st("last_heartbeat")
		}' "$flat"
	return 0
}

# $1 = parsed tsv. Writes $WORK/targets (sorted lssn) and $WORK/skips ("lssn reason").
classify() {
	: > "$WORK/targets"; : > "$WORK/skips"
	awk -F'\t' -v min="$MIN_LSSN" -v T="$WORK/targets" -v S="$WORK/skips" '
		($1+0) < min { next }
		{
			r = ""
			if ($2 == "missing" || $3 == "missing" || $4 == "missing") r = "missing-keys"
			else {
				if ($2 == "set") r = r (r==""?"":"+") "hostname"
				if ($3 == "set") r = r (r==""?"":"+") "os"
				if ($4 != "null") r = r (r==""?"":"+") "heartbeat"
			}
			if (r == "") print $1 > T; else print $1 " " r > S
		}' "$1"
	sort -n -u -o "$WORK/targets" "$WORK/targets"
	sort -n -o "$WORK/skips" "$WORK/skips"
}

# Load + parse + classify. Prints the summary lines with prefix $1.
load_and_classify() {
	local tag="$1" raw="$WORK/list_${tag}.json" parsed="$WORK/parsed_${tag}.tsv" prc
	fetch_list "$raw" || return 2
	parse_list "$raw" > "$parsed"; prc=$?
	if [ $prc -ne 0 ]; then
		say "FAIL-CLOSED: unrecognised list schema (no \"data\" array). RstVal=$(grep -oE '"RstVal"[[:space:]]*:[[:space:]]*"?[0-9]+' "$raw" | grep -oE '[0-9]+$' | head -1)"
		return 2
	fi
	local total full
	total=$(grep -c . "$parsed")
	full=$(awk -F'\t' '$2!="missing" && $3!="missing" && $4!="missing"' "$parsed" | grep -c .)
	if [ "$total" -eq 0 ]; then
		say "FAIL-CLOSED: 0 servers parsed from the list (RstVal=$(grep -oE '"RstVal"[[:space:]]*:[[:space:]]*"?[0-9]+' "$raw" | grep -oE '[0-9]+$' | head -1))"
		return 2
	fi
	if [ "$full" -eq 0 ]; then
		say "FAIL-CLOSED: $total rows parsed but none has hostname/os/last_heartbeat keys (schema changed?)"
		return 2
	fi
	classify "$parsed"
	cp "$parsed" "$WORK/parsed_last.tsv"
	TOTAL=$total
	NT=$(grep -c . "$WORK/targets")
	NS=$(grep -c . "$WORK/skips")
	TMIN=$(head -1 "$WORK/targets"); TMAX=$(tail -1 "$WORK/targets")
	say "[$tag] parser=$([ "$USE_JQ" = 1 ] && echo jq || echo awk) total=$TOTAL rows_with_all_keys=$full targets=$NT skips_in_range=$NS min_target=${TMIN:--} max_target=${TMAX:--}"
	if [ "$NT" -gt 0 ]; then
		say "[$tag] target ranges: $(clip "$(compact_ranges < "$WORK/targets")" 600)"
	fi
	if [ "$NS" -gt 0 ]; then
		say "[$tag] skips (lssn reason):"
		head -20 "$WORK/skips" | sed 's/^/    /'
		[ "$NS" -gt 20 ] && say "    ...(+$((NS - 20)) more)"
	fi
	return 0
}

# Read-only auth hint: can this token see lssn $1 through the AK API? pApiLsvrDetailbyAk ->
# pLSvrDescOptbyAT uses the same dbo.lwGetUSNbyat(@ak) as pApiLSvrDelbyAK but checks
# tCorpUserRel against tLSvr.CSn (the delete SP checks the csn linked in tCorpLSvrRel), so
# this is a hint, not a guarantee. The body carries the server group's SKey: never print it.
auth_preflight() {
	local l="$1" body seen csn
	body=$(curl -sS -X POST "${GIIP_API_URL}?code=${GIIP_AZURE_CODE}" \
		-H 'Content-Type: application/x-www-form-urlencoded' \
		--data-urlencode 'text=LsvrDetail lssn' \
		--data-urlencode "token=${sk}" \
		--data-urlencode "jsondata={\"lssn\":${l}}" \
		--connect-timeout 10 --max-time 20 2>/dev/null)
	seen=$(printf '%s' "$body" | grep -oE '"LSsn"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+$' | head -1)
	csn=$(printf '%s' "$body" | grep -oE '"CSn"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+$' | head -1)
	if [ "$seen" = "$l" ]; then
		say "auth preflight (read-only LsvrDetail $l): token resolves to a user of the row's csn (tLSvr.CSn=${csn:-?}) - OK"
	else
		say "auth preflight (read-only LsvrDetail $l): row NOT visible to this token - LSvrDel will probably return 404 (the first-3 guard will stop apply)"
	fi
}

kvs_report() {
	# $1 = JSON object (numbers/short strings only)
	[ "$KVS_REPORT" = "1" ] || return 0
	local jsondata resp rst
	jsondata="{\"kType\":\"lssn\",\"kKey\":\"${lssn:-0}\",\"kFactor\":\"${KFACTOR}\",\"kValue\":$1}"
	resp=$(curl -sS -X POST "$apiaddrv2" \
		-H 'Content-Type: application/x-www-form-urlencoded' \
		--data-urlencode 'text=KVSPut kType kKey kFactor' \
		--data-urlencode "token=${sk}" \
		--data-urlencode "jsondata=${jsondata}" \
		--connect-timeout 10 --max-time 20 2>/dev/null)
	rst=$(printf '%s' "$resp" | grep -oE '"RstVal"[[:space:]]*:[[:space:]]*"?[0-9]+' | grep -oE '[0-9]+$' | head -1)
	say "kvs report (kType=lssn kKey=${lssn:-0} kFactor=${KFACTOR}): RstVal=${rst:-none}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
say "giip 2948 nameless lssn cleanup: action=$ACTION min_lssn=$MIN_LSSN agent_lssn=${lssn:-?} host=$(hostname 2>/dev/null)"
say "rule: lssn>=$MIN_LSSN AND hostname null/empty AND os null/empty AND last_heartbeat null"

load_and_classify "before" || exit 2

if [ "$NT" -gt "$MAX_TARGETS" ]; then
	say "FAIL-CLOSED: $NT targets > --max-targets $MAX_TARGETS; refusing"
	exit 2
fi

[ "$NT" -gt 0 ] && auth_preflight "$TMIN"

if [ "$ACTION" = "dryrun" ]; then
	kvs_report "{\"action\":\"dryrun\",\"min_lssn\":$MIN_LSSN,\"total\":$TOTAL,\"targets\":$NT,\"skips\":$NS,\"min_target\":${TMIN:-0},\"max_target\":${TMAX:-0}}"
	say "DRYRUN done: no write call was made. Re-run with --action apply to delete $NT rows."
	exit 0
fi

# ----------------------------- apply -----------------------------
if [ "$NT" -eq 0 ]; then
	say "APPLY: nothing to delete."
	kvs_report "{\"action\":\"apply\",\"min_lssn\":$MIN_LSSN,\"total\":$TOTAL,\"targets\":0,\"deleted\":0,\"failed\":0,\"remaining\":0,\"result\":\"done\"}"
	exit 0
fi

say "ROLLBACK SQL (run on giipdb to undo the soft delete; tIP/tLSvrNIC/tLSvrDiskStat/tLSvrPort rows removed by the SP are not restorable):"
echo "UPDATE tLSvr SET lsDeldt = NULL WHERE lsDeldt IS NOT NULL AND ($(sql_ranges < "$WORK/targets"));"

cp "$WORK/targets" "$WORK/todo"
: > "$WORK/ok"; : > "$WORK/fail"
printf 'lssn\tRstVal\n' > "$RESULT_FILE"
attempted=0; consecutive_fail=0; stop_reason=""

while read -r target; do
	[ -n "$target" ] || continue
	if [ $(( $(date +%s) - START_EPOCH )) -ge "$BUDGET" ]; then
		stop_reason="budget"
		break
	fi
	resp=$(curl -sS -X POST "${GIIP_API_URL}?code=${GIIP_AZURE_CODE}" \
		-H 'Content-Type: application/x-www-form-urlencoded' \
		--data-urlencode 'text=LSvrDel lssn' \
		--data-urlencode "token=${sk}" \
		--data-urlencode "usertoken=${sk}" \
		--data-urlencode "jsondata={\"lssn\":${target}}" \
		--connect-timeout 10 --max-time 15 2>/dev/null)
	crc=$?
	rst=$(printf '%s' "$resp" | grep -oE '"RstVal"[[:space:]]*:[[:space:]]*"?[0-9]+' | grep -oE '[0-9]+$' | head -1)
	[ -z "$rst" ] && rst="curl${crc}"
	attempted=$((attempted + 1))
	printf '%s\t%s\n' "$target" "$rst" >> "$RESULT_FILE"
	if [ "$rst" = "200" ]; then
		echo "$target" >> "$WORK/ok"
		consecutive_fail=0
	else
		echo "$target $rst" >> "$WORK/fail"
		consecutive_fail=$((consecutive_fail + 1))
		if [ "$attempted" -eq 3 ] && [ "$consecutive_fail" -eq 3 ]; then
			stop_reason="first3"
			break
		fi
		if [ "$consecutive_fail" -ge 10 ]; then
			stop_reason="consecutive10"
			break
		fi
	fi
	sleep "$SLEEP_SEC" 2>/dev/null || sleep 1
done < "$WORK/todo"

NOK=$(grep -c . "$WORK/ok")
NFAIL=$(grep -c . "$WORK/fail")
NNOT=$((NT - attempted))
ELAPSED=$(( $(date +%s) - START_EPOCH ))
say "APPLY loop: attempted=$attempted deleted(RstVal 200)=$NOK failed=$NFAIL not_attempted=$NNOT elapsed=${ELAPSED}s stop=${stop_reason:-completed}"
if [ "$NOK" -gt 0 ]; then say "deleted ranges: $(clip "$(compact_ranges < "$WORK/ok")" 600)"; fi
if [ "$NFAIL" -gt 0 ]; then
	say "failed (by RstVal):"
	awk '{ l[$2] = l[$2] (l[$2]==""?"":" ") $1; c[$2]++ } END{ for (k in c) print "    RstVal=" k " count=" c[k] ": " l[k] }' "$WORK/fail" | cut -c1-600
fi

# ---- verification: fetch the list again ----
cp "$WORK/ok" "$WORK/ok_sorted"; sort -n -o "$WORK/ok_sorted" "$WORK/ok_sorted"
cp "$WORK/targets" "$WORK/targets_before"
if load_and_classify "after"; then
	cut -f1 "$WORK/parsed_last.tsv" | sort -n -u > "$WORK/listed_after"
	STILL=$(comm -12 "$WORK/ok_sorted" "$WORK/listed_after" | grep -c .)
	NEW=$(comm -13 "$WORK/targets_before" "$WORK/targets" | grep -c .)
	REMAIN=$NT
	say "VERIFY: deleted-but-still-listed=$STILL remaining_targets=$REMAIN new_targets_since_start=$NEW"
	if [ "$STILL" -gt 0 ]; then
		say "still listed after RstVal 200: $(clip "$(comm -12 "$WORK/ok_sorted" "$WORK/listed_after" | compact_ranges)" 400)"
	fi
	if [ "$NEW" -gt 0 ]; then
		say "WARNING: $NEW new nameless rows appeared during this run - the lssn=0 loop is still active on some agent: $(clip "$(comm -13 "$WORK/targets_before" "$WORK/targets" | compact_ranges)" 300)"
	fi
else
	STILL=-1; REMAIN=-1; NEW=-1
	say "VERIFY: re-fetch failed; deleted/remaining could not be confirmed"
fi
say "per-lssn results: $RESULT_FILE"

case "$stop_reason" in
	budget) result="partial"; rc=3 ;;
	first3|consecutive10) result="aborted_${stop_reason}"; rc=4 ;;
	*) if [ "$NFAIL" -eq 0 ] && [ "$STILL" -eq 0 ] && [ "$REMAIN" -eq 0 ]; then result="done"; rc=0; else result="incomplete"; rc=5; fi ;;
esac

kvs_report "{\"action\":\"apply\",\"min_lssn\":$MIN_LSSN,\"targets\":$(wc -l < "$WORK/targets_before"),\"attempted\":$attempted,\"deleted\":$NOK,\"failed\":$NFAIL,\"still_listed\":$STILL,\"remaining\":$REMAIN,\"new_since_start\":$NEW,\"elapsed_sec\":$ELAPSED,\"result\":\"$result\"}"

case "$rc" in
	0) say "RESULT: DONE - all targets deleted and verified." ;;
	3) say "RESULT: PARTIAL - time budget (${BUDGET}s) reached. RE-RUN APPLY to continue ($REMAIN still listed)." ;;
	4) say "RESULT: ABORTED ($stop_reason) - deletes are failing; check auth (SK -> lwGetUSNbyat) before re-running." ;;
	5) say "RESULT: INCOMPLETE - failed=$NFAIL still_listed=$STILL remaining=$REMAIN. RE-RUN APPLY to retry." ;;
esac
exit $rc
