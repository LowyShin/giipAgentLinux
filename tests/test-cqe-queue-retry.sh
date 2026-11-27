#!/bin/bash
# giip #4167 (C3) — queue_get() 네트워크 일시 오류 백오프 재시도 검증 (단위 테스트)
#
# 실제 product 코드(lib/cqe.sh)의 queue_get 를 그대로 source 하고 curl/log_error/kvs_put 를
# 모의(mock)해 응답 분기를 구동한다. 검증 대상:
#   - 전송 실패(curl 종료코드 != 0) 시 최대 2회 백오프 재시도(총 3회 시도)
#   - 서버 일시 장애(HTTP 5xx, giipfaw 503 "The service is unavailable.") 시 동일 재시도
#   - 백오프 간격이 2s → 4s 로 지수 증가하는지
#   - 재시도 도중 성공하면 정상 처리(rc=0, 에러 로그 없음)
#   - 정상 응답(빈 본문/공백/정상 스크립트)은 재시도 대상이 아니며 시도 1회로 끝나는지
#   - 5xx 응답이 "JSON 파싱 실패"가 아니라 서비스 오류(NetworkError)로 분류되는지
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
FAIL_WRITE=""         # 실패 구간 응답 본문(비면 응답 파일을 만들지 않음)
OK_HTTP="200"         # 성공 구간 HTTP 상태 코드
OK_WRITE=""           # 성공 구간 응답 본문

# --- 모의 실행 기록 ---
CURL_CALLS=0          # 실제 curl 호출 횟수
SLEEP_CALLS=""        # sleep 호출 인자 기록
CAPTURED_ERR=""       # log_error 로 잡힌 "타입|메시지" 누적

