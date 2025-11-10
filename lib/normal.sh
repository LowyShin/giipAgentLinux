#!/bin/bash
# giipAgent Normal Mode Library
# Version: 2.00
# Date: 2025-01-10
# Purpose: Normal mode functions for local agent queue processing
# Rule: Follow giipapi_rules.md - text contains parameter names only, jsondata contains actual values

# ============================================================================
# Queue Fetching Functions
# ============================================================================

# Function: Fetch queue from API
# Usage: fetch_queue "lssn" "hostname" "os" "output_file"
fetch_queue() {
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
		--no-check-certificate -q
	
	return $?
}

# ============================================================================
# JSON Response Parsing Functions
# ============================================================================

# Function: Parse JSON response and extract script
# Returns: 0 if script available, 1 if no queue (404), 2 if error
parse_json_response() {
	local response_file=$1
	local output_file=$2
	
	# Check if file exists and has content
	if [ ! -s "$response_file" ]; then
		echo "[Normal] Empty response"
		return 1
	fi
	
	# Check if response is JSON
	local is_json=$(head -c 10 "$response_file" | grep -E '^\s*\{')
	
	if [ -n "$is_json" ]; then
		# Check for error in JSON
		if grep -q '"error"' "$response_file"; then
			local error_msg=$(cat "$response_file")
			echo "[Normal] ❌ API Error Response:"
			echo "$error_msg"
			
			# Save error to KVS
			local error_details="{\"error_type\":\"api_error\",\"error_message\":\"API returned error\",\"error_code\":1,\"context\":\"queue_fetch\"}"
			save_execution_log "error" "$error_details" 2>/dev/null
			
			return 2
		fi
		
		# Extract fields from JSON
		local rstval=$(cat "$response_file" | grep -o '"RstVal"\s*:\s*"[^"]*"' | sed 's/"RstVal"\s*:\s*"//; s/"$//' | head -1)
		local script_body=$(cat "$response_file" | grep -o '"ms_body"\s*:\s*"[^"]*"' | sed 's/"ms_body"\s*:\s*"//; s/"$//' | sed 's/\\n/\n/g')
		local mssn=$(cat "$response_file" | grep -o '"mssn"\s*:\s*[0-9]*' | sed 's/"mssn"\s*:\s*//' | head -1)
		
		if [ "$rstval" = "404" ]; then
			echo "[Normal] No queue (404)"
			
			# Save queue check to KVS
			local queue_check_details="{\"api_response\":\"404\",\"has_queue\":false,\"mssn\":0,\"script_source\":\"none\"}"
			save_execution_log "queue_check" "$queue_check_details" 2>/dev/null
			
			return 1
		elif [ "$rstval" = "200" ]; then
			if [ -n "$script_body" ] && [ "$script_body" != "null" ]; then
				# ms_body is available
				echo "$script_body" > "$output_file"
				echo "[Normal] Queue received (ms_body)"
				
				# Save queue check to KVS
				local queue_check_details="{\"api_response\":\"200\",\"has_queue\":true,\"mssn\":${mssn:-0},\"script_source\":\"ms_body\"}"
				save_execution_log "queue_check" "$queue_check_details" 2>/dev/null
				
				return 0
			elif [ -n "$mssn" ] && [ "$mssn" != "null" ] && [ "$mssn" != "0" ]; then
				# Fetch from repository
				echo "[Normal] Fetching from repository (mssn=$mssn)"
				
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
					echo "[Normal] Queue received (repository)"
					
					# Save queue check to KVS
					local queue_check_details="{\"api_response\":\"200\",\"has_queue\":true,\"mssn\":${mssn},\"script_source\":\"repository\"}"
					save_execution_log "queue_check" "$queue_check_details" 2>/dev/null
					
					return 0
				else
					echo "[Normal] ❌ Failed to fetch from repository"
					return 2
				fi
			else
				echo "[Normal] ⚠️  No script available"
				return 1
			fi
		else
			echo "[Normal] ⚠️  API error: RstVal=$rstval"
			
			# Save error to KVS
			local error_details="{\"error_type\":\"api_error\",\"error_message\":\"Unexpected API response\",\"error_code\":${rstval:-0},\"context\":\"queue_check\"}"
			save_execution_log "error" "$error_details" 2>/dev/null
			
			return 2
		fi
	else
		# Not JSON, assume it's raw script (backward compatibility)
		echo "[Normal] Non-JSON response, treating as raw script"
		cp "$response_file" "$output_file"
		return 0
	fi
}

