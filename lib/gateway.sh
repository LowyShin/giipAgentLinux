#!/bin/bash
# giipAgent Gateway Mode Library
# Version: 2.00
# Date: 2025-01-10
# Purpose: Gateway mode functions for managing remote servers and database queries
# Rule: Follow giipapi_rules.md - text contains parameter names only, jsondata contains actual values

# Load SSH connection logger module
SCRIPT_DIR_GATEWAY_SSH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ -f "${SCRIPT_DIR_GATEWAY_SSH}/ssh_connection_logger.sh" ]; then
	. "${SCRIPT_DIR_GATEWAY_SSH}/ssh_connection_logger.sh"
else
	echo "⚠️  Warning: ssh_connection_logger.sh not found" >&2
fi

# Load remote SSH test result reporting module
if [ -f "${SCRIPT_DIR_GATEWAY_SSH}/remote_ssh_test.sh" ]; then
	. "${SCRIPT_DIR_GATEWAY_SSH}/remote_ssh_test.sh"
else
	echo "⚠️  Warning: remote_ssh_test.sh not found" >&2
fi

# Load KVS logging module for tKVS storage
if [ -f "${SCRIPT_DIR_GATEWAY_SSH}/kvs.sh" ]; then
	. "${SCRIPT_DIR_GATEWAY_SSH}/kvs.sh"
else
	# Provide stub function if kvs.sh not available
	kvs_put() {
		echo "[gateway.sh] ⚠️  WARNING: kvs_put stub called (kvs.sh not loaded)" >&2
		return 1
	}
fi

# Function: Log gateway operation to both stderr AND tKVS
# Usage: gateway_log "🟢" "[5.4]" "Gateway 서버 목록 조회 시작" "additional_json_data"
# Function: Gateway Operation Logging
# Purpose: Log to both stderr (console) and tKVS with point tracking
# Usage: gateway_log "emoji" "point_code" "message" [optional_details]
# Example: gateway_log "🟢" "[5.6]" "Server processed" "hostname=server1"
gateway_log() {
	local emoji="$1"
	local point="$2"
	local message="$3"
	local details="${4:-}"  # Optional details (not included in JSON to avoid escaping issues)
	local timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
	
	# Log to stderr (for console visibility and log files)
	if [ -n "$details" ]; then
		echo "[gateway.sh] ${emoji} ${point} ${message}: ${details}" >&2
	else
		echo "[gateway.sh] ${emoji} ${point} ${message}" >&2
	fi
	
	# Log to tKVS - store only essential info (point, timestamp)
	# This avoids JSON escaping issues with variable content
	local json_payload="{\"event_type\":\"gateway_operation\",\"point\":\"${point}\",\"timestamp\":\"${timestamp}\"}"
	
	if type kvs_put >/dev/null 2>&1; then
		kvs_put "lssn" "${lssn:-0}" "gateway_operation" "$json_payload" 2>/dev/null
	fi
}

# ============================================================================
# Server Management Functions
# ============================================================================

