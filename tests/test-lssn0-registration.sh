#!/bin/bash
# Test: lssn=0 self-registration (offline, no network)
# 목적: giipAgent3.sh 의 lssn=0 자동등록이 무한 재등록(tLSvr 행 증식)을 일으키지 않는지 검증.
#   (1) persist_lssn 이 lssn="0" / lssn=0 / lssn='0' / CRLF 줄을 모두 71234 로 갱신
#   (2) cnf inode 불변 (sed -i/rename 이 아닌 in-place 덮어쓰기 → Docker 단일파일 bind mount 대응)
#   (3) cnf 쓰기 불가 → 사이드카 giipAgent.lssn 기록, load_config 가 71234 를 사용
#   (4) queue_get 은 lssn=0 이면 curl 을 호출하지 않고 반환
#   (5) 잘못된 응답(RstVal 500 / RstVal 400 + lssn null)이면 cnf 불변
#   (+) register_server 가 201 JSON 응답(curl stub)으로 cnf 를 갱신하고 lssn 을 export
#
# 읽기전용 시뮬레이션: root 로 실행하면 chmod 444 로는 쓰기가 막히지 않는다. 그래서
#   (a) write_file_inplace() 를 실패하도록 stub 하는 방식을 항상 수행하고,
#   (b) chattr +i 가 가능한 환경이면 실제 immutable 파일로도 한 번 더 검증한다(불가하면 SKIP).
#
# Usage: bash tests/test-lssn0-registration.sh

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="${SCRIPT_DIR}/../lib"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/giip_lssn0_test.XXXXXX")
trap 'chattr -i "$WORK"/*/giipAgent.cnf 2>/dev/null; rm -rf "$WORK"' EXIT