# ============================================================================
# Script Execution Functions
# ============================================================================

# Function: Execute script file
# Usage: execute_script "script_file"
execute_script() {
	local script_file=$1
	
	if [ ! -s "$script_file" ]; then
		echo "[Normal] Empty script file"
		return 1
	fi
	
	# Check for HTTP errors in script
	local err_check=$(cat "$script_file" | grep "HTTP Error")
	if [ -n "$err_check" ]; then
		echo "[Normal] ❌ HTTP Error in script"
		
		# Save error to KVS
		local error_details="{\"error_type\":\"script_error\",\"error_message\":\"HTTP Error in script\",\"error_code\":1,\"context\":\"script_execution\"}"
		save_execution_log "error" "$error_details" 2>/dev/null
		
		return 1
	fi
	
	# Convert DOS line endings
	dos2unix "$script_file" 2>/dev/null
	
	# Check if it's an expect script
	local n=$(cat "$script_file" | grep 'expect=' | wc -l)
	
	local script_start_time=$(date +%s)
	local script_exit_code=0
	
	if [ ${n} -ge 1 ]; then
		# Execute expect script
		expect "$script_file" >> "$LogFileName" 2>&1
		script_exit_code=$?
		echo "[Normal] Executed expect script (exit_code=${script_exit_code})"
	else
		# Execute bash script
		sh "$script_file" >> "$LogFileName" 2>&1
		script_exit_code=$?
		echo "[Normal] Executed bash script (exit_code=${script_exit_code})"
	fi
	
	local script_end_time=$(date +%s)
	local script_duration=$((script_end_time - script_start_time))
	
	# Save script execution to KVS
	local script_type="bash"
	[ ${n} -ge 1 ] && script_type="expect"
	
	local exec_details="{\"script_type\":\"${script_type}\",\"exit_code\":${script_exit_code},\"execution_time_seconds\":${script_duration}}"
	save_execution_log "script_execution" "$exec_details" 2>/dev/null
	
	return $script_exit_code
}

# ============================================================================
# Main Normal Mode Function
# ============================================================================

# Function: Run normal mode (single execution)
run_normal_mode() {
	local lssn=$1
	local hostname=$2
	local os=$3
	
	log_message "INFO" "Starting GIIP Agent V2.0 in NORMAL MODE"
	log_message "INFO" "Version: ${sv}, LSSN: ${lssn}, Hostname: ${hostname}"
	
	# Save startup to KVS
	local startup_details="{\"pid\":$$,\"config_file\":\"giipAgent.cnf\",\"api_endpoint\":\"${apiaddrv2}\"}"
	save_execution_log "startup" "$startup_details"
	
	# Temporary files
	local tmpFileName="giipTmpScript.sh"
	local response_file="/tmp/giipAgent_response_$$.json"
	
	# Fetch queue
	echo "[Normal] Fetching queue from API..."
	fetch_queue "$lssn" "$hostname" "$os" "$response_file"
	
	# Parse response
	parse_json_response "$response_file" "$tmpFileName"
	local parse_result=$?
	
	rm -f "$response_file"
	
	if [ $parse_result -eq 0 ]; then
		# Script available, execute it
		execute_script "$tmpFileName"
		rm -f "$tmpFileName"
	elif [ $parse_result -eq 1 ]; then
		# No queue (404)
		log_message "INFO" "No queue available"
	else
		# Error
		log_message "ERROR" "Failed to fetch queue"
	fi
	
	# Save shutdown to KVS
	local shutdown_details="{\"reason\":\"normal\",\"process_count\":1,\"uptime_seconds\":0}"
	save_execution_log "shutdown" "$shutdown_details"
	
	log_message "INFO" "Normal mode execution completed"
	
	return 0
}

# ============================================================================
# Export Functions
# ============================================================================

export -f fetch_queue
export -f parse_json_response
export -f execute_script
export -f run_normal_mode