# Function: Get remote servers from database (real-time query, no cache)
# Per GATEWAY_CONFIG_PHILOSOPHY.md: Database as Single Source of Truth
# Returns: temp file path with JSON data (caller must delete!)
get_gateway_servers() {
	local temp_file="/tmp/gateway_servers_$$.json"
	local api_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && api_url="${api_url}?code=${apiaddrcode}"
	
	# 🔴 [로깅 포인트 #5.4] Gateway 서버 목록 조회 시작
	gateway_log "🟢" "[5.4]" "Gateway 서버 목록 조회 시작"
	
	local text="GatewayRemoteServerListForAgent lssn"
	local jsondata="{\"lssn\":${lssn}}"
	
	wget -O "$temp_file" \
		--post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"$api_url" \
		--no-check-certificate -q 2>&1
	
	if [ ! -s "$temp_file" ]; then
		# 🔴 [로깅 포인트 #5.4-ERROR] 서버 목록 조회 실패
		gateway_log "❌" "[5.4-ERROR]" "Gateway 서버 목록 조회 실패: file_empty=true"
		rm -f "$temp_file"
		return 1
	fi
	
	# Check for error response
	local err_check=$(cat "$temp_file" | grep -i "rstval.*40[0-9]")
	if [ -n "$err_check" ]; then
		# 🔴 [로깅 포인트 #5.4-ERROR] API 에러 응답
		gateway_log "❌" "[5.4-ERROR]" "Gateway 서버 목록 API 에러: ${err_check}"
		rm -f "$temp_file"
		return 1
	fi
	
	# 🔴 [로깅 포인트 #5.4-SUCCESS] 서버 목록 조회 성공
	local server_count=$(cat "$temp_file" | grep -o '{[^}]*}' | wc -l)
	gateway_log "🟢" "[5.4-SUCCESS]" "Gateway 서버 목록 조회 성공: count=${server_count}"
	
	echo "$temp_file"
	return 0
}

# Legacy function removed: sync_gateway_servers
# Reason: Database as Single Source of Truth - no CSV caching

# Function: Get DB queries from database (real-time query, no cache)
# Returns: temp file path with JSON data (caller must delete!)
get_db_queries() {
	local temp_file="/tmp/gateway_db_queries_$$.json"
	local api_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && api_url="${api_url}?code=${apiaddrcode}"
	
	local text="GatewayDBQueryList lssn"
	local jsondata="{\"lssn\":${lssn}}"
	
	wget -O "$temp_file" \
		--post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"$api_url" \
		--no-check-certificate -q 2>&1
	
	if [ ! -s "$temp_file" ]; then
		rm -f "$temp_file"
		return 1
	fi
	
	echo "$temp_file"
	return 0
}

# Legacy function removed: sync_db_queries
# Reason: Database as Single Source of Truth - no CSV caching

# Function: Get managed databases from tManagedDatabase (real-time query, no cache)
# Returns: temp file path with JSON data (caller must delete!)
get_managed_databases() {
	local temp_file="/tmp/managed_databases_$$.json"
	local api_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && api_url="${api_url}?code=${apiaddrcode}"
	
	local text="GatewayManagedDatabaseList lssn"
	local jsondata="{\"lssn\":${lssn}}"
	
	wget -O "$temp_file" \
		--post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"$api_url" \
		--no-check-certificate -q 2>&1
	
	if [ ! -s "$temp_file" ]; then
		echo "[Gateway] ⚠️  Failed to fetch managed databases from DB" >&2
		rm -f "$temp_file"
		return 1
	fi
	
	# Check for error response
	local err_check=$(cat "$temp_file" | grep -i "rstval.*40[0-9]")
	if [ -n "$err_check" ]; then
		echo "[Gateway] ⚠️  API error response" >&2
		rm -f "$temp_file"
		return 1
	fi
	
	echo "$temp_file"
	return 0
}

# ============================================================================
# Remote Execution Functions
# ============================================================================

