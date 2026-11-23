#!/bin/bash
# ============================================================================
# host-probe.cqe.sh — GIIP #6233 Linux leg: 자유 질의 호스트 프로브
# ----------------------------------------------------------------------------
# 이 스크립트는 "lowy-dp01(Windows) 과 동일한 질의 파이프라인" 의 Linux 판이다.
#   질문(Question) 을 인자로 받아
#     1) 호스트의 결정적 사실(hostname/os/uptime/disk/memory/docker/giipAgent/메모리 상위)
#        을 읽기 전용으로 수집하고
#     2) gair(giipAiRouter) 경유로 질문을 조사한 뒤
#     3) 결과를 GIIP tKVS 에 저장해(lowy님이 조회할 수 있게 한다).
#
# 저장은 두 건이다 (giip #6233 요구 스키마):
#   kType="$(hostname).probe"  kKey=$ProbeId  kFactor='answer'  kValue={question,answer,facts,hostname,ts,engine}
#   kType="$(hostname).probe"  kKey=$ProbeId  kFactor='status'  kValue={state,reason}
#
# CQE 전달 방식:
#   giipAgentLinux 는 CQE 로 내려받은 스크립트 본문을 `sh "$script_file"` 로 실행한다
#   (lib/normal.sh execute_script). 이때 load_config 가 export 한 $sk / $lssn / $apiaddrv2 가
#   환경변수로 주입되므로 그것을 우선 사용한다. CQE 로 전달되지 않고 레포에서 직접 실행할
#   때(=bash cqe/host-probe.cqe.sh <ProbeId> <Question>) 는 호스트의 giipAgent.cnf 를 읽는다.
#
# ⚠️ CSN 무관 스크립트다 (giipAgentLinux 규칙):
#    특정 CSN · lssn · 호스트명을 코드에 박지 않는다. kType 은 실행 시 hostname 으로 만든다.
#
# 보안:
#    SK / AK / gair 함수 키 값은 stdout·stderr·로그·KVS 본문 어디에도 남기지 않는다.
#    (KVS 에는 질문·답변·사실만 저장한다.)
#
# 등록: giipdb/mgmt/register-*.ps1 로 tMgmtScript(script_type='sh') 에 등록 후 CQE 로 호출.
# 사양: giip #6233 (Windows leg = lowyworkenv scripts/cqe/dp01-probe.ps1)
# ============================================================================

# 로케일 고정 — CentOS 7.x 는 로케일이 다르면 명령어 출력 파싱이 깨진다 (MAINTENANCE_PRECAUTIONS §2)
export LC_ALL=C
export LANG=C

SCRIPT_VERSION="1.0"

# --- 실행 상한 -------------------------------------------------------------
# 자유 질의 조사(gair 호출) 최대 10분. 넘기면 timeout 이 124 를 돌려주고
# 사실 수집분만 저장 + status=failed 로 남긴다.
PROBE_TIMEOUT_SEC="${PROBE_TIMEOUT_SEC:-600}"

# --- gair 엔드포인트 -------------------------------------------------------
GAIR_BASE_URL="${GAIR_BASE_URL:-https://giipfaw.azurewebsites.net/api/gair}"
GAIR_MESSAGES_URL="${GAIR_MESSAGES_URL:-${GAIR_BASE_URL%/}/v1/messages}"
# gair 는 모델을 고정하지 않고 JEV 판정 → 프로파일 → 모델로 라우팅한다(shadow_mode 가 off 인 CSN).
# 직접 호출(curl) 경로는 요청 model 필드가 필요하다. MiniMax-M3 은 CSN 47 의 deep 프로파일 기본값이며
# prefix 규칙(minimax→MiniMax)으로 minimax 엔진이 잡힌다. env GAIR_MODEL 로 덮어쓸 수 있다.
GAIR_MODEL="${GAIR_MODEL:-MiniMax-M3}"
GAIR_MAX_TOKENS="${GAIR_MAX_TOKENS:-2048}"

# --- 저장 크기 상한 --------------------------------------------------------
FACTS_MAX_CHARS=12000
ANSWER_MAX_CHARS=20000

TMPDIR_PROBE=""
TMP_OUTPUT=""
PROBE_ID=""
QUESTION=""
SK=""
API_URL=""
API_CODE=""
ULOGINID=""
GAIR_FUNCTION_KEY=""
GAIR_TOKEN=""
GAIR_TOKEN_KIND=""
HOST_NAME="$(hostname 2>/dev/null)"
FACTS_JSON="{}"
ANSWER_TEXT=""
ANSWER_ENGINE=""
FAIL_REASON=""
KVS_PUT_PATH=""
CNF_FILE=""
SCRIPT_DIR="."

