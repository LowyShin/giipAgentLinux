#!/bin/bash
# SSH Connection Logger Module
# Version: 1.0
# Date: 2025-11-14
# Purpose: Log SSH connection attempts and results to KVS
# Usage: Source this file and call log_ssh_attempt() / log_ssh_result()

# ============================================================================
# SSH Connection Logging Functions
# ============================================================================

# Function: Log SSH connection attempt (before connecting)
# Usage: log_ssh_attempt "remote_host" "remote_port" "remote_user" "auth_method" "remote_lssn" "hostname"
# Parameters:
#   $1 - remote_host: Target server IP/hostname
#   $2 - remote_port: SSH port (default 22)
#   $3 - remote_user: SSH username
#   $4 - auth_method: "password" or "key"
#   $5 - remote_lssn: Target server LSSN (optional)
#   $6 - hostname: Target server hostname (optional)
log_ssh_attempt() {
	local remote_host=$1
	local remote_port=$2
	local remote_user=$3
	local auth_method=$4
	local remote_lssn=${5:-0}
	local hostname=${6:-"unknown"}
	
	# Validate required parameters
	if [ -z "$remote_host" ] || [ -z "$remote_port" ] || [ -z "$remote_user" ]; then
		echo "[SSH-Logger] ⚠️  Missing required parameters for log_ssh_attempt" >&2
		return 1
	fi
	
	# Build connection attempt details JSON
	local connection_attempt="{\"target_host\":\"${remote_host}\",\"target_port\":${remote_port},\"target_user\":\"${remote_user}\",\"target_lssn\":${remote_lssn},\"target_hostname\":\"${hostname}\",\"auth_method\":\"${auth_method}\",\"status\":\"attempting\",\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}"
	
	# Save to KVS (requires save_execution_log from kvs.sh)
	if type save_execution_log >/dev/null 2>&1; then
		save_execution_log "ssh_connection_attempt" "$connection_attempt"
		
		local logdt=$(date '+%Y%m%d%H%M%S')
		echo "[${logdt}] [SSH-Logger] 🔌 Attempting SSH: ${remote_user}@${remote_host}:${remote_port} (LSSN:${remote_lssn}, method:${auth_method})" >> $LogFileName
	else
		echo "[SSH-Logger] ⚠️  save_execution_log function not found (kvs.sh not loaded?)" >&2
		return 1
	fi
	
	return 0
}

# Function: Log SSH connection result (after connecting)
# Usage: log_ssh_result "remote_host" "remote_port" "exit_code" "duration_seconds" "remote_lssn" "hostname"
# Parameters:
#   $1 - remote_host: Target server IP/hostname
#   $2 - remote_port: SSH port
#   $3 - exit_code: Command exit code (0=success, non-zero=failure)
#   $4 - duration_seconds: Execution duration in seconds
#   $5 - remote_lssn: Target server LSSN (optional)
#   $6 - hostname: Target server hostname (optional)
log_ssh_result() {
	local remote_host=$1
	local remote_port=$2
	local exit_code=$3
	local duration_seconds=$4
	local remote_lssn=${5:-0}
	local hostname=${6:-"unknown"}
	
	# Validate required parameters
	if [ -z "$remote_host" ] || [ -z "$remote_port" ] || [ -z "$exit_code" ]; then
		echo "[SSH-Logger] ⚠️  Missing required parameters for log_ssh_result" >&2
		return 1
	fi
	
	# Determine status
	local status="failed"
	local status_icon="❌"
	if [ "$exit_code" -eq 0 ]; then
		status="success"
		status_icon="✅"
	fi
	
	# Build connection result details JSON
	local connection_result="{\"target_host\":\"${remote_host}\",\"target_port\":${remote_port},\"target_lssn\":${remote_lssn},\"target_hostname\":\"${hostname}\",\"exit_code\":${exit_code},\"status\":\"${status}\",\"duration_seconds\":${duration_seconds},\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}"
	
	# Save to KVS
	if type save_execution_log >/dev/null 2>&1; then
		save_execution_log "ssh_connection_result" "$connection_result"
		
		local logdt=$(date '+%Y%m%d%H%M%S')
		echo "[${logdt}] [SSH-Logger] ${status_icon} SSH result: ${remote_host}:${remote_port} (exit_code:${exit_code}, duration:${duration_seconds}s)" >> $LogFileName
	else
		echo "[SSH-Logger] ⚠️  save_execution_log function not found (kvs.sh not loaded?)" >&2
		return 1
	fi
	
	return 0
}

# Function: Log remote execution event (high-level)
# Usage: log_remote_execution "started|success|failed" "hostname" "lssn" "ssh_host" "ssh_port" "queue_available" "error_message"
# Parameters:
#   $1 - execution_status: "started", "success", or "failed"
#   $2 - hostname: Target server hostname
#   $3 - lssn: Target server LSSN
#   $4 - ssh_host: SSH connection host
#   $5 - ssh_port: SSH connection port
#   $6 - queue_available: "true" or "false" (optional, default "unknown")
#   $7 - error_message: Error description if failed (optional)
log_remote_execution() {
	local execution_status=$1
	local hostname=$2
	local lssn=$3
	local ssh_host=$4
	local ssh_port=$5
	local queue_available=${6:-"unknown"}
	local error_message=${7:-""}
	
	# Validate required parameters
	if [ -z "$execution_status" ] || [ -z "$hostname" ] || [ -z "$lssn" ]; then
		echo "[SSH-Logger] ⚠️  Missing required parameters for log_remote_execution" >&2
		return 1
	fi
	
	# Build remote execution details JSON
	local remote_exec_details="{\"hostname\":\"${hostname}\",\"lssn\":${lssn},\"ssh_host\":\"${ssh_host}\",\"ssh_port\":${ssh_port},\"queue_available\":${queue_available},\"execution_status\":\"${execution_status}\""
	
	# Add error message if provided
	if [ -n "$error_message" ]; then
		remote_exec_details="${remote_exec_details},\"error_message\":\"${error_message}\""
	fi
	
	remote_exec_details="${remote_exec_details}}"
	
	# Save to KVS
	if type save_execution_log >/dev/null 2>&1; then
		save_execution_log "remote_execution" "$remote_exec_details"
		
		local logdt=$(date '+%Y%m%d%H%M%S')
		local status_icon="🔄"
		case "$execution_status" in
			success) status_icon="✅" ;;
			failed) status_icon="❌" ;;
			started) status_icon="🚀" ;;
		esac
		
		echo "[${logdt}] [SSH-Logger] ${status_icon} Remote execution: ${hostname} (LSSN:${lssn}) - ${execution_status}" >> $LogFileName
	else
		echo "[SSH-Logger] ⚠️  save_execution_log function not found (kvs.sh not loaded?)" >&2
		return 1
	fi
	
	return 0
}

# ============================================================================
# Export Functions
# ============================================================================

export -f log_ssh_attempt
export -f log_ssh_result
export -f log_remote_execution

# ============================================================================
# Module Loaded Confirmation
# ============================================================================

echo "[SSH-Logger] Module loaded successfully" >&2
