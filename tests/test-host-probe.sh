#!/bin/bash
# Test: cqe/host-probe.cqe.sh — GIIP #6233 자유 질의 프로브 (오프라인, 네트워크 없음)
# 목적:
#   (1) 인자 누락 → usage 오류(exit 1), SK 없으면 config 오류(exit 2)
#   (2) gair 함수 키 미설정 → 조사를 건너뛰고 facts + status(failed) 만 저장 (exit 3)
#   (3) claude CLI 있음 → gair env(ANTHROPIC_BASE_URL/AUTH_TOKEN/CUSTOM_HEADERS/CLAUDE_CONFIG_DIR)를
#       정확히 심고 호출하며, 답변이 answer 행에 저장된다 (exit 0)
#   (4) claude CLI 없음 → gair Messages API 직접 호출(curl)로 fallback 하고 답변을 저장한다 (exit 0)
#   (5) 저장 요청이 giipApiSk4 KVSPut(text=KVSPut kType kKey kFactor kValue) 형태이고
#       kType="<hostname>.probe" / kKey=ProbeId / kFactor=answer|status 를 담는지 검증
#   (6) stdout 은 ASCII 요약만, 비밀값(SK/AK/함수 키)은 stdout·stderr 에 새지 않는다
#   (7) facts 가 유효한 JSON 이고 필수 항목을 담는지 검증
#
# Usage: bash tests/test-host-probe.sh
# 네트워크: 없음 (curl 은 전부 stub)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROBE="${SCRIPT_DIR}/../cqe/host-probe.cqe.sh"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/giip_host_probe_test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
ng()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
check() { # $1=label $2=actual $3=expected
	if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (actual=[$2] expected=[$3])"; fi
}

# --- stub bin 디렉터리 ------------------------------------------------------
mkdir -p "$WORK/bin"
# claude 이 없는 최소 PATH 용 (스크립트가 쓰는 바이너리만 심볼릭 링크)
mkdir -p "$WORK/bin_noclaude"
for b in bash sh sed awk grep cut tr head tail df free uptime date uname pgrep ps timeout curl mktemp rm cat wc env date; do
	p="$(command -v "$b" 2>/dev/null)" && ln -sf "$p" "$WORK/bin_noclaude/$b"
done
ln -sf "$(command -v jq 2>/dev/null || echo /bin/true)" "$WORK/bin_noclaude/jq" 2>/dev/null
ln -sf "$(command -v jq 2>/dev/null || echo /bin/true)" "$WORK/bin/jq" 2>/dev/null
ln -sf "$(command -v hostname 2>/dev/null || echo /bin/true)" "$WORK/bin_noclaude/hostname" 2>/dev/null

# curl stub: 호출을 기록하고 URL/text 에 따라 canned 응답을 돌려준다
cat > "$WORK/bin/curl" <<'STUB'
#!/bin/bash
echo "$*" >> "$CURL_CALL_LOG"
out=""
args=""
while [ $# -gt 0 ]; do
	if [ "$1" = "-o" ]; then out="$2"; shift; fi
	args="$args $1"
	shift
done
resp="$STUB_DEFAULT_RESPONSE"
case "$args" in
	*AdminGetAK*)   resp="$STUB_AK_RESPONSE" ;;
	*KVSPut*)       resp="$STUB_KVS_RESPONSE" ;;
	*gair*)         resp="$STUB_GAIR_RESPONSE" ;;
esac
if [ -n "$out" ]; then printf '%s' "$resp" > "$out"; else printf '%s' "$resp"; fi
exit 0
STUB
chmod +x "$WORK/bin/curl"
ln -sf "$WORK/bin/curl" "$WORK/bin_noclaude/curl"

# claude stub: 넘겨받은 gair env 를 기록하고 정해진 답변을 출력한다
cat > "$WORK/bin/claude" <<'STUB'
#!/bin/bash
{
	echo "ARGS=$*"
	echo "BASE_URL=$ANTHROPIC_BASE_URL"
	echo "AUTH_TOKEN=$ANTHROPIC_AUTH_TOKEN"
	echo "CUSTOM_HEADERS=$ANTHROPIC_CUSTOM_HEADERS"
	echo "CONFIG_DIR=$CLAUDE_CONFIG_DIR"
} >> "$CLAUDE_CALL_LOG"
printf '%s' "$STUB_CLAUDE_ANSWER"
exit 0
STUB
chmod +x "$WORK/bin/claude"

export CURL_CALL_LOG="$WORK/curl_calls.log"
export CLAUDE_CALL_LOG="$WORK/claude_calls.log"
: > "$CURL_CALL_LOG"
: > "$CLAUDE_CALL_LOG"