# ============================================================================
# 유틸
# ============================================================================

# stdout 은 ASCII 요약 전용. 진단은 stderr 로 보낸다.
err() { printf '[host-probe] %s\n' "$1" >&2; }

# JSON 문자열 본문 이스케이프 (따옴표 없는 값). 개행/탭/CR 을 제어문자로 바꾼다.
json_escape() {
	printf '%s' "$1" \
		| sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
		| sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g' -e 's/\t/\\t/g' -e 's/\r/\\r/g'
}

# 문자열을 감싼 JSON 문자열 리터럴
json_str() {
	printf '"%s"' "$(json_escape "$1")"
}

# stdin 의 각 줄을 JSON 문자열 배열로 만든다
json_str_array() {
	_first=1
	printf '['
	while IFS= read -r _line; do
		[ "$_first" -eq 1 ] || printf ','
		printf '%s' "$(json_str "$_line")"
		_first=0
	done
	printf ']'
}

cleanup() {
	[ -n "$TMP_OUTPUT" ] && rm -f "$TMP_OUTPUT"
	[ -n "$TMPDIR_PROBE" ] && rm -rf "$TMPDIR_PROBE"
	return 0
}
trap cleanup EXIT

# 설정 파일에서 값 하나만 읽는다 (파일을 source 하지 않는다 — 임의 코드 실행 회피).
# 사용법: read_cnf_value <key>
read_cnf_value() {
	[ -n "$CNF_FILE" ] && [ -f "$CNF_FILE" ] || return 0
	grep -E "^[[:space:]]*$1[[:space:]]*=" "$CNF_FILE" 2>/dev/null | tail -1 \
		| tr -d '\r' \
		| sed -e "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//" -e 's/[[:space:]]#.*$//' -e 's/[[:space:]]*$//' \
		| tr -d "\"'"
}

# 기준 URL 에서 다른 giipApi 함수 URL 을 만든다. 변환 규칙이 없으면 빈 문자열.
derive_api_url() {
	# $1 = 기준 URL, $2 = 목표 함수명
	case "$1" in
		*giipApiSk4*) printf '%s' "${1/giipApiSk4/$2}" ;;
		*giipApiSk3*) printf '%s' "${1/giipApiSk3/$2}" ;;
		*giipApiSk2*) printf '%s' "${1/giipApiSk2/$2}" ;;
		*giipApiSk)   printf '%s' "${1/giipApiSk/$2}" ;;
		*)            printf '' ;;
	esac
}

# ============================================================================
# 1. 인자 / 설정
# ============================================================================
parse_args() {
	# $1 = ProbeId, $2 = Question (둘 다 필수).
	# CQE 로 전달될 때는 인자가 붙지 않으므로 같은 이름의 환경변수도 받는다.
	PROBE_ID="${1:-${PROBE_ID:-}}"
	QUESTION="${2:-${QUESTION:-}}"

	if [ -z "$PROBE_ID" ] || [ -z "$QUESTION" ]; then
		err "usage: host-probe.cqe.sh <ProbeId> <Question> (both required)"
		return 1
	fi
	# tKVS 컬럼 길이 제한(tKVS.kKey varchar(100)) 안으로 자른다.
	PROBE_ID="$(printf '%s' "$PROBE_ID" | cut -c1-100)"
	return 0
}