# Function: Execute command on remote server
execute_remote_command() {
	local remote_host=$1
	local remote_user=$2
	local remote_port=$3
	local ssh_key=$4
	local ssh_password=$5
	local script_file=$6
	local remote_lssn=${7:-0}      # Optional LSSN parameter
	local hostname=${8:-"unknown"}  # Optional hostname parameter
	
	local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
	local start_time=$(date +%s)
	local auth_method="none"
	
	# Determine authentication method
	if [ -n "${ssh_password}" ]; then
		auth_method="password"
	elif [ -n "${ssh_key}" ] && [ -f "${ssh_key}" ]; then
		auth_method="key"
	fi
	
	# 🔍 Log SSH connection attempt
	if type log_ssh_attempt >/dev/null 2>&1; then
		log_ssh_attempt "$remote_host" "$remote_port" "$remote_user" "$auth_method" "$remote_lssn" "$hostname"
	fi
	
	local exit_code=1
	
	if [ -n "${ssh_password}" ]; then
		if ! command -v sshpass &> /dev/null; then
			echo "  ❌ sshpass not available"
			local duration=$(($(date +%s) - start_time))
			
			# Log failure
			if type log_ssh_result >/dev/null 2>&1; then
				log_ssh_result "$remote_host" "$remote_port" "127" "$duration" "$remote_lssn" "$hostname"
			fi
			return 1
		fi
		
		sshpass -p "${ssh_password}" scp ${ssh_opts} -P ${remote_port} \
		    ${script_file} ${remote_user}@${remote_host}:/tmp/giipTmpScript.sh 2>&1 | head -5
		
		if [ $? -ne 0 ]; then
			local duration=$(($(date +%s) - start_time))
			
			# Log SCP failure
			if type log_ssh_result >/dev/null 2>&1; then
				log_ssh_result "$remote_host" "$remote_port" "126" "$duration" "$remote_lssn" "$hostname"
			fi
			return 1
		fi
		
		sshpass -p "${ssh_password}" ssh ${ssh_opts} -p ${remote_port} \
		    ${remote_user}@${remote_host} \
		    "chmod +x /tmp/giipTmpScript.sh && /tmp/giipTmpScript.sh && rm -f /tmp/giipTmpScript.sh" 2>&1 | head -20
		
		exit_code=$?
		
	elif [ -n "${ssh_key}" ] && [ -f "${ssh_key}" ]; then
		scp ${ssh_opts} -i ${ssh_key} -P ${remote_port} \
		    ${script_file} ${remote_user}@${remote_host}:/tmp/giipTmpScript.sh 2>&1 | head -5
		
		if [ $? -ne 0 ]; then
			local duration=$(($(date +%s) - start_time))
			
			# Log SCP failure
			if type log_ssh_result >/dev/null 2>&1; then
				log_ssh_result "$remote_host" "$remote_port" "126" "$duration" "$remote_lssn" "$hostname"
			fi
			return 1
		fi
		
		ssh ${ssh_opts} -i ${ssh_key} -p ${remote_port} \
		    ${remote_user}@${remote_host} \
		    "chmod +x /tmp/giipTmpScript.sh && /tmp/giipTmpScript.sh && rm -f /tmp/giipTmpScript.sh" 2>&1 | head -20
		
		exit_code=$?
	else
		echo "  ❌ No authentication method available"
		local duration=$(($(date +%s) - start_time))
		
		# Log no auth failure
		if type log_ssh_result >/dev/null 2>&1; then
			log_ssh_result "$remote_host" "$remote_port" "125" "$duration" "$remote_lssn" "$hostname"
		fi
		return 1
	fi
	
	# Calculate duration
	local duration=$(($(date +%s) - start_time))
	
	# 🔍 Log SSH connection result
	if type log_ssh_result >/dev/null 2>&1; then
		log_ssh_result "$remote_host" "$remote_port" "$exit_code" "$duration" "$remote_lssn" "$hostname"
	fi
	
	return $exit_code
}

# ============================================================================
# Queue Management Functions
# ============================================================================

# Function: Get script by mssn (from repository)
get_script_by_mssn() {
	local mssn=$1
	local output_file=$2
	
	local api_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && api_url="${api_url}?code=${apiaddrcode}"
	
	local text="CQERepoScript mssn"
	local jsondata="{\"mssn\":${mssn}}"
	
	wget -O "$output_file" \
		--post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"$api_url" \
		--no-check-certificate -q 2>&1
	
	if [ -s "$output_file" ]; then
		dos2unix "$output_file" 2>/dev/null
		return 0
	fi
	return 1
}

