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
	echo "[gateway.sh] 🟢 [5.4] Gateway 서버 목록 조회 시작: lssn=${lssn}, api_url=${api_url}, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
	
	local text="GatewayRemoteServerListForAgent lssn"
	local jsondata="{\"lssn\":${lssn}}"
	
	wget -O "$temp_file" \
		--post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"$api_url" \
		--no-check-certificate -q 2>&1
	
	if [ ! -s "$temp_file" ]; then
		# 🔴 [로깅 포인트 #5.4-ERROR] 서버 목록 조회 실패
		echo "[gateway.sh] ❌ [5.4-ERROR] Gateway 서버 목록 조회 실패: file_empty=true, lssn=${lssn}, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
		rm -f "$temp_file"
		return 1
	fi
	
	# Check for error response
	local err_check=$(cat "$temp_file" | grep -i "rstval.*40[0-9]")
	if [ -n "$err_check" ]; then
		# 🔴 [로깅 포인트 #5.4-ERROR] API 에러 응답
		echo "[gateway.sh] ❌ [5.4-ERROR] Gateway 서버 목록 API 에러: error_response=${err_check}, lssn=${lssn}, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
		rm -f "$temp_file"
		return 1
	fi
	
	# 🔴 [로깅 포인트 #5.4-SUCCESS] 서버 목록 조회 성공
	local server_count=$(cat "$temp_file" | grep -o '{[^}]*}' | wc -l)
	echo "[gateway.sh] 🟢 [5.4-SUCCESS] Gateway 서버 목록 조회 성공: server_count=${server_count}, file_size=$(wc -c < "$temp_file"), timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
	
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
process_gateway_servers() {
	local tmpdir="/tmp/giipAgent_gateway_$$"
	mkdir -p "$tmpdir"
	
	# Get servers from DB (real-time query, no cache)
	local server_list_file=$(get_gateway_servers)
	if [ $? -ne 0 ] || [ ! -f "$server_list_file" ]; then
		# 🔴 [로깅 포인트 #5.5-ERROR] 서버 목록 파일 확인 실패
		echo "[gateway.sh] ❌ [5.5-ERROR] 서버 목록 파일 확인 실패: lssn=${lssn}, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
		rm -rf "$tmpdir"
		return 1
	fi
	
	# 🔴 [로깅 포인트 #5.5] 서버 목록 파일 확인 성공
	echo "[gateway.sh] 🟢 [5.5] 서버 목록 파일 확인 성공: file_size=$(wc -c < "$server_list_file"), lssn=${lssn}, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
	
	local logdt=$(date '+%Y%m%d%H%M%S')
	echo "[${logdt}] [Gateway] Starting server processing cycle..." >> $LogFileName
	
	# 🔴 [로깅 포인트 #5.5-JSON-DEBUG] 서버 목록 파일 내용 확인
	echo "[gateway.sh] 🟢 [5.5-JSON-DEBUG] 파일 내용 (첫 200자): $(head -c 200 "$server_list_file"), timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
	
	# 🔴 [로깅 포인트 #5.5-GREP-TEST] grep 정규식 테스트
	local grep_result=$(cat "$server_list_file" | grep -o '{[^}]*}')
	local grep_count=$(echo "$grep_result" | grep -c '^')
	echo "[gateway.sh] 🟢 [5.5-GREP-TEST] grep -o '{[^}]*}' 결과: ${grep_count}개 매칭 (파일 크기: $(wc -c < "$server_list_file")B), timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
	
	# 🔴 [로깅 포인트 #5.5-GREP-WARN] 만약 grep이 0개면 경고
	if [ "$grep_count" -eq 0 ]; then
		echo "[gateway.sh] ⚠️  [5.5-GREP-WARN] grep 0개 매칭 발생 - JSON이 multiline 형식일 가능성! (파일 내용: $(cat "$server_list_file" | head -c 100)...), timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
	fi
	
	# Parse JSON and process each server
	# Fix: Use jq for robust JSON parsing instead of grep (handles multiline JSON)
	# Fallback: Use grep if jq not available
	if command -v jq &> /dev/null; then
		# 🔴 [로깅 포인트 #5.5-JQ-USED] jq 사용 로깅
		echo "[gateway.sh] 🟢 [5.5-JQ-USED] jq로 JSON 파싱 시작, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
		
		# ✅ jq 사용 (권장)
		jq -r '.data[]? // .[]? // .' "$server_list_file" 2>/dev/null | while read -r server_json; do
			[[ -z "$server_json" || "$server_json" == "{}" ]] && continue
			
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
		# 🔴 [로깅 포인트 #5.5-GREP-FALLBACK] grep fallback 사용 로깅
		echo "[gateway.sh] 🟢 [5.5-GREP-FALLBACK] jq 없음 - grep fallback 사용 (tr -d '\n' + sed), timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
		
		# ✅ Fallback: grep (jq 없을 때)
		# 먼저 JSON을 한 줄로 정규화
		tr -d '\n' < "$server_list_file" | sed 's/}/}\n/g' | grep -o '{[^}]*}' | while read -r server_json; do
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
		
		# Skip disabled servers
		[[ -z $hostname ]] && continue
		[[ $enabled == "0" ]] && continue
		
		# 🔴 [로깅 포인트 #5.6] 서버 JSON 파싱 완료
		echo "[gateway.sh] 🟢 [5.6] 서버 JSON 파싱 완료: hostname=${hostname}, lssn=${lssn}, ssh_host=${ssh_host}, ssh_port=${ssh_port}, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
		
		# Set defaults
		[ -z "$ssh_port" ] && ssh_port="22"
		[ -z "$ssh_user" ] && ssh_user="root"
		[ -z "$os_info" ] && os_info="Linux"
		
		logdt=$(date '+%Y%m%d%H%M%S')
		echo "[${logdt}] [Gateway] Processing: $hostname (LSSN:$lssn)" >> $LogFileName
		
		# 🔍 Log remote execution started
		if type log_remote_execution >/dev/null 2>&1; then
			log_remote_execution "started" "$hostname" "$lssn" "$ssh_host" "$ssh_port" "unknown"
		fi
		
		# 🔴 [로깅 포인트 #5.7] SSH 테스트 시작
		echo "[gateway.sh] 🟢 [5.7] SSH 테스트 시작: hostname=${hostname}, ssh_host=${ssh_host}, ssh_port=${ssh_port}, ssh_user=${ssh_user}, auth_method=$([ -n "${ssh_password}" ] && echo "password" || echo "key"), timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
		
		local tmpfile="${tmpdir}/script_${lssn}.sh"
		get_remote_queue "$lssn" "$hostname" "$os_info" "$tmpfile"
		
		local queue_available="false"
		if [ -s "$tmpfile" ]; then
			local err_check=$(cat "$tmpfile" | grep "HTTP Error")
			if [ -n "$err_check" ]; then
				# 🔴 [로깅 포인트 #5.8-ERROR] 큐 조회 실패
				echo "[gateway.sh] ❌ [5.8-ERROR] 큐 조회 실패: hostname=${hostname}, lssn=${lssn}, error=${err_check}, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
				
				# Log execution failed (queue error)
				if type log_remote_execution >/dev/null 2>&1; then
					log_remote_execution "failed" "$hostname" "$lssn" "$ssh_host" "$ssh_port" "false" "Queue fetch error: $err_check"
				fi
				rm -f "$tmpfile"
				continue
			fi
			
			# 🔴 [로깅 포인트 #5.8] 큐 조회 성공
			echo "[gateway.sh] 🟢 [5.8] 큐 조회 성공: hostname=${hostname}, lssn=${lssn}, script_size=$(wc -c < "$tmpfile"), timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
			
			queue_available="true"
			
			# 🔴 [로깅 포인트 #5.9] SSH 연결 시도
			echo "[gateway.sh] 🟢 [5.9] SSH 연결 시도: hostname=${hostname}, ssh_host=${ssh_host}:${ssh_port}, ssh_user=${ssh_user}, lssn=${lssn}, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
			
			execute_remote_command "$ssh_host" "$ssh_user" "$ssh_port" "$ssh_key_path" "$ssh_password" "$tmpfile" "$lssn" "$hostname" >> $LogFileName
			local exec_result=$?
			
			# Determine SSH test result and calculate duration
			local ssh_status="fail"
			local duration=0
			if [ $exec_result -eq 0 ]; then
				ssh_status="success"
			fi
			
			# 🔴 [로깅 포인트 #5.10] SSH 연결 결과
			if [ $exec_result -eq 0 ]; then
				echo "[gateway.sh] 🟢 [5.10] SSH 연결 성공: hostname=${hostname}, lssn=${lssn}, exit_code=${exec_result}, ssh_status=${ssh_status}, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
			else
				echo "[gateway.sh] ❌ [5.10-ERROR] SSH 연결 실패: hostname=${hostname}, lssn=${lssn}, exit_code=${exec_result}, ssh_status=${ssh_status}, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
			fi
			
			# Log execution result
			if type log_remote_execution >/dev/null 2>&1; then
				if [ $exec_result -eq 0 ]; then
					log_remote_execution "success" "$hostname" "$lssn" "$ssh_host" "$ssh_port" "true"
				else
					log_remote_execution "failed" "$hostname" "$lssn" "$ssh_host" "$ssh_port" "true" "SSH execution failed (exit code: $exec_result)"
				fi
			fi
			
			# 🔴 [로깅 포인트 #5.10.1] RemoteServerSSHTest API 호출 시작
			echo "[gateway.sh] 🟢 [5.10.1] RemoteServerSSHTest API 호출 시작: lssn=${lssn}, gateway_lssn=${lssn}, test_type=ssh, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
			
			# Call RemoteServerSSHTest API to update LSChkdt
			if type report_ssh_test_result >/dev/null 2>&1; then
				report_ssh_test_result "$lssn" "$lssn"
				local api_result=$?
				
				if [ $api_result -eq 0 ]; then
					# 🔴 [로깅 포인트 #5.10.2] RemoteServerSSHTest API 호출 성공
					echo "[gateway.sh] 🟢 [5.10.2] RemoteServerSSHTest API 호출 성공: lssn=${lssn}, gateway_lssn=${lssn}, rstval=200, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
				else
					# 🔴 [로깅 포인트 #5.10.3] RemoteServerSSHTest API 호출 실패 또는 응답 없음
					echo "[gateway.sh] ❌ [5.10.3] RemoteServerSSHTest API 호출 실패: lssn=${lssn}, gateway_lssn=${lssn}, api_result=${api_result}, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
				fi
			else
				# 🔴 [로깅 포인트 #5.10.4] RemoteServerSSHTest 모듈 로드 실패
				echo "[gateway.sh] ❌ [5.10.4] RemoteServerSSHTest 모듈 로드 실패: report_ssh_test_result function not found, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
			fi
			
			rm -f "$tmpfile"
		else
			# 🔴 [로깅 포인트 #5.11] 큐 없음 (정상)
			echo "[gateway.sh] 🟢 [5.11] 큐 없음 (정상): hostname=${hostname}, lssn=${lssn}, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
			
			# No queue available
			if type log_remote_execution >/dev/null 2>&1; then
				log_remote_execution "success" "$hostname" "$lssn" "$ssh_host" "$ssh_port" "false"
			fi
		fi
	done
	fi  # End of if command jq check
	
	# Clean up
	rm -f "$server_list_file"
	rm -rf "$tmpdir"
	
	# 🔴 [로깅 포인트 #5.12] Gateway 사이클 완료
	echo "[gateway.sh] 🟢 [5.12] Gateway 사이클 완료: lssn=${lssn}, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
	
	logdt=$(date '+%Y%m%d%H%M%S')
	echo "[${logdt}] [Gateway] Cycle completed" >> $LogFileName
	
	# 🔴 [로깅 포인트 #5.13] 실행 로그 저장
	if type save_execution_log >/dev/null 2>&1; then
		local cycle_status="{\"status\":\"completed\",\"cycle_timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"lssn\":${lssn}}"
		save_execution_log "gateway_cycle_end" "$cycle_status"
		echo "[gateway.sh] 🟢 [5.13] 실행 로그 저장 완료: status=success, lssn=${lssn}, timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')" >&2
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

export -f get_gateway_servers
export -f get_db_queries
export -f get_managed_databases
export -f execute_remote_command
export -f get_script_by_mssn
export -f get_remote_queue
export -f process_gateway_servers
export -f check_managed_databases