resolve_config() {
	# --- 설정 파일 후보 ---
	# HOST_PROBE_CNF 로 경로를 직접 지정할 수 있다(테스트·특수 배치용).
	SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || SCRIPT_DIR="."
	for c in \
		"${HOST_PROBE_CNF:-}" \
		"$SCRIPT_DIR/../../giipAgent.cnf" \
		"$SCRIPT_DIR/../giipAgent.cnf" \
		"$SCRIPT_DIR/giipAgent.cnf" \
		"/home/giip/giipAgent.cnf" \
		"/opt/giip/giipAgent.cnf" \
		"/usr/local/giip/giipAgent.cnf"
	do
		if [ -f "$c" ]; then
			CNF_FILE="$c"
			break
		fi
	done

	# --- SK ---
	# CQE 전달 경로에서는 환경변수로 주입된다(giipAgentLinux 가 export).
	[ -z "$SK" ] && SK="${sk:-}"
	[ -z "$SK" ] && [ -n "$CNF_FILE" ] && SK="$(read_cnf_value sk)"
	if [ -z "$SK" ]; then
		err "SK not found (env sk / giipAgent.cnf 'sk=')"
		return 1
	fi

	# --- API 엔드포인트 (KVSPut 용) ---
	[ -z "$API_URL" ] && API_URL="${apiaddrv2:-}"
	[ -z "$API_URL" ] && [ -n "$CNF_FILE" ] && API_URL="$(read_cnf_value apiaddrv2)"
	if [ -z "$API_URL" ]; then
		err "apiaddrv2 not found (env apiaddrv2 / giipAgent.cnf 'apiaddrv2=')"
		return 1
	fi

	# --- AdminGetAK 용 함수 코드(giipApi?code=) ---
	API_CODE="${GIIP_AZURE_CODE:-}"
	[ -z "$API_CODE" ] && [ -n "$CNF_FILE" ] && API_CODE="$(read_cnf_value apiaddrcode)"

	# --- AdminGetAK 용 로그인 ID (SK + uloginid 2요소 인증) ---
	ULOGINID="${GIIP_ULOGINID:-}"
	[ -z "$ULOGINID" ] && [ -n "$CNF_FILE" ] && ULOGINID="$(read_cnf_value uloginid)"

	# --- gair 함수 키 (authLevel=function → x-functions-key) ---
	GAIR_FUNCTION_KEY="${GAIR_FUNCTION_KEY:-}"
	[ -z "$GAIR_FUNCTION_KEY" ] && [ -n "$CNF_FILE" ] && GAIR_FUNCTION_KEY="$(read_cnf_value gairfunctionkey)"
	[ -z "$GAIR_FUNCTION_KEY" ] && [ -n "$CNF_FILE" ] && GAIR_FUNCTION_KEY="$(read_cnf_value agentfunctionkey)"

	return 0
}

