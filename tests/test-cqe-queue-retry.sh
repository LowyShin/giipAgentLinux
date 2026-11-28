#!/bin/bash
# giip #4167 (C1~C4) — queue_get() 응답 처리·재시도·오류 분류 검증 (단위 테스트)
#
# 실제 product 코드(lib/cqe.sh)의 queue_get 를 그대로 source 하고
# curl / log_error / log_message / kvs_put / sleep 를 모의(mock)해 각 응답 분기를 구동한다.
# 검증 항목:
#   (C1) 빈 파일·공백 응답을 JSON 파싱 전에 정상 대기(rc=0, 에러 로그 없음) 처리
#   (C2) ms_body 가 빈 문자열(또는 키 없음)인 유효 JSON → 정상 스킵 (JsonParsingError 금지)
#   (C3) 전송 실패·타임아웃·HTTP 5xx 시 최초 1회 + 최대 2회 백오프 재시도(2s → 4s)
#   (C4) 오류 분류 — 전송 실패/타임아웃/5xx = NetworkError, 빈 응답·빈 스크립트 = 정상 스킵,
#                   진짜 malformed JSON 만 JsonParsingError
#
# sleep 은 기다리지 않고 호출된 인자만 기록한다(백오프 값 검증용).
# 시나리오는 "실패 구간"과 "성공 구간" 두 단계로 지정한다 — 실패 구간이 끝난 뒤 성공 구간으로 전환.

set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CQE_LIB="${SCRIPT_DIR}/../lib/cqe.sh"

if [ ! -f "$CQE_LIB" ]; then
	echo "❌ Error: cqe.sh not found — expected: $CQE_LIB"
	exit 1
fi

# --- 모의 시나리오 변수 ---
FAIL_TIMES=0          # 앞에서부터 연속 실패할 시도 횟수
FAIL_EXIT=0           # 실패 구간 curl 종료코드
FAIL_HTTP="000"       # 실패 구간 HTTP 상태 코드
FAIL_WRITE=""         # 실패 구간 응답 본문(비면 0바이트 응답 파일만 만든다)
OK_HTTP="200"         # 성공 구간 HTTP 상태 코드
OK_WRITE=""           # 성공 구간 응답 본문

# --- 모의 실행 기록 ---
CURL_CALLS=0          # 실제 curl 호출 횟수
SLEEP_CALLS=""        # sleep 호출 인자 기록
CAPTURED_ERR=""       # log_error 로 잡힌 "타입|메시지" 누적
OUT_CONTENT=""        # queue_get 이 남긴 출력 파일 내용

# --- 모의 함수 ---
curl() {
	# queue_get 가 -o <temp_response> 로 쓰므로 그 경로를 찾아 시나리오 내용을 쓴다
	local out="" prev=""
	for a in "$@"; do
		[ "$prev" = "-o" ] && out="$a"
		prev="$a"
	done
	CURL_CALLS=$((CURL_CALLS + 1))
	local body="" code="" rc=0
	if [ "$CURL_CALLS" -le "$FAIL_TIMES" ]; then
		body="$FAIL_WRITE"; code="$FAIL_HTTP"; rc="$FAIL_EXIT"
	else
		body="$OK_WRITE"; code="$OK_HTTP"; rc=0
	fi
	if [ -n "$out" ]; then
		# 빈 본문이어도 0바이트 응답 파일은 존재하는 것으로 둔다(HTTP 200 + 빈 body 상황)
		printf '%s' "$body" > "$out"
	fi
	# 실제 curl 과 동일하게 -w "%{http_code}" 결과를 stdout 으로 내보낸다
	printf '%s' "$code"
	return "$rc"
}
sleep() { SLEEP_CALLS="${SLEEP_CALLS}${1} "; }
log_error()   { CAPTURED_ERR="${CAPTURED_ERR}${2}|${1}"$'\n'; }
log_message() { :; }
kvs_put()     { :; }
export -f curl sleep log_error log_message kvs_put 2>/dev/null || true

# 전역 요구 변수
sk="dummy-sk"
apiaddrv2="http://dummy.local/api"

# shellcheck disable=SC1090
source "$CQE_LIB"

PASS=0; FAIL=0
# run <이름> <기대 rc> <기대 에러타입(""=에러없음)> <기대 curl 호출수> <기대 sleep 인자열> <기대 출력파일("-"=무관)>
run() {
	local name="$1" exp_rc="$2" exp_err="$3" exp_calls="$4" exp_sleep="$5" exp_out="$6"
	CAPTURED_ERR=""; CURL_CALLS=0; SLEEP_CALLS=""; OUT_CONTENT=""
	local of; of="$(mktemp)"
	queue_get "71286" "test-host" "Ubuntu 22.04" "$of" >/dev/null 2>&1
	local rc=$?
	local errtype=""
	[ -n "$CAPTURED_ERR" ] && errtype="$(printf '%s' "$CAPTURED_ERR" | head -1 | cut -d'|' -f1)"
	OUT_CONTENT="$(cat "$of" 2>/dev/null)"
	local ok=1
	[ "$rc" = "$exp_rc" ] || ok=0
	[ "$errtype" = "$exp_err" ] || ok=0
	[ "$CURL_CALLS" = "$exp_calls" ] || ok=0
	[ "${SLEEP_CALLS% }" = "$exp_sleep" ] || ok=0
	if [ "$exp_out" != "-" ]; then
		[ "$OUT_CONTENT" = "$exp_out" ] || ok=0
	fi
	if [ "$ok" = 1 ]; then
		PASS=$((PASS+1)); printf 'PASS  %-42s rc=%s err=[%s] calls=%s sleep=[%s] out=[%s]\n' "$name" "$rc" "${errtype:-none}" "$CURL_CALLS" "${SLEEP_CALLS% }" "$OUT_CONTENT"
	else
		FAIL=$((FAIL+1)); printf 'FAIL  %-42s rc=%s(exp %s) err=[%s](exp [%s]) calls=%s(exp %s) sleep=[%s](exp [%s]) out=[%s](exp [%s])\n' \
			"$name" "$rc" "$exp_rc" "${errtype:-none}" "${exp_err:-none}" "$CURL_CALLS" "$exp_calls" "${SLEEP_CALLS% }" "$exp_sleep" "$OUT_CONTENT" "$exp_out"
	fi
	rm -f "$of" "$of.type" "$of.mslsn" "$of.mssn" 2>/dev/null
}

