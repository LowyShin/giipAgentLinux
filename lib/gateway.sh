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

# Load normal mode queue fetching module (for Gateway self-queue processing via CQEQueueGet API)
if [ -f "${SCRIPT_DIR_GATEWAY_SSH}/normal.sh" ]; then
	. "${SCRIPT_DIR_GATEWAY_SSH}/normal.sh"
else
	# Provide stub function if normal.sh not available
	fetch_queue() {
		echo "[gateway.sh] ⚠️  WARNING: fetch_queue stub called (normal.sh not loaded)" >&2
		return 1
	}
fi

# Function: Log gateway operation to both stderr AND tKVS
# Usage: gateway_log "🟢" "[5.4]" "Gateway 서버 목록 조회 시작" "additional_json_data"
# Function: Gateway Operation Logging
# Purpose: Log to both stderr (console) and tKVS with point tracking
# Usage: gateway_log "emoji" "point_code" "message" "optional_json_fragment"
# Example: gateway_log "🟢" "[5.6]" "Server processed" ""
#
# ⚠️ IMPORTANT: 
# - This function calls kvs_put() which follows giipapi_rules.md
# - The 4th parameter (optional_json_fragment) is appended as-is to JSON
# - It should contain proper JSON fragments ONLY
# - NO string escaping or variable substitution in this function
# - If you need to log variable data, do it OUTSIDE this function as a separate kvs_put call
gateway_log() {
	local emoji="$1"
	local point="$2"
	local message="$3"
	local extra_json="${4:-}"
	
	# Log to stderr (for console visibility and LogFileName)
	echo "[gateway.sh] ${emoji} ${point} ${message}: lssn=${lssn:-unknown}" >&2
	
	# Log to tKVS - point only (timestamp will be set by DB with getdate())
	# Use pure JSON object as per kvs.sh requirements
	local json_payload="{\"event_type\":\"gateway_operation\",\"point\":\"${point}\"}"
	
	# Only append extra_json if provided (it must be valid JSON fragment)
	if [ -n "$extra_json" ]; then
		json_payload="${json_payload%}},${extra_json}}"
	fi
	
	# Call kvs_put with proper JSON object (NOT escaped string)
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
		gateway_log "❌" "[5.4-ERROR]" "Gateway 서버 목록 API 에러"
		rm -f "$temp_file"
		return 1
	fi
	
	# 🔴 [로깅 포인트 #5.4-SUCCESS] 서버 목록 조회 성공
	local server_count=$(cat "$temp_file" | grep -o '{[^}]*}' | wc -l)
	gateway_log "🟢" "[5.4-SUCCESS]" "Gateway 서버 목록 조회 성공"
	
	# 🔴 DEBUG: 다음 함수 호출 확인
	gateway_log "🔵" "[5.4-RETURN]" "server_list_file 반환: $temp_file"
	
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
# Note: 'enabled' field is no longer parsed or checked
extract_server_params() {
	local server_json="$1"
	local hostname ssh_user ssh_host ssh_port ssh_key_path ssh_password os_info lssn
	
	# 🔴 DEBUG: 입력 JSON 확인
	gateway_log "🔵" "[5.4.9-INPUT]" "extract_server_params input: $(echo -n "$server_json" | head -c 100)..."
	
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
	fi
	
	# Return as JSON string (without enabled field)
	echo "{\"hostname\":\"${hostname}\",\"lssn\":\"${lssn}\",\"ssh_host\":\"${ssh_host}\",\"ssh_user\":\"${ssh_user}\",\"ssh_port\":${ssh_port:-22},\"ssh_key_path\":\"${ssh_key_path}\",\"ssh_password\":\"${ssh_password}\",\"os_info\":\"${os_info:-Linux}\"}"
}

# Function: Validate server parameters
# Returns: 0 if valid, 1 if should skip
# Usage: if validate_server_params "$server_params"; then...
# Note: No longer checks 'enabled' field - all servers are processed regardless of enabled status
validate_server_params() {
	local server_params="$1"
	
	# Check if hostname is empty
	local hostname=$(echo "$server_params" | jq -r '.hostname // empty' 2>/dev/null)
	if [ -z "$hostname" ]; then
		# Fallback: try grep
		hostname=$(echo "$server_params" | grep -o '"hostname"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
	fi
	
	[[ -z "$hostname" ]] && return 1
	return 0
}

# Function: Process single server - all-in-one handler
# Returns: 0 on success, 1 on failure
# Usage: process_single_server "$server_json" "$tmpdir"
process_single_server() {
	local server_json="$1"
	local tmpdir="$2"
	local global_lssn="${lssn}"  # Capture global lssn for logging
	
	# 🔴 DEBUG: 함수 진입 확인
	gateway_log "🔵" "[5.5.0-ENTRY]" "process_single_server 호출됨"
	
	# Skip empty objects
	[[ -z "$server_json" || "$server_json" == "{}" ]] && return 0
	
	# Step 1: Extract parameters (returns JSON)
	local server_params=$(extract_server_params "$server_json")
	
	# 🔴 DEBUG: extract_server_params 반환값 확인
	gateway_log "🔵" "[5.5.1-EXTRACT]" "extract_server_params 완료: length=$(echo -n "$server_params" | wc -c)"
	
	# Debug: Check if server_params is empty
	if [ -z "$server_params" ]; then
		gateway_log "❌" "[5.5.1-DEBUG]" "extract_server_params returned empty"
		return 0
	fi
	
	# 🆕 Step 1.5: Log extracted parameters to tKVS BEFORE validation
	# Purpose: Record all extracted parameters for debugging validation failures
	local extract_log_params="{\"action\":\"server_params_extracted\",\"server_params\":${server_params}}"
	if type kvs_put >/dev/null 2>&1; then
		kvs_put "lssn" "${global_lssn:-0}" "gateway_server_extract" "$extract_log_params" 2>/dev/null
		gateway_log "🟢" "[5.5.1.5]" "Extracted params logged to tKVS"
	fi
	
	# Step 2: Validate parameters
	gateway_log "🔵" "[5.5.2-VALIDATE]" "validate_server_params 시작"
	if ! validate_server_params "$server_params"; then
		# 🔴 DEBUG: 왜 validate 실패했는지 상세 로그
		local hostname=$(echo "$server_params" | jq -r '.hostname // empty' 2>/dev/null)
		gateway_log "⚠️ " "[5.5.2-DEBUG-FAIL]" "validate 실패: hostname='$hostname', server_params='$server_params'"
		
		# 🆕 Log validation failure to tKVS
		local validate_fail_log="{\"action\":\"validation_failed\",\"hostname\":\"${hostname}\",\"server_params\":${server_params}}"
		if type kvs_put >/dev/null 2>&1; then
			kvs_put "lssn" "${global_lssn:-0}" "gateway_validation_failure" "$validate_fail_log" 2>/dev/null
		fi
		
		gateway_log "⚠️ " "[5.5.2-SKIPPED]" "Server skipped (validation failed)"
		return 0
	fi
	gateway_log "🔵" "[5.5.2-VALID]" "validate_server_params 통과"
	
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
			
			# 🆕 Step 4.5: Log SSH connection attempt parameters BEFORE connecting
			# Purpose: Record all connection parameters for debugging if connection fails
			local ssh_attempt_params="{\"action\":\"ssh_attempt_before_connect\",\"hostname\":\"${hostname}\",\"lssn\":${server_lssn},\"ssh_host\":\"${ssh_host}\",\"ssh_port\":${ssh_port},\"ssh_user\":\"${ssh_user}\",\"ssh_key_path\":\"${ssh_key_path}\",\"has_password\":$([ -n \"$ssh_password\" ] && echo 'true' || echo 'false')}"
			
			gateway_log "🔵" "[5.8.5]" "SSH 접속 시도 파라미터 저장 시작"
			if type kvs_put >/dev/null 2>&1; then
				kvs_put "lssn" "${lssn:-0}" "ssh_connection_attempt" "$ssh_attempt_params" 2>/dev/null
				gateway_log "🟢" "[5.8.5]" "SSH 접속 파라미터 tKVS 저장 완료"
			else
				gateway_log "⚠️ " "[5.8.5]" "kvs_put not available, skipping KVS logging"
			fi
			
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
		# 올바른 jq 쿼리: complete objects만 추출
		jq -c '.data[]? // .[]? // .' "$server_list_file" 2>/dev/null > "$temp_servers_file"
	else
		# 🔴 [로깅 포인트 #5.5-GREP-FALLBACK] grep fallback
		gateway_log "🟢" "[5.5-GREP-FALLBACK]" "grep fallback 사용"
		tr -d '\n' < "$server_list_file" | sed 's/}/}\n/g' | grep -o '{[^}]*}' > "$temp_servers_file"
	fi
	
	# 🔴 DEBUG: temp_servers_file 내용 확인
	local parsed_lines=$(wc -l < "$temp_servers_file")
	gateway_log "🔵" "[5.5-PARSED-COUNT]" "파싱된 라인 수: $parsed_lines"
	gateway_log "🔵" "[5.5-PARSED-FIRST]" "첫 번째 라인: $(head -1 "$temp_servers_file")"
	
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
	
	# 🔴 DEBUG: 함수 진입 확인
	gateway_log "🔵" "[5.4.5-PROCESS_ENTRY]" "process_gateway_servers 호출됨"
	
	# [5.3.1] 🟢 Gateway 자신의 큐 처리 (CQEQueueGet API 호출 → LSChkdt 자동 업데이트)
	gateway_log "🟢" "[5.3.1]" "Gateway 자신의 큐 조회 시작"
	local gateway_queue_file="/tmp/gateway_self_queue_$$.sh"
	
	if type fetch_queue >/dev/null 2>&1; then
		fetch_queue "$lssn" "$hn" "$os" "$gateway_queue_file"
		if [ -s "$gateway_queue_file" ]; then
			gateway_log "🟢" "[5.3.1-EXECUTE]" "Gateway 자신의 큐 존재, 스크립트 실행"
			bash "$gateway_queue_file"
			local script_result=$?
			gateway_log "🟢" "[5.3.1-COMPLETED]" "Gateway 자신의 큐 실행 완료" "\"result\":${script_result}"
		else
			gateway_log "🟢" "[5.3.1-EMPTY]" "Gateway 자신의 큐 없음 (404)"
		fi
		rm -f "$gateway_queue_file"
	else
		gateway_log "⚠️ " "[5.3.1-WARN]" "fetch_queue 함수 미로드"
	fi
	
	# Get servers from DB (real-time query, no cache)
	local server_list_file=$(get_gateway_servers)
	if [ $? -ne 0 ] || [ ! -f "$server_list_file" ]; then
		# 🔴 [로깅 포인트 #5.5-ERROR] 서버 목록 파일 확인 실패
		gateway_log "❌" "[5.5-ERROR]" "서버 목록 파일 확인 실패"
		rm -rf "$tmpdir"
		return 1
	fi
	
	# 🔴 DEBUG: server_list_file 수신 확인
	gateway_log "🔵" "[5.4.6-FILE_RECEIVED]" "server_list_file 수신: $server_list_file (size=$(wc -c < \"$server_list_file\"))"
	
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
		local cycle_status="{\"status\":\"completed\",\"lssn\":${lssn}}"
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