# ============================================================================
# 2. 결정적 사실 수집 (읽기 전용)
# ============================================================================
collect_facts() {
	HOST_NAME="$(hostname 2>/dev/null)"
	[ -z "$HOST_NAME" ] && HOST_NAME="unknown"

	OS_PRETTY="$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')"
	OS_NAME="$(grep -E '^NAME=' /etc/os-release 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')"
	OS_VERSION="$(grep -E '^VERSION_ID=' /etc/os-release 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')"
	KERNEL="$(uname -sr 2>/dev/null)"
	UPTIME_RAW="$(uptime 2>/dev/null | sed 's/^[[:space:]]*//')"
	UPTIME_SECONDS="$(cut -d' ' -f1 /proc/uptime 2>/dev/null | cut -d. -f1)"
	[ -z "$UPTIME_SECONDS" ] && UPTIME_SECONDS=0
	BOOT_TIME="$(date -d "@$(( $(date +%s) - UPTIME_SECONDS ))" '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)"

	# --- 디스크 (실제 파일시스템만, 최대 20건) ---
	DISK_JSON="$(
		df -h -P 2>/dev/null | awk 'NR>1 && $1 ~ /^\// {printf "%s|%s|%s|%s|%s|%s\n", $1, $2, $3, $4, $5, $6}' \
		| head -20 \
		| while IFS= read -r _row; do
			_dfs=$(printf '%s' "$_row" | cut -d'|' -f1)
			_dsize=$(printf '%s' "$_row" | cut -d'|' -f2)
			_dused=$(printf '%s' "$_row" | cut -d'|' -f3)
			_davail=$(printf '%s' "$_row" | cut -d'|' -f4)
			_dpct=$(printf '%s' "$_row" | cut -d'|' -f5)
			_dmnt=$(printf '%s' "$_row" | cut -d'|' -f6)
			printf '{"fs":%s,"size":%s,"used":%s,"avail":%s,"use_pct":%s,"mount":%s}' \
				"$(json_str "$_dfs")" "$(json_str "$_dsize")" "$(json_str "$_dused")" \
				"$(json_str "$_davail")" "$(json_str "$_dpct")" "$(json_str "$_dmnt")"
			printf '\n'
		done \
		| awk 'BEGIN{first=1} {if(!first) printf ","; printf "%s", $0; first=0} END{printf ""}' \
		| sed -e 's/^/[/' -e 's/$/]/'
	)"
	[ -z "$DISK_JSON" ] && DISK_JSON="[]"

	# --- 메모리 ---
	MEM_TOTAL="$(free -m 2>/dev/null | awk '/^Mem:/ {print $2}')"
	MEM_USED="$(free -m 2>/dev/null | awk '/^Mem:/ {print $3}')"
	MEM_FREE="$(free -m 2>/dev/null | awk '/^Mem:/ {print $4}')"
	MEM_SHARED="$(free -m 2>/dev/null | awk '/^Mem:/ {print $5}')"
	MEM_BUFFCACHE="$(free -m 2>/dev/null | awk '/^Mem:/ {print $6}')"
	MEM_AVAIL="$(free -m 2>/dev/null | awk '/^Mem:/ {print $7}')"
	MEM_SWAP_TOTAL="$(free -m 2>/dev/null | awk '/^Swap:/ {print $2}')"
	MEM_SWAP_USED="$(free -m 2>/dev/null | awk '/^Swap:/ {print $3}')"
	MEM_JSON="{\"total_mb\":$(json_str "$MEM_TOTAL"),\"used_mb\":$(json_str "$MEM_USED"),\"free_mb\":$(json_str "$MEM_FREE"),\"shared_mb\":$(json_str "$MEM_SHARED"),\"buff_cache_mb\":$(json_str "$MEM_BUFFCACHE"),\"available_mb\":$(json_str "$MEM_AVAIL"),\"swap_total_mb\":$(json_str "$MEM_SWAP_TOTAL"),\"swap_used_mb\":$(json_str "$MEM_SWAP_USED")}"

	# --- Docker (있을 때만) ---
	DOCKER_JSON="{\"installed\":false}"
	if command -v docker >/dev/null 2>&1; then
		DOCKER_VERSION="$(timeout 20 docker version --format '{{.Server.Version}}' 2>/dev/null | head -1 | tr -d '\r')"
		DOCKER_PS="$(
			timeout 20 docker ps --format '{{.Names}}|{{.Image}}|{{.Status}}' 2>/dev/null | head -20 \
			| while IFS= read -r _row; do
				_dname=$(printf '%s' "$_row" | cut -d'|' -f1)
				_dimage=$(printf '%s' "$_row" | cut -d'|' -f2)
				_dstatus=$(printf '%s' "$_row" | cut -d'|' -f3)
				printf '{"name":%s,"image":%s,"status":%s}' \
					"$(json_str "$_dname")" "$(json_str "$_dimage")" "$(json_str "$_dstatus")"
				printf '\n'
			done \
			| awk 'BEGIN{first=1} {if(!first) printf ","; printf "%s", $0; first=0} END{printf ""}' \
			| sed -e 's/^/[/' -e 's/$/]/'
		)"
		[ -z "$DOCKER_PS" ] && DOCKER_PS="[]"
		DOCKER_JSON="{\"installed\":true,\"server_version\":$(json_str "$DOCKER_VERSION"),\"containers\":${DOCKER_PS}}"
	fi

	# --- giipAgent 프로세스 / 서비스 ---
	GIIP_PROCS="$(pgrep -af 'giipAgent' 2>/dev/null | head -10)"
	GIIP_SERVICES=""
	if command -v systemctl >/dev/null 2>&1; then
		GIIP_SERVICES="$(systemctl list-units --type=service --all --no-legend 2>/dev/null | grep -i giip | head -10)"
	fi
	GIIP_PROCS_JSON="$(printf '%s\n' "$GIIP_PROCS" | json_str_array)"
	GIIP_SERVICES_JSON="$(printf '%s\n' "$GIIP_SERVICES" | json_str_array)"
	GIIP_JSON="{\"processes\":${GIIP_PROCS_JSON},\"services\":${GIIP_SERVICES_JSON}}"

	# --- 메모리 상위 프로세스 10개 ---
	if ps aux --sort=-%mem >/dev/null 2>&1; then
		TOP_ROWS="$(ps aux --sort=-%mem 2>/dev/null | head -11 | tail -10)"
	else
		TOP_ROWS="$(ps aux 2>/dev/null | head -11 | tail -10)"
	fi
	TOP_JSON="$(
		printf '%s\n' "$TOP_ROWS" \
		| while IFS= read -r _row; do
			[ -z "$_row" ] && continue
			_tpid=$(printf '%s' "$_row" | awk '{print $2}')
			_tuser=$(printf '%s' "$_row" | awk '{print $1}')
			_tcpu=$(printf '%s' "$_row" | awk '{print $3}')
			_tmem=$(printf '%s' "$_row" | awk '{print $4}')
			_trss=$(printf '%s' "$_row" | awk '{print $6}')
			_tcmd=$(printf '%s' "$_row" | cut -c 11-)
			printf '{"pid":%s,"user":%s,"cpu_pct":%s,"mem_pct":%s,"rss_kb":%s,"command":%s}' \
				"$(json_str "$_tpid")" "$(json_str "$_tuser")" "$(json_str "$_tcpu")" \
				"$(json_str "$_tmem")" "$(json_str "$_trss")" "$(json_str "$_tcmd")"
			printf '\n'
		done \
		| awk 'BEGIN{first=1} {if(!first) printf ","; printf "%s", $0; first=0} END{printf ""}' \
		| sed -e 's/^/[/' -e 's/$/]/'
	)"
	[ -z "$TOP_JSON" ] && TOP_JSON="[]"

	FACTS_JSON="{\"hostname\":$(json_str "$HOST_NAME"),\"os_name\":$(json_str "$OS_NAME"),\"os_version\":$(json_str "$OS_VERSION"),\"os_pretty\":$(json_str "$OS_PRETTY"),\"kernel\":$(json_str "$KERNEL"),\"uptime\":$(json_str "$UPTIME_RAW"),\"uptime_seconds\":$(json_str "$UPTIME_SECONDS"),\"boot_time\":$(json_str "$BOOT_TIME"),\"disk\":${DISK_JSON},\"memory\":${MEM_JSON},\"docker\":${DOCKER_JSON},\"giipagent\":${GIIP_JSON},\"top_memory\":${TOP_JSON}}"

	return 0
}