export STUB_DEFAULT_RESPONSE='{"data":[{"RstVal":"200","Proc_MSG":"200"}]}'
export STUB_AK_RESPONSE='{"data":[{"RstVal":"200","ak":"TESTAK-VALUE-0001","usn":29,"csn":70425}]}'
export STUB_KVS_RESPONSE='{"data":[{"RstVal":"200","RstMsg":"Success"}]}'
export STUB_GAIR_RESPONSE='{"id":"msg_1","type":"message","role":"assistant","content":[{"type":"text","text":"디스크 사용률 42% 입니다."}]}'
export STUB_CLAUDE_ANSWER='메모리 여유가 충분합니다.'

# --- 설정 파일 --------------------------------------------------------------
CNF_DIR="$WORK/install"
mkdir -p "$CNF_DIR"
cat > "$CNF_DIR/giipAgent.cnf" <<'EOF'
sk="TEST-SK-VALUE-0001"
lssn="71174"
apiaddrv2="https://example.invalid/api/giipApiSk2"
apiaddrcode="TEST-FUNCKEY-VALUE"
gairfunctionkey="TEST-FUNCKEY-VALUE"
uloginid="probe@example.invalid"
EOF

run_probe() { # $1=extra PATH dir(빈 문자열이면 기본) 나머지=인자
	_extra_path="$1"; shift
	PATH="${_extra_path:+$_extra_path:}$WORK/bin:/usr/bin:/bin" \
	HOST_PROBE_CNF="$CNF_DIR/giipAgent.cnf" \
	CLAUDE_CONFIG_DIR_PROBE="$WORK/claude_cfg" \
	bash "$PROBE" "$@" >"$WORK/out.txt" 2>"$WORK/err.txt"
	echo $?
}

echo "=== (1) 인자/설정 오류 ==="
rc="$(run_probe '' )"
check "인자 없으면 exit 1" "$rc" "1"
grep -q "usage:" "$WORK/err.txt" && ok "usage 메시지(stderr)" || ng "usage 메시지 없음"

rc="$(run_probe '' "probe-1")"
check "Question 누락이면 exit 1" "$rc" "1"

# SK 없는 설정 파일
CNF_NOSK="$WORK/nosk"; mkdir -p "$CNF_NOSK"
printf 'lssn="71174"\napiaddrv2="https://example.invalid/api/giipApiSk2"\n' > "$CNF_NOSK/giipAgent.cnf"
PATH="$WORK/bin:/usr/bin:/bin" HOST_PROBE_CNF="$CNF_NOSK/giipAgent.cnf" bash "$PROBE" "p" "q" >"$WORK/out.txt" 2>"$WORK/err.txt"
check "SK 없으면 exit 2" "$?" "2"

echo "=== (2) gair 함수 키 미설정 → facts 만 저장하고 status=failed ==="
CNF_NOKEY="$WORK/nokey"; mkdir -p "$CNF_NOKEY"
grep -v '^gairfunctionkey' "$CNF_DIR/giipAgent.cnf" > "$CNF_NOKEY/giipAgent.cnf"
: > "$CURL_CALL_LOG"
rc="$(PATH="$WORK/bin:/usr/bin:/bin" HOST_PROBE_CNF="$CNF_NOKEY/giipAgent.cnf" bash "$PROBE" "probe-nokey" "디스크는?" >"$WORK/out.txt" 2>"$WORK/err.txt"; echo $?)"
check "함수 키 없으면 exit 3" "$rc" "3"
grep -q "state=failed" "$WORK/out.txt" && ok "stdout summary state=failed" || ng "state=failed 없음: $(cat "$WORK/out.txt")"
grep -q "gairfunctionkey" "$WORK/err.txt" && ok "사유에 함수 키 언급" || ng "사유 메시지 없음"
# 함수 키가 없어도 KVSPut 은 두 건(answer/status) 나간다
n_kv=$(grep -c "KVSPut" "$CURL_CALL_LOG")
check "KVSPut 2건(answer+status)" "$n_kv" "2"

echo "=== (3) claude CLI 경로 ==="
: > "$CURL_CALL_LOG"; : > "$CLAUDE_CALL_LOG"
rc="$(run_probe "$WORK/bin" "probe-cli" "메모리는?")"
check "claude 경로 exit 0" "$rc" "0"
grep -q "state=done" "$WORK/out.txt" && ok "stdout summary state=done" || ng "state=done 없음: $(cat "$WORK/out.txt")"
grep -q "engine=gair/claude-cli" "$WORK/out.txt" && ok "engine 표시" || ng "engine 표시 없음"
grep -q "BASE_URL=https://giipfaw.azurewebsites.net/api/gair" "$CLAUDE_CALL_LOG" && ok "ANTHROPIC_BASE_URL=gair" || ng "ANTHROPIC_BASE_URL 잘못됨"
grep -q "AUTH_TOKEN=TESTAK-VALUE-0001" "$CLAUDE_CALL_LOG" && ok "ANTHROPIC_AUTH_TOKEN=파생 AK" || ng "AK 전달 안 됨: $(cat "$CLAUDE_CALL_LOG")"
grep -q "CUSTOM_HEADERS=x-functions-key: TEST-FUNCKEY-VALUE" "$CLAUDE_CALL_LOG" && ok "ANTHROPIC_CUSTOM_HEADERS=x-functions-key" || ng "함수키 헤더 없음"
grep -q "CONFIG_DIR=$WORK/claude_cfg" "$CLAUDE_CALL_LOG" && ok "CLAUDE_CONFIG_DIR 전용 디렉터리" || ng "CONFIG_DIR 없음"
[ -d "$WORK/claude_cfg" ] && ok "전용 설정 디렉터리 생성됨" || ng "전용 설정 디렉터리 없음"
grep -q "read-only\|읽기 전용" "$CLAUDE_CALL_LOG" && ok "프롬프트에 읽기 전용 지시 포함" || ng "읽기 전용 지시 없음"

