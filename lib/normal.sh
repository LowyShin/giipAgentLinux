#!/bin/bash
# giipAgent Normal Mode Library
# Version: 2.00
# Date: 2025-01-10
# Purpose: Normal mode functions for local agent queue processing
# Rule: Follow giipapi_rules.md - text contains parameter names only, jsondata contains actual values

# ============================================================================
# Note: queue_get() is provided by lib/cqe.sh for CQEQueueGet API calls
# ============================================================================

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
		save_execution_log "error" "$error_details"
		
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
	save_execution_log "script_execution" "$exec_details"
	
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
	local startup_details="{\"pid\":$$,\"config_file\":\"giipAgent.cnf\",\"api_endpoint\":\"${apiaddrv2}\",\"is_gateway\":0,\"mode\":\"normal\",\"git_commit\":\"${GIT_COMMIT}\",\"file_modified\":\"${FILE_MODIFIED}\",\"script_path\":\"${BASH_SOURCE[1]}\"}"
	save_execution_log "startup" "$startup_details"
	
	# Temporary files
	local tmpFileName="giipTmpScript.sh"
	
	# Fetch queue using queue_get (from kvs.sh)
	echo "[Normal] Fetching queue from API..."
	queue_get "$lssn" "$hostname" "$os" "$tmpFileName"
	local fetch_result=$?
	
	# Handle fetch result
	if [ $fetch_result -eq 0 ]; then
		# Script available, execute it
		if [ -s "$tmpFileName" ]; then
			execute_script "$tmpFileName"
			rm -f "$tmpFileName"
		fi
	elif [ $fetch_result -eq 1 ]; then
		# No queue (404)
		log_message "INFO" "No queue available"
		
		# Save queue check to KVS
		local queue_check_details="{\"api_response\":\"404\",\"has_queue\":false,\"mssn\":0,\"script_source\":\"none\"}"
		save_execution_log "queue_check" "$queue_check_details"
	else
		# Error
		log_message "ERROR" "Failed to fetch queue"
		
		# Save error to KVS
		local error_details="{\"error_type\":\"api_error\",\"error_message\":\"Failed to fetch queue\",\"error_code\":${fetch_result},\"context\":\"queue_fetch\"}"
		save_execution_log "error" "$error_details"
	fi
	
	# Save shutdown to KVS
	local shutdown_details="{\"reason\":\"normal\",\"process_count\":1,\"uptime_seconds\":0,\"is_gateway\":0,\"mode\":\"normal\"}"
	save_execution_log "shutdown" "$shutdown_details"
	
	log_message "INFO" "Normal mode execution completed"
	
	return 0
}

# ============================================================================
# Export Functions
# ============================================================================

export -f execute_script
export -f run_normal_mode