# ============================================================================
# 3. 프롬프트
# ============================================================================
build_prompt() {
	PROMPT="당신은 Linux 호스트의 상태를 조사하는(read-only) 진단 도우미입니다.
아래는 이 호스트에서 이미 수집한 사실(facts) 입니다. 그리고 아래 질문에 답하세요.

[질문]
$QUESTION

[수집된 사실]
$FACTS_JSON

[규칙]
- 읽기 전용으로만 조사하고, 확인한 사실만 답하라.
- 변경·삭제·재시작·설정 수정을 하지 마라.
- 사실(facts)에 없는 내용은 추정하지 말고 '확인 필요' 라고 명시하라.
- 답은 질문에 직접 답하는 내용 위주로, 확인한 수치와 명령 결과를 함께 적어라.
- 답변 본문만 출력하라(앞뒤에 설명을 덧붙이지 마라)."
	printf '%s' "$PROMPT"
}

# ============================================================================
# 4. gair 인증 토큰 (AK 파생 → 안 되면 SK 직접 사용)
# ============================================================================
# AdminGetAK: SK + uloginid 2요소 → 최신 AK (giipdb/SP/pApiAdminGetAKbyAK.sql).
# gair 는 AK 또는 프로젝트 SK 를 토큰으로 받고 해석은 bySK 우선이다(giip #6224).
#   → AK 파생이 안 되면 SK 를 그대로 토큰으로 써도 된다.
derive_ak() {
	AK=""
	if [ -z "$ULOGINID" ] || [ -z "$API_CODE" ]; then
		err "AdminGetAK skipped (uloginid or apiaddrcode missing) - SK used as gair token"
		return 1
	fi

	_admin_url="$(derive_api_url "$API_URL" giipApi)"
	[ -z "$_admin_url" ] && _admin_url="https://giipfaw.azurewebsites.net/api/giipApi"

	_resp="$(curl -sS --max-time 30 -X POST "${_admin_url}?code=${API_CODE}" \
		-H "Content-Type: application/x-www-form-urlencoded" \
		--data-urlencode "text=AdminGetAK" \
		--data-urlencode "token=${SK}" \
		--data-urlencode "jsondata={\"uloginid\":\"${ULOGINID}\"}" 2>/dev/null)"

	if [ -z "$_resp" ]; then
		err "AdminGetAK empty response"
		return 1
	fi

	AK="$(printf '%s' "$_resp" | jq -r '.data[0].ak // .ak // empty' 2>/dev/null)"
	if [ -z "$AK" ]; then
		AK="$(printf '%s' "$_resp" | grep -oE '"ak"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -e 's/.*"ak"[[:space:]]*:[[:space:]]*"//' -e 's/"$//')"
	fi
	if [ -z "$AK" ]; then
		err "AdminGetAK did not return ak"
		return 1
	fi
	return 0
}

