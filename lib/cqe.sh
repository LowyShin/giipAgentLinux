#!/bin/bash
# giipAgent CQE (Centralized Queue Engine) Library
# Version: 1.00
# Date: 2025-11-28
# Purpose: CQE API wrapper functions for queue fetching
# Rule: Follow giipapi_rules.md - text contains parameter names only, jsondata contains actual values

# ============================================================================
# Queue Fetching Function (CQEQueueGet API wrapper)
# ============================================================================

# Function: Fetch queue from API with unified error handling
# Usage: queue_get "lssn" "hostname" "os" "output_file"
# Returns: 0 on success, 1 on failure
# Output: Extracted script saved to output_file
# 
# ✅ API Rules (giipapi_rules.md):
# - text: Parameter names only
# - jsondata: Actual values as JSON
queue_get() {
	local lssn=$1
	local hostname=$2
	local os=$3
	local output_file=$4
	
	# Validate required parameters
	if [ -z "$lssn" ] || [ -z "$hostname" ] || [ -z "$os" ] || [ -z "$output_file" ]; then
		echo "[queue_get] ⚠️  Missing required parameters (lssn, hostname, os, output_file)" >&2
		return 1
	fi
	
	# lssn=0 가드: pApiCQEQueueGetbySK 는 lssn=0 이면 서버 등록(pLSvrInfoInputSimplebySK)을
	# 수행해 tLSvr 에 행을 INSERT 한다. 큐 조회 경로에서 lssn=0 으로 호출하면 매 실행
	# 행이 늘어나므로 거부한다. 등록은 giipAgent3.sh → lib/lssn_register.sh 만 담당한다.
	if ! [[ "$lssn" =~ ^[0-9]+$ ]] || [ "$lssn" -eq 0 ]; then
		echo "[queue_get] ⚠️  WARN: refusing CQEQueueGet with lssn='${lssn}' (unregistered server; would create a new tLSvr row)" >&2
		if command -v log_message >/dev/null 2>&1; then
			log_message "WARN" "queue_get skipped: lssn='${lssn}' is not a registered lssn"
		fi
		return 1
	fi
	
	# Validate required global variables
	if [ -z "$sk" ] || [ -z "$apiaddrv2" ]; then
		echo "[queue_get] ⚠️  Missing required variables (sk, apiaddrv2)" >&2
		return 1
	fi
	
	# Build API URL
	local api_url="${apiaddrv2}"
	
	# ✅ Follow giipapi_rules.md: text contains parameter names only!
	# giip #2928: Use jq for proper JSON serialization to prevent malformed JSON on special characters
	local text="CQEQueueGet lssn hostname os op"
	local jsondata
	jsondata=$(jq -n --argjson lssn "$lssn" --arg hostname "$hostname" --arg os "$os" --arg op "op" '{lssn: $lssn, hostname: $hostname, os: $os, op: $op}')
	
	local temp_response="/tmp/queue_response_$$.json"
	
	# Clean up old temp files
	rm -f /tmp/queue_response_* 2>/dev/null
	rm -f /tmp/queue_status_* 2>/dev/null
	
	# URL encode parameters (same pattern as kvs.sh for consistency)
	# This is required because curl -d does NOT automatically encode values
	local encoded_text=$(printf '%s' "$text" | jq -sRr '@uri' 2>/dev/null || echo "$text")
	local encoded_token=$(printf '%s' "$sk" | jq -sRr '@uri' 2>/dev/null || echo "$sk")
	local encoded_jsondata=$(printf '%s' "$jsondata" | jq -sRr '@uri' 2>/dev/null || echo "$jsondata")
	
	# DEBUG: Log API call parameters to KVS for diagnostic purposes
	# This helps identify if parameters (especially 'os') are being passed correctly
	echo "[queue_get] 🐛 DEBUG: Calling CQEQueueGet API for LSSN=$lssn, hostname=$hostname, os=$os" >&2
	if command -v kvs_put >/dev/null 2>&1; then
		kvs_put "lssn" "$lssn" "cqe_api_call_debug" "{\"text\":\"$text\",\"os_value\":\"$os\",\"hostname\":\"$hostname\",\"lssn\":$lssn,\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}"
	fi
	
	# Call CQEQueueGet API with URL-encoded parameters
	# giip #1209: lssn 71174(cctrank03) observed hanging with no log output after the
	# DEBUG line above, for multiple consecutive cron cycles (cron.log, 07:45~09:45).
	# This curl call previously had no timeout, so an unresponsive/slow API could make
	# it block indefinitely, matching that symptom exactly. --connect-timeout/--max-time
	# values match the existing convention in lib/mssql.sh.
	#
	# giip #4167 (C3): 네트워크 일시 오류 시 최대 2회 백오프 재시도.
	# 1회 호출은 일시적인 연결 hiccup 한 번에도 cron 주기 전체를 실패로 남겼고 그 결과
	# ErrorLogs 에 NetworkError 가 반복 적재됐다. 재시도 대상은 2가지다:
	#   (1) 전송 실패 — curl 종료코드 != 0 (연결 거부·리셋·DNS·타임아웃)
	#   (2) 서버 일시 장애 — HTTP 5xx (giipfaw Function App 503 "The service is unavailable.")
	#       이 응답은 JSON 이 아니라 평문이라 기존 코드에서 "JSON 파싱 실패"로 오분류돼 왔다
	#       (giip 5866). HTTP 응답을 정상적으로 받은 빈 본문은 네트워크 오류가 아니므로
	#       재시도 대상이 아니고, 아래 giip 3936 가드 의미가 그대로 유지된다.
	local max_attempts=3          # 최초 1회 + 재시도 최대 2회
	local retry_delay=2           # 백오프 기본 초 — 2s → 4s 로 지수 증가
	local attempt=1
	local curl_exit_code=0
	local http_code=""
	local temp_status="/tmp/queue_status_$$.txt"
	while : ; do
		rm -f "$temp_response" "$temp_status"
		# -w 로 HTTP 상태 코드를 stdout(temp_status) 으로 받고, stderr 는 기존처럼 stdout 으로 보낸다
		curl -s -X POST "$api_url" \
			-d "text=${encoded_text}&token=${encoded_token}&jsondata=${encoded_jsondata}" \
			-H "Content-Type: application/x-www-form-urlencoded" \
			--insecure --connect-timeout 10 --max-time 30 \
			-o "$temp_response" -w "%{http_code}" 2>&1 > "$temp_status"
		curl_exit_code=$?
		http_code=$(tr -d '[:space:]' < "$temp_status" 2>/dev/null)

		# 재시도 필요 여부 판정
		local retryable=0
		if [ "$curl_exit_code" -ne 0 ]; then
			retryable=1
		fi
		case "$http_code" in
			5??) retryable=1 ;;
		esac

		# 일시 오류가 아니면 응답 해석 단계로 진행
		if [ "$retryable" -eq 0 ]; then
			break
		fi

		# 재시도 한도 도달 — 마지막 실패로 확정
		if [ "$attempt" -ge "$max_attempts" ]; then
			break
		fi

		echo "[queue_get] ⚠️  Transient API failure (curl exit: $curl_exit_code, http: ${http_code:-n/a}, attempt ${attempt}/${max_attempts}) — retrying in ${retry_delay}s" >&2
		sleep "$retry_delay"
		retry_delay=$((retry_delay * 2))
		attempt=$((attempt + 1))
	done
	rm -f "$temp_status" 2>/dev/null

	# 전송 자체가 실패한 상태(curl 종료코드 != 0)면 부분 본문이 남아 있어도 정상 응답으로 보지 않는다
	if [ "$curl_exit_code" -ne 0 ]; then
		local partial_note=""
		if [ -s "$temp_response" ]; then
			partial_note=" (partial body discarded)"
		fi
		rm -f "$temp_response"
		if [ "$curl_exit_code" -eq 28 ]; then
			echo "[queue_get] ❌ API call timed out (curl exit code: 28, connect-timeout=10s/max-time=30s, attempts=${attempt})${partial_note}" >&2
		else
			echo "[queue_get] ❌ API call failed or no response (curl exit code: $curl_exit_code, attempts=${attempt})${partial_note}" >&2
		fi

		# Log to ErrorLogs DB
		if command -v log_error >/dev/null 2>&1; then
			log_error "CQEQueueGet API call failed (curl exit: $curl_exit_code, attempts: $attempt)" "NetworkError" "API: $api_url, LSSN: $lssn, hostname: $hostname, os: $os"
		fi

		return 1
	fi

	# 서버 일시 장애(5xx): JSON 파싱 실패가 아니라 서비스 오류로 분류한다
	case "$http_code" in
		5??)
			local svc_body=""
			svc_body=$(head -c 200 "$temp_response" 2>/dev/null)
			rm -f "$temp_response"
			echo "[queue_get] ❌ API service unavailable (HTTP $http_code, attempts=${attempt}): ${svc_body}" >&2

			# Log to ErrorLogs DB
			if command -v log_error >/dev/null 2>&1; then
				log_error "CQEQueueGet API service unavailable (HTTP $http_code, attempts: $attempt)" "NetworkError" "API: $api_url, LSSN: $lssn, hostname: $hostname, os: $os, body: ${svc_body:0:200}"
			fi

			return 1
			;;
	esac

	# Check if response file was created and has content
	if [ ! -s "$temp_response" ]; then
		rm -f "$temp_response"
		echo "[queue_get] ❌ API call failed or no response (curl exit code: $curl_exit_code, empty body)" >&2

		# Log to ErrorLogs DB
		if command -v log_error >/dev/null 2>&1; then
			log_error "CQEQueueGet API call failed (curl exit: $curl_exit_code)" "NetworkError" "API: $api_url, LSSN: $lssn, hostname: $hostname, os: $os"
		fi

		return 1
	fi
	
	# Check API response status (RstVal field)
	local rst_val=$(jq -r '.data[0].RstVal // .RstVal // "unknown"' "$temp_response" 2>/dev/null)
	
	# If jq fails or RstVal not found, try grep
	if [ -z "$rst_val" ] || [ "$rst_val" = "unknown" ]; then
		rst_val=$(grep -o '"RstVal"\s*:\s*"[^"]*"' "$temp_response" 2>/dev/null | sed -n 's/.*"\([^"]*\)".*/\1/p' | head -1)
	fi
	
	# Handle API error responses
	if [ "$rst_val" != "200" ] && [ -n "$rst_val" ]; then
		local proc_name=$(jq -r '.data[0].ProcName // .ProcName // "unknown"' "$temp_response" 2>/dev/null)
		if [ -z "$proc_name" ]; then
			proc_name=$(grep -o '"ProcName"\s*:\s*"[^"]*"' "$temp_response" 2>/dev/null | sed -n 's/.*"\([^"]*\)".*/\1/p' | head -1)
		fi
		
		rm -f "$temp_response"
		
		# ✅ No queue available is a NORMAL situation (404), not an error
		# Only return success (0) with empty file to indicate "checked but no queue"
		if [[ "$proc_name" == *"404"* ]] || [[ "$rst_val" == *"404"* ]] || [ "$rst_val" = "0" ]; then
			echo "[queue_get] INFO: No queue available for LSSN=$lssn, hostname=$hostname, OS=$os (this is normal)" >&2
			# Create empty file to indicate we checked but found no queue
			touch "$output_file"
			return 0
		fi
		
		# Other errors are actual failures
		echo "[queue_get] ❌ API returned error: $rst_val - $proc_name" >&2
		
		# Log to ErrorLogs DB
		if command -v log_error >/dev/null 2>&1; then
			log_error "CQEQueueGet API error: RstVal=$rst_val, ProcName=$proc_name" "ApiError" "LSSN: $lssn, hostname: $hostname, os: $os, text: $text"
		fi
		
		return 1
	fi
	
	# Extract script and type from JSON response
	if command -v jq >/dev/null 2>&1; then
		local script=$(jq -r '.data[0].ms_body // .ms_body // empty' "$temp_response" 2>/dev/null)
		local script_type=$(jq -r '.data[0].script_type // .script_type // "sh"' "$temp_response" 2>/dev/null)
		# giip-967: capture mslsn/mssn too so execute_script() can tag the
		# resulting KVS script_execution log with which CQE schedule this was
		local resp_mslsn=$(jq -r '.data[0].mslsn // .mslsn // empty' "$temp_response" 2>/dev/null)
		local resp_mssn=$(jq -r '.data[0].mssn // .mssn // empty' "$temp_response" 2>/dev/null)
		if [ -n "$script" ] && [ "$script" != "null" ]; then
			echo "$script" > "$output_file"
			# Save script type to a sidecar file or return it
			echo "$script_type" > "${output_file}.type"
			# giip-967: sidecar files for mslsn/mssn (mirrors .type pattern above)
			[ -n "$resp_mslsn" ] && [ "$resp_mslsn" != "null" ] && echo "$resp_mslsn" > "${output_file}.mslsn"
			[ -n "$resp_mssn" ] && [ "$resp_mssn" != "null" ] && echo "$resp_mssn" > "${output_file}.mssn"
			rm -f "$temp_response"
			return 0
		fi
	fi
	
	# Method 2: Try sed/grep for fallback parsing
	if [ ! -s "$output_file" ] 2>/dev/null; then
		local normalized=$(tr -d '\n\r' < "$temp_response")
		local script=$(echo "$normalized" | sed -n 's/.*"ms_body"\s*:\s*"\([^"]*\)".*/\1/p' | head -1)
		if [ -n "$script" ]; then
			echo "$script" | sed 's/\\n/\n/g' > "$output_file"
			rm -f "$temp_response"
			return 0
		fi
	fi
	
	# If we reach here, extraction failed
	# Save response for debugging
	local response_content=$(cat "$temp_response" 2>/dev/null | head -c 1000)
	rm -f "$temp_response"

	# giip 3936: 빈 응답은 파싱 실패가 아니라 "받을 작업 없음 / 일시적 무응답" 으로 다룬다.
	# 전단의 404·RstVal=0 '큐 없음=정상' 처리와 같은 철학 — ErrorLogs 에 거짓 에러를 남기지 않는다.
	if [ -z "$(printf '%s' "$response_content" | tr -d '[:space:]')" ]; then
		echo "[queue_get] INFO: Empty response for LSSN=$lssn, hostname=$hostname, OS=$os (no work / transient — not an error)" >&2
		touch "$output_file"
		return 0
	fi

	echo "[queue_get] ❌ Failed to extract script from API response" >&2
	echo "[queue_get] DEBUG: Response content (first 1000 chars):" >&2
	echo "$response_content" >&2
	echo "[queue_get] DEBUG: API URL: $api_url" >&2
	echo "[queue_get] DEBUG: jsondata: $jsondata" >&2
	
	# Log to ErrorLogs DB
	if command -v log_error >/dev/null 2>&1; then
		log_error "CQEQueueGet JSON parsing failed" "JsonParsingError" "Response: ${response_content:0:500}, LSSN: $lssn, hostname: $hostname, os: $os"
	fi
	
	return 1
}

export -f queue_get