# Function: Get queue for specific server
get_remote_queue() {
	local lssn=$1
	local hostname=$2
	local os=$3
	local output_file=$4
	
	local api_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && api_url="${api_url}?code=${apiaddrcode}"
	
	local text="CQEQueueGet lssn hostname os op"
	local jsondata="{\"lssn\":${lssn},\"hostname\":\"${hostname}\",\"os\":\"${os}\",\"op\":\"op\"}"
	
	wget -O "$output_file" \
		--post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"$api_url" \
		--no-check-certificate -q 2>&1
	
	if [ -s "$output_file" ]; then
		local is_json=$(cat "$output_file" | grep -o '^{.*}$')
		if [ -n "$is_json" ]; then
			local rstval=$(cat "$output_file" | grep -o '"RstVal":"[^"]*"' | sed 's/"RstVal":"//; s/"$//' | head -1)
			local script_body=$(cat "$output_file" | grep -o '"ms_body":"[^"]*"' | sed 's/"ms_body":"//; s/"$//' | sed 's/\\n/\n/g')
			local mssn=$(cat "$output_file" | grep -o '"mssn":[0-9]*' | sed 's/"mssn"://' | head -1)
			
			[ "$rstval" = "404" ] && return 1
			
			if [ "$rstval" = "200" ]; then
				if [ -n "$script_body" ] && [ "$script_body" != "null" ]; then
					echo "$script_body" > "$output_file"
					dos2unix "$output_file" 2>/dev/null
					return 0
				elif [ -n "$mssn" ] && [ "$mssn" != "null" ] && [ "$mssn" != "0" ]; then
					get_script_by_mssn "$mssn" "$output_file"
					return $?
				fi
			fi
			return 1
		else
			dos2unix "$output_file" 2>/dev/null
			return 0
		fi
	fi
	return 1
}

# Function: Process gateway servers
# ============================================================================
# Server Processing Sub-Functions (Refactored from process_gateway_servers)
# ============================================================================

# ============================================================================
# Server Processing - Self-Contained Functions
# Each function is INDEPENDENT and returns results, no global variable magic
# ============================================================================