resolve_gair_token() {
	GAIR_TOKEN=""
	GAIR_TOKEN_KIND=""
	if derive_ak; then
		GAIR_TOKEN="$AK"
		GAIR_TOKEN_KIND="ak"
		AK=""
	else
		GAIR_TOKEN="$SK"
		GAIR_TOKEN_KIND="sk"
	fi
	[ -z "$GAIR_TOKEN" ] && return 1
	return 0
}

# ============================================================================
# 5. 조사 실행 — claude CLI 있으면 CLI, 없으면 gair Messages API 직접 호출
# ============================================================================
run_with_claude_cli() {
	# $1 = 프롬프트. stdout 으로 답변을 돌려준다.
	_prompt="$1"
	_claude_bin="$(command -v claude 2>/dev/null)"
	[ -n "$_claude_bin" ] || return 1

	# 전용 클린 설정 디렉터리 (giip #6229: 기본 설정을 쓰면 커넥터 비활성 조건에서 플러그인
	# 로드 실패로 exit 1 이 난다). 이 디렉터리는 지우지 않는다.
	_claude_cfg="${CLAUDE_CONFIG_DIR_PROBE:-${HOME:-/root}/.claude-gair-host}"
	mkdir -p "$_claude_cfg" 2>/dev/null || return 1

	err "engine=claude-cli config_dir=$_claude_cfg"

	if command -v timeout >/dev/null 2>&1; then
		timeout "$PROBE_TIMEOUT_SEC" env -u ANTHROPIC_API_KEY -u ANTHROPIC_MODEL \
			ANTHROPIC_BASE_URL="$GAIR_BASE_URL" \
			ANTHROPIC_AUTH_TOKEN="$GAIR_TOKEN" \
			ANTHROPIC_CUSTOM_HEADERS="x-functions-key: ${GAIR_FUNCTION_KEY}" \
			CLAUDE_CONFIG_DIR="$_claude_cfg" \
			"$_claude_bin" -p "$_prompt" \
				--dangerously-skip-permissions \
				--disallowedTools Write,Edit,NotebookEdit,WebFetch,WebSearch
	else
		env -u ANTHROPIC_API_KEY -u ANTHROPIC_MODEL \
			ANTHROPIC_BASE_URL="$GAIR_BASE_URL" \
			ANTHROPIC_AUTH_TOKEN="$GAIR_TOKEN" \
			ANTHROPIC_CUSTOM_HEADERS="x-functions-key: ${GAIR_FUNCTION_KEY}" \
			CLAUDE_CONFIG_DIR="$_claude_cfg" \
			"$_claude_bin" -p "$_prompt" \
				--dangerously-skip-permissions \
				--disallowedTools Write,Edit,NotebookEdit,WebFetch,WebSearch
	fi
	return $?
}

run_with_gair_api() {
	# $1 = 프롬프트. stdout 으로 답변을 돌려준다.
	_prompt="$1"

	_body="{\"model\":$(json_str "$GAIR_MODEL"),\"max_tokens\":${GAIR_MAX_TOKENS},\"messages\":[{\"role\":\"user\",\"content\":$(json_str "$_prompt")}]}"

	TMP_OUTPUT="$(mktemp "${TMPDIR:-/tmp}/host-probe-gair.XXXXXX" 2>/dev/null)" || {
		err "mktemp failed"
		return 2
	}

	if command -v timeout >/dev/null 2>&1; then
		timeout "$PROBE_TIMEOUT_SEC" curl -sS --max-time "$PROBE_TIMEOUT_SEC" \
			-X POST "$GAIR_MESSAGES_URL" \
			-H "Content-Type: application/json" \
			-H "Authorization: Bearer ${GAIR_TOKEN}" \
			-H "x-functions-key: ${GAIR_FUNCTION_KEY}" \
			-d "$_body" -o "$TMP_OUTPUT" 2>/dev/null
	else
		curl -sS --max-time "$PROBE_TIMEOUT_SEC" \
			-X POST "$GAIR_MESSAGES_URL" \
			-H "Content-Type: application/json" \
			-H "Authorization: Bearer ${GAIR_TOKEN}" \
			-H "x-functions-key: ${GAIR_FUNCTION_KEY}" \
			-d "$_body" -o "$TMP_OUTPUT" 2>/dev/null
	fi
	_rc=$?
	if [ "$_rc" -ne 0 ]; then
		err "gair http call failed rc=$_rc"
		return 1
	fi

	# Anthropic Messages 응답에서 text 블록을 뽑는다.
	_text=""
	if command -v jq >/dev/null 2>&1; then
		_text="$(jq -r '[.content[]? | select(.type == "text") | .text] | join("\n")' "$TMP_OUTPUT" 2>/dev/null)"
	fi
	if [ -z "$_text" ]; then
		_text="$(sed -n 's/.*"text"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$TMP_OUTPUT" 2>/dev/null | head -40)"
	fi
	if [ -z "$_text" ]; then
		err "gair response has no text block"
		return 1
	fi
	printf '%s' "$_text"
	return 0
}