# --- 모의 함수 ---
curl() {
  # queue_get 가 -o <temp_response> 로 쓰므로 그 경로를 찾아 시나리오 내용을 쓴다
  local out="" prev=""
  for a in "$@"; do
    [ "$prev" = "-o" ] && out="$a"
    prev="$a"
  done
  CURL_CALLS=$((CURL_CALLS + 1))
  local body="" code=""
  if [ "$CURL_CALLS" -le "$FAIL_TIMES" ]; then
    body="$FAIL_WRITE"; code="$FAIL_HTTP"
    if [ -n "$out" ] && [ -n "$body" ]; then printf '%s' "$body" > "$out"; fi
    printf '%s' "$code"
    return "$FAIL_EXIT"
  fi
  body="$OK_WRITE"; code="$OK_HTTP"
  if [ -n "$out" ]; then
    if [ -n "$body" ]; then printf '%s' "$body" > "$out"; else : > "$out"; rm -f "$out"; fi
  fi
  # 실제 curl 과 동일하게 -w "%{http_code}" 결과를 stdout 으로 내보낸다
  printf '%s' "$code"
  return 0
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
# run <이름> <기대 rc> <기대 에러타입(""=에러없음)> <기대 curl 호출수> <기대 sleep 인자열>
run() {
  local name="$1" exp_rc="$2" exp_err="$3" exp_calls="$4" exp_sleep="$5"
  CAPTURED_ERR=""; CURL_CALLS=0; SLEEP_CALLS=""
  local of; of="$(mktemp)"
  queue_get "71286" "test-host" "Ubuntu 22.04" "$of" >/dev/null 2>&1
  local rc=$?
  local errtype=""
  [ -n "$CAPTURED_ERR" ] && errtype="$(printf '%s' "$CAPTURED_ERR" | head -1 | cut -d'|' -f1)"
  local ok=1
  [ "$rc" = "$exp_rc" ] || ok=0
  [ "$errtype" = "$exp_err" ] || ok=0
  [ "$CURL_CALLS" = "$exp_calls" ] || ok=0
  [ "${SLEEP_CALLS% }" = "$exp_sleep" ] || ok=0
  if [ "$ok" = 1 ]; then
    PASS=$((PASS+1)); printf 'PASS  %-46s rc=%s err=[%s] calls=%s sleep=[%s]\n' "$name" "$rc" "${errtype:-none}" "$CURL_CALLS" "${SLEEP_CALLS% }"
  else
    FAIL=$((FAIL+1)); printf 'FAIL  %-46s rc=%s(exp %s) err=[%s](exp [%s]) calls=%s(exp %s) sleep=[%s](exp [%s])\n' \
      "$name" "$rc" "$exp_rc" "${errtype:-none}" "${exp_err:-none}" "$CURL_CALLS" "$exp_calls" "${SLEEP_CALLS% }" "$exp_sleep"
  fi
  rm -f "$of" "$of.type" "$of.mslsn" "$of.mssn" 2>/dev/null
}

# 정상 응답 본문(큐 스크립트)
SCRIPT_JSON='{"RstVal":"200","data":[{"ms_body":"echo hi","script_type":"sh"}]}'

echo "=== giip4167 queue_get 백오프 재시도 검증 ($(date '+%Y-%m-%d %H:%M:%S')) ==="
echo "대상: $CQE_LIB"
echo

# C3: 전송 실패(연결 거부)가 계속되면 최대 3회 시도(최초 1 + 재시도 2) 후 NetworkError, 백오프 2s→4s
FAIL_TIMES=99; FAIL_EXIT=7; FAIL_HTTP="000"; FAIL_WRITE=""; OK_HTTP="200"; OK_WRITE="$SCRIPT_JSON"
run "전송실패 지속(exit7)"                1 "NetworkError" 3 "2 4"
# C3: 타임아웃(exit 28) 지속 → 동일하게 3회 시도 후 NetworkError
FAIL_TIMES=99; FAIL_EXIT=28; FAIL_HTTP="000"; FAIL_WRITE=""; OK_HTTP="200"; OK_WRITE="$SCRIPT_JSON"
run "타임아웃 지속(exit28)"               1 "NetworkError" 3 "2 4"
# C3: 1회 전송 실패 후 성공 → 2회 시도, 백오프 1회(2s), rc=0, 에러 로그 없음
FAIL_TIMES=1; FAIL_EXIT=7; FAIL_HTTP="000"; FAIL_WRITE=""; OK_HTTP="200"; OK_WRITE="$SCRIPT_JSON"
run "1회 실패 후 성공"                   0 ""            2 "2"
# C3: 2회 전송 실패 후 성공 → 3회 시도, 백오프 2회(2s 4s), rc=0
FAIL_TIMES=2; FAIL_EXIT=7; FAIL_HTTP="000"; FAIL_WRITE=""; OK_HTTP="200"; OK_WRITE="$SCRIPT_JSON"
run "2회 실패 후 성공"                   0 ""            3 "2 4"
# C3: 서버 일시 장애(503) 지속 → 3회 시도 후 NetworkError(JsonParsingError 로 오분류되지 않음)
FAIL_TIMES=99; FAIL_EXIT=0; FAIL_HTTP="503"; FAIL_WRITE='The service is unavailable.'; OK_HTTP="200"; OK_WRITE="$SCRIPT_JSON"
run "서버 일시장애 503 지속"              1 "NetworkError" 3 "2 4"
# C3: 503 이 1회 후 정상 응답 → 2회 시도 후 rc=0
FAIL_TIMES=1; FAIL_EXIT=0; FAIL_HTTP="503"; FAIL_WRITE='The service is unavailable.'; OK_HTTP="200"; OK_WRITE="$SCRIPT_JSON"
run "503 1회 후 정상"                     0 ""            2 "2"
# 재시도 대상 아님: HTTP 200 + 빈 본문(curl exit 0) → 시도 1회, NetworkError(giip 3936 가드 이전 단계)
FAIL_TIMES=0; FAIL_EXIT=0; FAIL_HTTP="000"; FAIL_WRITE=""; OK_HTTP="200"; OK_WRITE=""
run "빈 응답(전송성공, 본문없음)"        1 "NetworkError" 1 ""
# 재시도 대상 아님: 공백만 있는 본문 → giip 3936 가드, rc=0, 에러 없음
FAIL_TIMES=0; OK_HTTP="200"; OK_WRITE=$'   \n\t  \n'; run "공백만 응답"                0 ""            1 ""
# 정상: RstVal=0(큐 없음=정상) → 시도 1회, rc=0, 에러 없음
FAIL_TIMES=0; OK_HTTP="200"; OK_WRITE='{"RstVal":"0"}'; run "RstVal=0 큐없음(정상)"       0 ""            1 ""
# 정상: ms_body 포함 실제 스크립트 → 시도 1회, rc=0, 에러 없음
FAIL_TIMES=0; OK_HTTP="200"; OK_WRITE="$SCRIPT_JSON"; run "정상 ms_body 스크립트"        0 ""            1 ""
# 진짜 무효: 비어있지 않은 비-JSON 쓰레기 → JsonParsingError(올바른 분류), 재시도 없음
FAIL_TIMES=0; OK_HTTP="200"; OK_WRITE='garbage not json at all'
run "비어있지않은 무효응답(진짜파싱실패)"  1 "JsonParsingError" 1 ""

echo
echo "=== 요약: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" = 0 ] && exit 0 || exit 1
