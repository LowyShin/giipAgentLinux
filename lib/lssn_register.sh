#!/bin/bash
# giipAgentLinux Library: Server self-registration (lssn=0)
# Purpose: lssn=0 으로 설치된 에이전트가 첫 실행 시 서버를 등록하고, 발급된 lssn 을
#          cnf(또는 사이드카 giipAgent.lssn)에 저장한다.
# Requires: lib/common.sh (log_message, persist_lssn)
#
# 배경 (giip 2928 후속):
#   - giipAgent.sh(v2)는 ASP cqequeueget03.asp 가 plain-text lssn 을 돌려줘 `cat` 으로 읽었다.
#   - giipAgent3.sh 는 giipApiSk2(JSON)로 바꾸면서도 plain-text 파싱을 유지했고,
#     text 에 파라미터명 없이 `CQEQueueGet` 만 보내 SP 에 lssn/hostname 이 전달되지 않았다.
#     결과: 매 실행 tLSvr 에 새 행이 INSERT 되고 cnf 는 lssn=0 그대로 → 무한 재등록.
#   - giipApiSk2 응답(첫 결과셋만 JSON):
#       {"data":[{"RstVal":"201","lssn":12345,"ProcName":"[pLSvrInfoInputSimplebySK]"}],...}
#     RstVal 200(기존 hostname 재사용) / 201(신규 등록)만 성공으로 본다.

# Function: Build CQEQueueGet jsondata for registration (lssn=0)
# Usage: build_register_jsondata "$hostname" "$os"
build_register_jsondata() {
	local hostname="$1"
	local os="$2"
	if command -v jq >/dev/null 2>&1; then
		jq -nc --arg hostname "$hostname" --arg os "$os" --arg op "op" \
			'{lssn: 0, hostname: $hostname, os: $os, op: $op}'
	else
		# jq 가 없을 때: \ 와 " 만 이스케이프하는 최소 직렬화 (hostname/os 에 제어문자는 없다고 가정)
		local h o
		h=$(printf '%s' "$hostname" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
		o=$(printf '%s' "$os" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
		printf '{"lssn":0,"hostname":"%s","os":"%s","op":"op"}' "$h" "$o"
	fi
}

# Function: Extract issued lssn from a giipApiSk2 CQEQueueGet response file
# Usage: parse_register_response "$response_file"  → echoes lssn on success
# Returns: 0 if RstVal is 200/201 and lssn is a positive integer, 1 otherwise
parse_register_response() {
	local resp="$1"
	[ -s "$resp" ] || return 1
	local rst="" val=""
	if command -v jq >/dev/null 2>&1; then
		rst=$(jq -r '.data[0].RstVal // empty' "$resp" 2>/dev/null)
		val=$(jq -r '.data[0].lssn // empty' "$resp" 2>/dev/null)
	fi
	# jq 부재/파싱실패 시 grep/sed 폴백
	if [ -z "$rst" ]; then
		rst=$(tr -d '\n\r' < "$resp" | grep -o '"RstVal"[[:space:]]*:[[:space:]]*"\{0,1\}[0-9]*' | head -1 | grep -o '[0-9]*$')
	fi
	if [ -z "$val" ]; then
		val=$(tr -d '\n\r' < "$resp" | grep -o '"lssn"[[:space:]]*:[[:space:]]*"\{0,1\}[0-9]*' | head -1 | grep -o '[0-9]*$')
	fi
	case "$rst" in
		200|201) ;;
		*) return 1 ;;
	esac
	if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -gt 0 ]; then
		echo "$val"
		return 0
	fi
	return 1
}

# Function: Register this server (lssn=0) and persist the issued lssn
# Usage: register_server "$config_file" "$hostname" "$os"
# Globals: reads sk, apiaddrv2; on success sets and exports lssn
# Returns: 0 = registered and persisted (cnf or sidecar), 1 = failed
register_server() {
	local config_file="$1"
	local hostname="$2"
	local os="$3"

	if [ -z "$sk" ] || [ -z "$apiaddrv2" ]; then
		log_message "ERROR" "register_server: missing sk or apiaddrv2"
		return 1
	fi

	local api_url jsondata resp
	api_url=$(build_api_url "${apiaddrv2}")
	jsondata=$(build_register_jsondata "$hostname" "$os")
	resp=$(mktemp "${TMPDIR:-/tmp}/giip_register_resp.XXXXXX") || return 1

	# giipapi 규칙: text 에는 SP 파라미터명, jsondata 에 실제 값. 값은 URL 인코딩한다.
	curl -s -X POST "${api_url}" \
		--data-urlencode "text=CQEQueueGet lssn hostname os op" \
		--data-urlencode "token=${sk}" \
		--data-urlencode "jsondata=${jsondata}" \
		-H "Content-Type: application/x-www-form-urlencoded" \
		--insecure --connect-timeout 10 --max-time 30 -o "$resp" 2>/dev/null
	local curl_rc=$?

	local new_lssn
	new_lssn=$(parse_register_response "$resp")
	if [ -z "$new_lssn" ]; then
		local raw
		raw=$(head -c 500 "$resp" 2>/dev/null | tr -d '\n\r')
		log_message "ERROR" "Server registration failed (curl exit=${curl_rc}). Raw response (first 500 bytes): ${raw}"
		rm -f "$resp"
		return 1
	fi
	rm -f "$resp"

	log_message "INFO" "Server registered with LSSN: ${new_lssn}"
	persist_lssn "$config_file" "$new_lssn"
	local prc=$?
	if [ $prc -eq 1 ]; then
		return 1
	fi

	lssn="$new_lssn"
	export lssn
	return 0
}