# Function: Parse server JSON and return extracted values
# Returns: JSON string with all server parameters
# Usage: server_params=$(extract_server_params "$server_json")
extract_server_params() {
	local server_json="$1"
	local hostname ssh_user ssh_host ssh_port ssh_key_path ssh_password os_info enabled lssn
	
	if command -v jq &> /dev/null; then
		# jq method
		hostname=$(echo "$server_json" | jq -r '.hostname // empty' 2>/dev/null)
		lssn=$(echo "$server_json" | jq -r '.lssn // empty' 2>/dev/null)
		ssh_host=$(echo "$server_json" | jq -r '.ssh_host // empty' 2>/dev/null)
		ssh_user=$(echo "$server_json" | jq -r '.ssh_user // empty' 2>/dev/null)
		ssh_port=$(echo "$server_json" | jq -r '.ssh_port // empty' 2>/dev/null)
		ssh_key_path=$(echo "$server_json" | jq -r '.ssh_key_path // empty' 2>/dev/null)
		ssh_password=$(echo "$server_json" | jq -r '.ssh_password // empty' 2>/dev/null)
		os_info=$(echo "$server_json" | jq -r '.os_info // empty' 2>/dev/null)
		enabled=$(echo "$server_json" | jq -r '.enabled // 1' 2>/dev/null)
	else
		# grep fallback
		hostname=$(echo "$server_json" | grep -o '"hostname"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		lssn=$(echo "$server_json" | grep -o '"lssn"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
		ssh_host=$(echo "$server_json" | grep -o '"ssh_host"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		ssh_user=$(echo "$server_json" | grep -o '"ssh_user"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		ssh_port=$(echo "$server_json" | grep -o '"ssh_port"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
		ssh_key_path=$(echo "$server_json" | grep -o '"ssh_key_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		ssh_password=$(echo "$server_json" | grep -o '"ssh_password"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		os_info=$(echo "$server_json" | grep -o '"os_info"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		enabled=$(echo "$server_json" | grep -o '"enabled"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
	fi
	
	# Return as JSON string
	echo "{\"hostname\":\"${hostname}\",\"lssn\":\"${lssn}\",\"ssh_host\":\"${ssh_host}\",\"ssh_user\":\"${ssh_user}\",\"ssh_port\":${ssh_port:-22},\"ssh_key_path\":\"${ssh_key_path}\",\"ssh_password\":\"${ssh_password}\",\"os_info\":\"${os_info:-Linux}\",\"enabled\":${enabled:-1}}"
}

# Function: Validate server parameters
# Returns: 0 if valid, 1 if should skip
# Usage: if validate_server_params "$server_params"; then...
validate_server_params() {
	local server_params="$1"
	
	# Check if hostname is empty
	local hostname=$(echo "$server_params" | jq -r '.hostname // empty' 2>/dev/null)
	if [ -z "$hostname" ]; then
		# Fallback: try grep
		hostname=$(echo "$server_params" | grep -o '"hostname"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
	fi
	
	local enabled=$(echo "$server_params" | jq -r '.enabled // 1' 2>/dev/null)
	if [ -z "$enabled" ] || [ "$enabled" = "null" ]; then
		# Fallback: try grep
		enabled=$(echo "$server_params" | grep -o '"enabled"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
		[ -z "$enabled" ] && enabled=1
	fi
	
	[[ -z "$hostname" ]] && return 1
	[[ "$enabled" == "0" ]] && return 1
	return 0
}

# Function: Process single server - all-in-one handler
# Returns: 0 on success, 1 on failure
# Usage: process_single_server "$server_json" "$tmpdir"
process_single_server() {
	local server_json="$1"
	local tmpdir="$2"
	local global_lssn="${lssn}"  # Capture global lssn for logging
	
	# Skip empty objects
	[[ -z "$server_json" || "$server_json" == "{}" ]] && return 0
	
	# Step 1: Extract parameters (returns JSON)
	local server_params=$(extract_server_params "$server_json")
	
	# Debug: Check if server_params is empty
	if [ -z "$server_params" ]; then
		gateway_log "❌" "[5.5.1-DEBUG]" "extract_server_params returned empty"
		return 0
	fi
	
	# Step 2: Validate parameters
	if ! validate_server_params "$server_params"; then
		gateway_log "⚠️ " "[5.5.2-SKIPPED]" "Server skipped (disabled or invalid)"
		return 0
	fi
	
	# Step 3: Extract individual values from params JSON
	local hostname=$(echo "$server_params" | jq -r '.hostname' 2>/dev/null)
	local server_lssn=$(echo "$server_params" | jq -r '.lssn' 2>/dev/null)
	local ssh_host=$(echo "$server_params" | jq -r '.ssh_host' 2>/dev/null)
	local ssh_user=$(echo "$server_params" | jq -r '.ssh_user' 2>/dev/null)
	local ssh_port=$(echo "$server_params" | jq -r '.ssh_port' 2>/dev/null)
	local ssh_key_path=$(echo "$server_params" | jq -r '.ssh_key_path' 2>/dev/null)
	local ssh_password=$(echo "$server_params" | jq -r '.ssh_password' 2>/dev/null)
	local os_info=$(echo "$server_params" | jq -r '.os_info' 2>/dev/null)
	
	# Log: Server parsing complete
	gateway_log "🟢" "[5.6]" "Server parsed: hostname=${hostname}, lssn=${server_lssn}"
	
	local logdt=$(date '+%Y%m%d%H%M%S')
	echo "[${logdt}] [Gateway] Processing: $hostname (LSSN:$server_lssn)" >> $LogFileName
	
	# Log remote execution started
	if type log_remote_execution >/dev/null 2>&1; then
		log_remote_execution "started" "$hostname" "$server_lssn" "$ssh_host" "$ssh_port" "unknown"
	fi
	
	# Step 4: Get remote queue
	local tmpfile="${tmpdir}/script_${server_lssn}.sh"
	get_remote_queue "$server_lssn" "$hostname" "$os_info" "$tmpfile"
	
	local ssh_result=1
	if [ -s "$tmpfile" ]; then
		# Check for errors
		local err_check=$(cat "$tmpfile" | grep "HTTP Error")
		if [ -n "$err_check" ]; then
			gateway_log "❌" "[5.8-ERROR]" "Queue fetch failed: ${err_check}"
			if type log_remote_execution >/dev/null 2>&1; then
				log_remote_execution "failed" "$hostname" "$server_lssn" "$ssh_host" "$ssh_port" "false" "Queue fetch error"
			fi
		else
			gateway_log "🟢" "[5.8]" "Queue fetched successfully"
			
			# Step 5: Execute SSH
			gateway_log "🟢" "[5.9]" "SSH attempt to ${ssh_host}:${ssh_port}"
			execute_remote_command "$ssh_host" "$ssh_user" "$ssh_port" "$ssh_key_path" "$ssh_password" "$tmpfile" "$server_lssn" "$hostname" >> $LogFileName
			ssh_result=$?
			
			# Log result
			if [ $ssh_result -eq 0 ]; then
				gateway_log "🟢" "[5.10]" "SSH success"
				if type log_remote_execution >/dev/null 2>&1; then
					log_remote_execution "success" "$hostname" "$server_lssn" "$ssh_host" "$ssh_port" "true"
				fi
			else
				gateway_log "❌" "[5.10]" "SSH failed: code=${ssh_result}"
				if type log_remote_execution >/dev/null 2>&1; then
					log_remote_execution "failed" "$hostname" "$server_lssn" "$ssh_host" "$ssh_port" "true" "SSH failed"
				fi
			fi
		fi
	else
		gateway_log "🟢" "[5.11]" "No queue (empty)"
		if type log_remote_execution >/dev/null 2>&1; then
			log_remote_execution "success" "$hostname" "$server_lssn" "$ssh_host" "$ssh_port" "false"
		fi
	fi
	
	rm -f "$tmpfile"
	
	# Step 6: Call RemoteServerSSHTest API (only if SSH succeeded)
	if [ $ssh_result -eq 0 ]; then
		gateway_log "🟢" "[5.10.1]" "RemoteServerSSHTest API call"
		if type report_ssh_test_result >/dev/null 2>&1; then
			report_ssh_test_result "$server_lssn" "$global_lssn"
			if [ $? -eq 0 ]; then
				gateway_log "🟢" "[5.10.2]" "API success"
			else
				gateway_log "❌" "[5.10.3]" "API failed"
			fi
		else
			gateway_log "❌" "[5.10.4]" "API module missing"
		fi
	fi
	
	return 0
}

# Function: Process server list from file
# Usage: process_server_list "server_list_file" "tmpdir"
process_server_list() {
	local server_list_file="$1"
	local tmpdir="$2"
	local server_count=0
	local temp_servers_file="${tmpdir}/servers_to_process.jsonl"
	
	# 🔴 [로깅 포인트 #5.5-TEST] 서버 목록 파일 읽기 테스트
	if ! [ -s "$server_list_file" ]; then
		gateway_log "❌" "[5.5-TEST]" "서버 목록 파일이 비어있음"
		return 1
	fi
	
	# Choose parser method and create temp file
	if command -v jq &> /dev/null; then
		# 🔴 [로깅 포인트 #5.5-JQ-USED] jq 사용
		gateway_log "🟢" "[5.5-JQ-USED]" "jq로 JSON 파싱 시작"
		jq -r '.data[]? // .[]? // .' "$server_list_file" 2>/dev/null > "$temp_servers_file"
	else
		# 🔴 [로깅 포인트 #5.5-GREP-FALLBACK] grep fallback
		gateway_log "🟢" "[5.5-GREP-FALLBACK]" "grep fallback 사용"
		tr -d '\n' < "$server_list_file" | sed 's/}/}\n/g' | grep -o '{[^}]*}' > "$temp_servers_file"
	fi
	
	# Process each server from temp file (NOT in subshell)
	if [ -s "$temp_servers_file" ]; then
		while IFS= read -r server_json; do
			[ -z "$server_json" ] && continue
			process_single_server "$server_json" "$tmpdir"
			((server_count++))
		done < "$temp_servers_file"
	fi
	
	# Clean up temp file
	rm -f "$temp_servers_file"
	
	# Log result
	if [ $server_count -gt 0 ]; then
		gateway_log "🟢" "[5.5-PROCESSING]" "서버 처리 완료: count=${server_count}"
	else
		gateway_log "⚠️ " "[5.5-NO-SERVERS]" "처리할 서버 없음"
	fi
}

# ============================================================================
# Main Gateway Server Processing Function
# ============================================================================

process_gateway_servers() {
	local tmpdir="/tmp/giipAgent_gateway_$$"
	mkdir -p "$tmpdir"
	
	# Get servers from DB (real-time query, no cache)
	local server_list_file=$(get_gateway_servers)
	if [ $? -ne 0 ] || [ ! -f "$server_list_file" ]; then
		# 🔴 [로깅 포인트 #5.5-ERROR] 서버 목록 파일 확인 실패
		gateway_log "❌" "[5.5-ERROR]" "서버 목록 파일 확인 실패"
		rm -rf "$tmpdir"
		return 1
	fi
	
	# 🔴 [로깅 포인트 #5.5] 서버 목록 파일 확인 성공
	gateway_log "🟢" "[5.5]" "서버 목록 파일 확인 성공" "\"file_size\":$(wc -c < \"$server_list_file\")"
	
	local logdt=$(date '+%Y%m%d%H%M%S')
	echo "[${logdt}] [Gateway] Starting server processing cycle..." >> $LogFileName
	
	# 🔴 [로깅 포인트 #5.5-JSON-DEBUG] 서버 목록 파일 내용 확인
	gateway_log "🟢" "[5.5-JSON-DEBUG]" "파일 내용 확인"
	
	# Process servers from list
	process_server_list "$server_list_file" "$tmpdir"
	
	# Clean up
	rm -f "$server_list_file"
	rm -rf "$tmpdir"
	
	# 🔴 [로깅 포인트 #5.12] Gateway 사이클 완료
	gateway_log "🟢" "[5.12]" "Gateway 사이클 완료"
	
	logdt=$(date '+%Y%m%d%H%M%S')
	echo "[${logdt}] [Gateway] Cycle completed" >> $LogFileName
	
	# 🔴 [로깅 포인트 #5.13] 실행 로그 저장
	if type save_execution_log >/dev/null 2>&1; then
		local cycle_status="{\"status\":\"completed\",\"cycle_timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"lssn\":${lssn}}"
		save_execution_log "gateway_cycle_end" "$cycle_status"
		gateway_log "🟢" "[5.13]" "실행 로그 저장 완료" "\"status\":\"success\""
	fi
}

# ============================================================================
# Managed Database Check Functions
# ============================================================================

# Load managed database check module (separate file for maintainability)
# This module handles tManagedDatabase health checks and last_check_dt updates
SCRIPT_DIR_GATEWAY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ -f "${SCRIPT_DIR_GATEWAY}/check_managed_databases.sh" ]; then
	. "${SCRIPT_DIR_GATEWAY}/check_managed_databases.sh"
else
	echo "⚠️  Warning: check_managed_databases.sh not found" >&2
	# Provide stub function to prevent errors
	check_managed_databases() {
		echo "[Gateway] ⚠️  check_managed_databases module not loaded" >&2
		return 1
	}
fi

# ============================================================================
# Export Functions
# ============================================================================

export -f gateway_log
export -f get_gateway_servers
export -f get_db_queries
export -f get_managed_databases
export -f execute_remote_command
export -f get_script_by_mssn
export -f get_remote_queue
export -f extract_server_params
export -f validate_server_params
export -f process_single_server
export -f process_server_list
export -f process_gateway_servers
export -f check_managed_databases