run_investigation() {
	# $1 = 프롬프트. stdout 으로 답변, rc 로 결과.
	_prompt="$1"

	if command -v claude >/dev/null 2>&1; then
		run_with_claude_cli "$_prompt"
		return $?
	fi

	# ANSWER_ENGINE 은 호출자(main)가 정한다 — 이 함수는 커맨드 치환으로
	# 불려서 여기서 정한 값은 부모 셸에 남지 않는다.
	err "claude CLI not found - falling back to gair Messages API (curl)"
	run_with_gair_api "$_prompt"
	return $?
}

# ============================================================================
# 6. tKVS 저장
# ============================================================================
# $1 kType, $2 kKey, $3 kFactor, $4 kValue(JSON)
# KVSPut 은 append(INSERT) 다 — 같은 (kType,kKey,kFactor) 로 여러 번 쌓이고 최신 행이 마지막이다.
kvs_put_probe() {
	_kt="$1"
	_kk="$2"
	_kf="$3"
	_kv="$4"

	_payload="{\"kType\":$(json_str "$_kt"),\"kKey\":$(json_str "$_kk"),\"kFactor\":$(json_str "$_kf"),\"kValue\":${_kv}}"

	_sk4_url="$(derive_api_url "$API_URL" giipApiSk4)"
	_sk2_url="$(derive_api_url "$API_URL" giipApiSk2)"

	_rst=""

	# 1순위: giipApiSk4 (파라미터 진짜 바인딩 — jsondata 의 kValue 가 그대로 @kValue 로 bind)
	if [ -n "$_sk4_url" ]; then
		_resp="$(curl -sS --max-time 30 -X POST "$_sk4_url" \
			-H "Content-Type: application/x-www-form-urlencoded" \
			--data-urlencode "text=KVSPut kType kKey kFactor kValue" \
			--data-urlencode "token=${SK}" \
			--data-urlencode "jsondata=${_payload}" 2>/dev/null)"
		_rst="$(printf '%s' "$_resp" | jq -r '.data[0].RstVal // .RstVal // empty' 2>/dev/null)"
		[ -z "$_rst" ] && _rst="$(printf '%s' "$_resp" | grep -oE '"RstVal"[[:space:]]*:[[:space:]]*"?[0-9]+' | head -1 | grep -oE '[0-9]+')"
		if [ "$_rst" = "200" ]; then
			KVS_PUT_PATH="giipApiSk4"
			return 0
		fi
		err "KVSPut via giipApiSk4 failed (RstVal=${_rst:-none})"
	fi

	# 2순위: giipApiSk2 (레포의 kvs_put 이 쓰는 경로 — KVSPut 전용 분기가 있다)
	if [ -n "$_sk2_url" ]; then
		_resp="$(curl -sS --max-time 30 -X POST "$_sk2_url" \
			-H "Content-Type: application/x-www-form-urlencoded" \
			--data-urlencode "text=KVSPut kType kKey kFactor" \
			--data-urlencode "token=${SK}" \
			--data-urlencode "jsondata=${_payload}" 2>/dev/null)"
		_rst="$(printf '%s' "$_resp" | jq -r '.data[0].RstVal // .RstVal // empty' 2>/dev/null)"
		[ -z "$_rst" ] && _rst="$(printf '%s' "$_resp" | grep -oE '"RstVal"[[:space:]]*:[[:space:]]*"?[0-9]+' | head -1 | grep -oE '[0-9]+')"
		if [ "$_rst" = "200" ]; then
			KVS_PUT_PATH="giipApiSk2"
			return 0
		fi
		err "KVSPut via giipApiSk2 failed (RstVal=${_rst:-none})"
	fi

	KVS_PUT_PATH=""
	return 1
}