# curl stub: 호출 기록을 남기고 $STUB_RESPONSE 를 -o 대상에 쓴다
mkdir -p "$WORK/bin"
cat > "$WORK/bin/curl" <<'STUB'
#!/bin/bash
echo "$*" >> "$CURL_CALL_LOG"
out=""
while [ $# -gt 0 ]; do
	if [ "$1" = "-o" ]; then out="$2"; shift; fi
	shift
done
if [ -n "$out" ]; then printf '%s' "$STUB_RESPONSE" > "$out"; else printf '%s' "$STUB_RESPONSE"; fi
exit 0
STUB
chmod +x "$WORK/bin/curl"
export PATH="$WORK/bin:$PATH"
export CURL_CALL_LOG="$WORK/curl_calls.log"
: > "$CURL_CALL_LOG"

. "${LIB_DIR}/common.sh"
. "${LIB_DIR}/lssn_register.sh"
. "${LIB_DIR}/cqe.sh"
LogFileName="$WORK/agent.log"

PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
ng()   { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

make_cnf() {
	# $1=dir $2=lssn line (without newline) $3=eol ("" or $'\r')
	mkdir -p "$1"
	printf 'sk="testsk"%s\n%s%s\napiaddrv2="https://example.invalid/api"%s\ngiipagentdelay="60"%s\n' \
		"$3" "$2" "$3" "$3" "$3" > "$1/giipAgent.cnf"
}

RESP_201='{"data":[{"RstVal":"201","lssn":71234,"ProcName":"[pLSvrInfoInputSimplebySK]"}],"debug":{}}'

echo "=== (1)(2) persist_lssn: quoting/CRLF variants, inode preserved ==="
i=0
for variant in 'lssn="0"' 'lssn=0' "lssn='0'" '  lssn = "0"'; do
	for eol in "" $'\r'; do
		i=$((i+1)); d="$WORK/c$i"
		make_cnf "$d" "$variant" "$eol"
		ino_before=$(stat -c %i "$d/giipAgent.cnf")
		persist_lssn "$d/giipAgent.cnf" 71234; rc=$?
		ino_after=$(stat -c %i "$d/giipAgent.cnf")
		label="[$variant]$([ -n "$eol" ] && echo ' CRLF')"
		got=$(read_lssn_from_file "$d/giipAgent.cnf")
		if [ $rc -eq 0 ] && [ "$got" = "71234" ] && [ "$(grep -c 'lssn=' "$d/giipAgent.cnf")" = "1" ]; then
			ok "$label -> lssn=$got"
		else
			ng "$label rc=$rc got='$got'"; cat -A "$d/giipAgent.cnf"
		fi
		if [ "$ino_before" = "$ino_after" ]; then ok "$label inode unchanged ($ino_after)"; else ng "$label inode changed $ino_before -> $ino_after"; fi
		# 다른 설정 보존 + CRLF 보존
		if grep -q '^sk="testsk"' "$d/giipAgent.cnf" && { [ -z "$eol" ] || grep -q $'^lssn="71234"\r$' "$d/giipAgent.cnf"; }; then
			ok "$label other lines/line endings preserved"
		else
			ng "$label other lines/line endings not preserved"
		fi
	done
done

echo "=== (3a) read-only cnf (write_file_inplace stubbed to fail) -> sidecar ==="
d="$WORK/ro"; make_cnf "$d" 'lssn="0"' ""
cp "$d/giipAgent.cnf" "$WORK/ro.orig"
eval "orig_$(declare -f write_file_inplace)"
write_file_inplace() { return 1; }
persist_lssn "$d/giipAgent.cnf" 71234 2>/dev/null; rc=$?
eval "$(declare -f orig_write_file_inplace | sed '1s/orig_write_file_inplace/write_file_inplace/')"
[ $rc -eq 2 ] && ok "persist_lssn returned 2 (sidecar)" || ng "persist_lssn rc=$rc (expected 2)"
cmp -s "$d/giipAgent.cnf" "$WORK/ro.orig" && ok "cnf unchanged" || ng "cnf changed"
[ "$(cat "$d/giipAgent.lssn" 2>/dev/null)" = "71234" ] && ok "sidecar giipAgent.lssn = 71234" || ng "sidecar missing/wrong"
( unset lssn; load_config "$d/giipAgent.cnf" 2>/dev/null; echo "$lssn" ) > "$WORK/ro.lssn"
[ "$(cat "$WORK/ro.lssn")" = "71234" ] && ok "load_config uses sidecar -> lssn=71234" || ng "load_config lssn='$(cat "$WORK/ro.lssn")'"
# cnf 에 실제 lssn 이 있으면 사이드카보다 cnf 우선
d2="$WORK/ro2"; make_cnf "$d2" 'lssn="555"' ""; echo 71234 > "$d2/giipAgent.lssn"
( load_config "$d2/giipAgent.cnf" 2>/dev/null; echo "$lssn" ) > "$WORK/ro2.lssn"
[ "$(cat "$WORK/ro2.lssn")" = "555" ] && ok "cnf lssn (555) wins over sidecar" || ng "cnf/sidecar precedence wrong: $(cat "$WORK/ro2.lssn")"

echo "=== (3b) read-only cnf via chattr +i (real immutable file) ==="
d="$WORK/imm"; make_cnf "$d" 'lssn="0"' ""
if command -v chattr >/dev/null 2>&1 && chattr +i "$d/giipAgent.cnf" 2>/dev/null; then
	persist_lssn "$d/giipAgent.cnf" 71234 2>/dev/null; rc=$?
	chattr -i "$d/giipAgent.cnf"
	[ $rc -eq 2 ] && [ "$(read_lssn_from_file "$d/giipAgent.cnf")" = "0" ] && [ "$(cat "$d/giipAgent.lssn")" = "71234" ] \
		&& ok "immutable cnf -> rc=2, cnf untouched, sidecar=71234" || ng "immutable cnf rc=$rc"
else
	echo "  SKIP: chattr +i not supported on this filesystem/user (covered by 3a stub)"
fi

echo "=== (4) queue_get with lssn=0 does not call curl ==="
sk="testsk"; apiaddrv2="https://example.invalid/api"; export sk apiaddrv2
: > "$CURL_CALL_LOG"
queue_get 0 "host1" "Linux" "$WORK/q.out" 2>/dev/null; rc=$?
[ $rc -ne 0 ] && [ ! -s "$CURL_CALL_LOG" ] && ok "queue_get lssn=0 -> rc=$rc, curl not called" || ng "queue_get lssn=0 rc=$rc, curl calls: $(wc -l < "$CURL_CALL_LOG")"
queue_get "" "host1" "Linux" "$WORK/q.out" 2>/dev/null; rc=$?
[ $rc -ne 0 ] && [ ! -s "$CURL_CALL_LOG" ] && ok "queue_get lssn='' -> rc=$rc, curl not called" || ng "queue_get lssn='' called curl"

echo "=== (5) invalid responses leave cnf unchanged ==="
for resp in '{"data":[{"RstVal":"500"}]}' '{"data":[{"RstVal":"400","lssn":null}]}' 'Invalid token' ''; do
	d="$WORK/bad$RANDOM"; make_cnf "$d" 'lssn="0"' ""
	cp "$d/giipAgent.cnf" "$d.orig"
	export STUB_RESPONSE="$resp"
	lssn=0
	register_server "$d/giipAgent.cnf" "host1" "Linux" 2>/dev/null; rc=$?
	if [ $rc -ne 0 ] && cmp -s "$d/giipAgent.cnf" "$d.orig" && [ ! -e "$d/giipAgent.lssn" ] && [ "$lssn" = "0" ]; then
		ok "response '${resp:-<empty>}' -> rc=$rc, cnf unchanged, no sidecar"
	else
		ng "response '${resp}' rc=$rc lssn=$lssn"
	fi
done
# jq 없는 폴백 파서도 동일하게 판정하는지
d="$WORK/nojq"; mkdir -p "$d"
printf '%s' "$RESP_201" > "$d/r1"; printf '%s' '{"data":[{"RstVal":"400","lssn":null}]}' > "$d/r2"
nojq_path="$WORK/nojqbin"; mkdir -p "$nojq_path"
for t in tr grep head sed cat; do ln -sf "$(command -v $t)" "$nojq_path/$t"; done
v1=$(PATH="$nojq_path" parse_register_response "$d/r1"); PATH="$nojq_path" parse_register_response "$d/r2" >/dev/null; r2=$?
[ "$v1" = "71234" ] && [ $r2 -ne 0 ] && ok "fallback parser (no jq): 201->71234, 400/null rejected" || ng "fallback parser v1='$v1' r2=$r2"

echo "=== (+) register_server end-to-end with stubbed 201 response ==="
d="$WORK/e2e"; make_cnf "$d" 'lssn="0"' ""
export STUB_RESPONSE="$RESP_201"; : > "$CURL_CALL_LOG"
lssn=0
register_server "$d/giipAgent.cnf" "host1" "Ubuntu%2022.04" 2>/dev/null; rc=$?
[ $rc -eq 0 ] && [ "$lssn" = "71234" ] && [ "$(read_lssn_from_file "$d/giipAgent.cnf")" = "71234" ] \
	&& ok "registered: lssn=$lssn, cnf updated" || ng "register_server rc=$rc lssn=$lssn"
bash -c 'echo "$lssn"' | grep -qx 71234 && ok "lssn exported to child processes" || ng "lssn not exported"
grep -q -- '--data-urlencode text=CQEQueueGet lssn hostname os op' "$CURL_CALL_LOG" && ok "curl sent 'text=CQEQueueGet lssn hostname os op'" || ng "text param wrong: $(cat "$CURL_CALL_LOG")"
grep -q '"hostname":"host1"' "$CURL_CALL_LOG" && grep -q '"lssn":0' "$CURL_CALL_LOG" && ok "jsondata carries lssn=0/hostname" || ng "jsondata wrong"
# DB 수정 후의 200(기존 hostname 재사용) 응답도 수용
d="$WORK/e2e200"; make_cnf "$d" 'lssn=0' ""
export STUB_RESPONSE='{"data":[{"RstVal":"200","lssn":"71234","ProcName":"x"}]}'
lssn=0; register_server "$d/giipAgent.cnf" "host1" "Linux" 2>/dev/null; rc=$?
[ $rc -eq 0 ] && [ "$(read_lssn_from_file "$d/giipAgent.cnf")" = "71234" ] && ok "RstVal 200 (existing) accepted" || ng "RstVal 200 rc=$rc"

echo ""
echo "Result: PASS=$PASS FAIL=$FAIL"
[ $FAIL -eq 0 ]