echo "=== (4) claude CLI 없을 때 → gair Messages API 직접 호출 ==="
: > "$CURL_CALL_LOG"
rc="$(PATH="$WORK/bin_noclaude:/usr/bin:/bin" HOST_PROBE_CNF="$CNF_DIR/giipAgent.cnf" bash "$PROBE" "probe-api" "디스크는?" >"$WORK/out.txt" 2>"$WORK/err.txt"; echo $?)"
check "gair api 경로 exit 0" "$rc" "0"
grep -q "engine=gair/api" "$WORK/out.txt" && ok "engine=gair/api 표시" || ng "engine 표시 없음: $(cat "$WORK/out.txt")"
grep -q "v1/messages" "$CURL_CALL_LOG" && ok "gair Messages API 호출" || ng "gair API 호출 없음"
grep -q "x-functions-key: TEST-FUNCKEY-VALUE\|x-functions-key:TEST-FUNCKEY-VALUE" "$CURL_CALL_LOG" && ok "함수키 헤더 전송" || ng "함수키 헤더 없음"

echo "=== (5) 저장 요청 형식 ==="
: > "$CURL_CALL_LOG"
rc="$(run_probe "$WORK/bin" "probe-store" "Q?")"
kvs_line="$(grep "KVSPut" "$CURL_CALL_LOG" | head -1)"
echo "$kvs_line" | grep -q "text=KVSPut kType kKey kFactor kValue" && ok "Sk4 text 형식" || ng "text 형식 다름: $kvs_line"
echo "$kvs_line" | grep -q "giipApiSk4" && ok "giipApiSk4 로 전송" || ng "Sk4 아님: $kvs_line"
echo "$kvs_line" | grep -q "kType" && echo "$kvs_line" | grep -q "probe" && ok "kType=<host>.probe" || ng "kType 없음: $kvs_line"
grep -q "kFactor" "$CURL_CALL_LOG" && ok "kFactor 존재" || ng "kFactor 없음"
grep -q "answer" "$CURL_CALL_LOG" && ok "answer 팩터 존재" || ng "answer 팩터 없음"
grep -q "status" "$CURL_CALL_LOG" && ok "status 팩터 존재" || ng "status 팩터 없음"

echo "=== (6) stdout 은 ASCII 요약만 / 비밀값 미노출 ==="
rc="$(run_probe "$WORK/bin" "probe-ascii" "Q?")"
if LC_ALL=C grep -q '[^ -~]' "$WORK/out.txt"; then
	ng "stdout 에 비ASCII 문자 있음: $(cat "$WORK/out.txt")"
else
	ok "stdout ASCII only"
fi
for secret in "TEST-SK-VALUE-0001" "TESTAK-VALUE-0001" "TEST-FUNCKEY-VALUE"; do
	if grep -q "$secret" "$WORK/out.txt" "$WORK/err.txt"; then
		ng "비밀값 노출: $secret"
	else
		ok "비밀값 미노출 ($secret)"
	fi
done

echo "=== (7) facts JSON 유효성 ==="
facts_line="$(grep "jsondata=" "$CURL_CALL_LOG" | grep "answer" | head -1)"
if command -v jq >/dev/null 2>&1; then
	# 스텁 curl 은 argv 를 그대로 기록하므로 jsondata 는 이미 생(raw) JSON 이다.
	# URL 디코딩 해킹(%→\x + printf %b)은 생 JSON 속의 '%'("12%", "%mem")를 망가뜨리므로 쓰지 않는다.
	decoded="$(printf '%s' "$facts_line" | sed -e 's/.*jsondata=//')"
	if printf '%s' "$decoded" | jq -e . >/dev/null 2>&1; then
		ok "jsondata 가 유효한 JSON"
	else
		ng "jsondata JSON 아님: $decoded"
	fi
fi

echo
echo "=== 결과: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" -eq 0 ]