# 정상 응답 본문(큐 스크립트)
SCRIPT_JSON='{"RstVal":"200","data":[{"ms_body":"echo hi","script_type":"sh"}]}'
# 실행할 스크립트가 비어 있는 정상 응답 (pApiCQEQueueGetbySK 가 ms_body='' 를 줄 수 있다)
EMPTY_MS_BODY_JSON='{"RstVal":"200","data":[{"ms_body":"","script_type":"sh"}]}'
# ms_body 키 자체가 없는 정상 응답
NO_MS_BODY_JSON='{"RstVal":"200","data":[]}'

echo "=== giip #4167 queue_get 응답처리·재시도 검증 ($(date '+%Y-%m-%d %H:%M:%S')) ==="
echo "대상: $CQE_LIB"
echo

# --- C1: 빈/공백 응답은 JSON 파싱 전에 정상 대기 처리 ---
FAIL_TIMES=0; OK_HTTP="200"; OK_WRITE=""
run "C1 빈 본문(전송성공 0바이트)" 0 "" 1 "" ""
FAIL_TIMES=0; OK_HTTP="200"; OK_WRITE=$'   \n\t  \n'
run "C1 공백만 응답" 0 "" 1 "" ""

# --- C2: 유효 JSON 이지만 실행할 스크립트 없음 → 정상 스킵 ---
FAIL_TIMES=0; OK_HTTP="200"; OK_WRITE="$EMPTY_MS_BODY_JSON"
run "C2 ms_body 빈 문자열" 0 "" 1 "" ""
FAIL_TIMES=0; OK_HTTP="200"; OK_WRITE="$NO_MS_BODY_JSON"
run "C2 유효JSON ms_body 없음" 0 "" 1 "" ""

# --- C3: 네트워크 일시 오류 시 백오프 재시도 ---
FAIL_TIMES=99; FAIL_EXIT=7; FAIL_HTTP="000"; FAIL_WRITE=""; OK_HTTP="200"; OK_WRITE="$SCRIPT_JSON"
run "C3 전송실패 지속(exit7)" 1 "NetworkError" 3 "2 4" "-"
FAIL_TIMES=99; FAIL_EXIT=28; FAIL_HTTP="000"; FAIL_WRITE=""; OK_HTTP="200"; OK_WRITE="$SCRIPT_JSON"
run "C3 타임아웃 지속(exit28)" 1 "NetworkError" 3 "2 4" "-"
FAIL_TIMES=1; FAIL_EXIT=7; FAIL_HTTP="000"; FAIL_WRITE=""; OK_HTTP="200"; OK_WRITE="$SCRIPT_JSON"
run "C3 1회 실패 후 성공" 0 "" 2 "2" "echo hi"
FAIL_TIMES=2; FAIL_EXIT=7; FAIL_HTTP="000"; FAIL_WRITE=""; OK_HTTP="200"; OK_WRITE="$SCRIPT_JSON"
run "C3 2회 실패 후 성공" 0 "" 3 "2 4" "echo hi"
FAIL_TIMES=99; FAIL_EXIT=0; FAIL_HTTP="503"; FAIL_WRITE='The service is unavailable.'; OK_HTTP="200"; OK_WRITE="$SCRIPT_JSON"
run "C3 5xx(503) 지속" 1 "NetworkError" 3 "2 4" "-"
FAIL_TIMES=1; FAIL_EXIT=0; FAIL_HTTP="503"; FAIL_WRITE='The service is unavailable.'; OK_HTTP="200"; OK_WRITE="$SCRIPT_JSON"
run "C3 503 1회 후 정상" 0 "" 2 "2" "echo hi"

# --- C4: 오류 분류 경계 ---
FAIL_TIMES=0; OK_HTTP="200"; OK_WRITE='{"RstVal":"0"}'
run "C4 RstVal=0 큐없음(정상)" 0 "" 1 "" ""
FAIL_TIMES=0; OK_HTTP="200"; OK_WRITE='{"RstVal":"404","ProcName":"no queue"}'
run "C4 RstVal=404 큐없음(정상)" 0 "" 1 "" ""
FAIL_TIMES=0; OK_HTTP="200"; OK_WRITE='{"RstVal":"500","ProcName":"boom"}'
run "C4 RstVal=500 API오류" 1 "ApiError" 1 "" "-"
FAIL_TIMES=0; OK_HTTP="200"; OK_WRITE="$SCRIPT_JSON"
run "C4 정상 ms_body 스크립트" 0 "" 1 "" "echo hi"
FAIL_TIMES=0; OK_HTTP="200"; OK_WRITE='garbage not json at all'
run "C4 무효JSON(진짜 파싱실패)" 1 "JsonParsingError" 1 "" "-"
FAIL_TIMES=99; FAIL_EXIT=7; FAIL_HTTP="000"; FAIL_WRITE='partial body'; OK_HTTP="200"; OK_WRITE="$SCRIPT_JSON"
run "C3 부분본문+전송실패" 1 "NetworkError" 3 "2 4" "-"

echo
echo "=== 요약: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" = 0 ] && exit 0 || exit 1