# ============================================================================
# main
# ============================================================================
main() {
	parse_args "$@" || exit 1
	resolve_config || exit 2

	TMPDIR_PROBE="$(mktemp -d "${TMPDIR:-/tmp}/host-probe.XXXXXX" 2>/dev/null)" || TMPDIR_PROBE=""

	collect_facts

	# kType = "<hostname>.probe" (tKVS.kType varchar(32) 안으로 자른다)
	_khost="$(printf '%s' "$HOST_NAME" | cut -c1-26)"
	KVS_TYPE="${_khost}.probe"

	_prompt="$(build_prompt)"
	if [ -z "$GAIR_FUNCTION_KEY" ]; then
		# gair 는 authLevel=function 이라 함수 키가 없으면 무조건 401 이다.
		# 애써 호출해서 401 본문을 "답변" 으로 저장하지 말고 사유를 남기고 끝낸다.
		err "gair function key not configured (env GAIR_FUNCTION_KEY / giipAgent.cnf 'gairfunctionkey=')"
		_answer=""
		_rc=2
		ANSWER_ENGINE="none"
	elif ! resolve_gair_token; then
		err "gair token unavailable (AK derive failed and no SK)"
		_answer=""
		_rc=2
		ANSWER_ENGINE="none"
	else
		# run_investigation 은 커맨드 치환(서브셸)으로 부르므로 그 안에서 정한
		# ANSWER_ENGINE 은 부모에 남지 않는다. 엔진은 여기서 미리 정한다.
		if command -v claude >/dev/null 2>&1; then
			ANSWER_ENGINE="gair/claude-cli"
		else
			ANSWER_ENGINE="gair/api"
		fi
		_answer="$(run_investigation "$_prompt")"
		_rc=$?
	fi
	ANSWER_TEXT="$_answer"

	_ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

	if [ "$_rc" -eq 0 ] && [ -n "$ANSWER_TEXT" ]; then
		_state="done"
		_reason=""
		_final_rc=0
	else
		_state="failed"
		case "$_rc" in
			2)   _reason="gair function key or temp file unavailable" ;;
			124) _reason="gair investigation timed out after ${PROBE_TIMEOUT_SEC}s" ;;
			*)   _reason="gair investigation failed (rc=${_rc})" ;;
		esac
		FAIL_REASON="$_reason"
		_final_rc=3
	fi

	# 크기 상한
	_answer_sized="$(printf '%s' "$ANSWER_TEXT" | cut -c1-$ANSWER_MAX_CHARS)"
	_facts_sized="$(printf '%s' "$FACTS_JSON" | cut -c1-$FACTS_MAX_CHARS)"

	_answer_json="{\"question\":$(json_str "$QUESTION"),\"answer\":$(json_str "$_answer_sized"),\"facts\":${_facts_sized},\"hostname\":$(json_str "$HOST_NAME"),\"ts\":$(json_str "$_ts"),\"engine\":$(json_str "gair"),\"engine_path\":$(json_str "$ANSWER_ENGINE"),\"script_version\":$(json_str "$SCRIPT_VERSION")}"
	_status_json="{\"state\":$(json_str "$_state"),\"reason\":$(json_str "$FAIL_REASON")}"

	kvs_put_probe "$KVS_TYPE" "$PROBE_ID" "answer" "$_answer_json"
	_answer_stored=$?
	kvs_put_probe "$KVS_TYPE" "$PROBE_ID" "status" "$_status_json"
	_status_stored=$?

	# stdout 은 ASCII 요약만 (giip #6233 요구: 한글은 KVS 본문에만)
	printf '[CQE-PROBE] host=%s probe=%s state=%s engine=%s\n' "$HOST_NAME" "$PROBE_ID" "$_state" "${ANSWER_ENGINE:-none}"
	printf '[CQE-PROBE] ktype=%s kfactor=answer stored=%s\n' "$KVS_TYPE" "$([ "$_answer_stored" -eq 0 ] && echo yes || echo no)"
	printf '[CQE-PROBE] ktype=%s kfactor=status stored=%s\n' "$KVS_TYPE" "$([ "$_status_stored" -eq 0 ] && echo yes || echo no)"
	printf '[CQE-PROBE] facts_chars=%s answer_chars=%s kvs_path=%s\n' "${#_facts_sized}" "${#_answer_sized}" "${KVS_PUT_PATH:-none}"

	if [ "$_answer_stored" -ne 0 ] || [ "$_status_stored" -ne 0 ]; then
		err "KVS save failed (answer=$_answer_stored status=$_status_stored)"
		exit 4
	fi

	exit "$_final_rc"
}

main "$@"
