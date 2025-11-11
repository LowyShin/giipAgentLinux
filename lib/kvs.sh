#!/bin/bash
# giipAgent KVS Logging Library
# Version: 2.00
# Date: 2025-01-10
# Purpose: KVS (Key-Value Store) logging functions for execution tracking
# Rule: Follow giipapi_rules.md - text contains parameter names only, jsondata contains actual values

# ============================================================================
# KVS Execution Logging Functions
# ============================================================================

# Function: Save execution log to KVS (giipagent factor)
# Usage: save_execution_log "event_type" "{\"details\":\"json\"}"
# Event types: startup, queue_check, script_execution, error, shutdown, gateway_init, heartbeat
# 
# ⚠️ API Rules (giipapi_rules.md):
# - text: Parameter names only (e.g., "KVSPut kType kKey kFactor")
# - jsondata: Actual values as JSON string
save_execution_log() {
	local event_type=$1
	local details_json=$2
	
	# Validate required variables
	if [ -z "$lssn" ] || [ -z "$sk" ] || [ -z "$apiaddrv2" ]; then
		echo "[KVS-Log] ⚠️  Missing required variables (lssn, sk, apiaddrv2)" >&2
		return 1
	fi
	
	local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	local hostname=$(hostname)
	local mode="${gateway_mode}"
	[ "$mode" = "1" ] && mode="gateway" || mode="normal"
	
	# Build kValue JSON (details_json is already JSON, don't escape)
	local kvalue="{\"event_type\":\"${event_type}\",\"timestamp\":\"${timestamp}\",\"lssn\":${lssn},\"hostname\":\"${hostname}\",\"mode\":\"${mode}\",\"version\":\"${sv}\",\"details\":${details_json}}"
	
	# Build API URL
	local kvs_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && kvs_url="${kvs_url}?code=${apiaddrcode}"
	
	# ✅ Follow giipapi_rules.md: text contains parameter names only!
	local text="KVSPut kType kKey kFactor"
	
	# ✅ jsondata contains actual values
	local jsondata="{\"kType\":\"lssn\",\"kKey\":\"${lssn}\",\"kFactor\":\"giipagent\",\"kValue\":${kvalue}}"
	
	# URL encode jsondata for POST (only encode spaces)
	local jsondata_encoded=$(echo "$jsondata" | sed 's/ /%20/g')
	
	# Call API (using giipApiSk2 with token parameter)
	wget -O /dev/null \
		--post-data="text=${text}&token=${sk}&jsondata=${jsondata_encoded}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"${kvs_url}" \
		--no-check-certificate -q 2>&1
	
	local exit_code=$?
	if [ $exit_code -eq 0 ]; then
		echo "[KVS-Log] ✅ Saved: ${event_type}"
		if [ -n "$LogFileName" ]; then
			echo "[KVS-Log] ✅ Saved: ${event_type}" >> "$LogFileName"
		fi
	else
		echo "[KVS-Log] ⚠️  Failed to save: ${event_type} (exit_code=${exit_code})" >&2
		if [ -n "$LogFileName" ]; then
			echo "[KVS-Log] ⚠️  Failed to save: ${event_type} (exit_code=${exit_code})" >> "$LogFileName"
		fi
		
		# Log error to database
		log_error "KVS logging failed: ${event_type}" "KVSError" "save_execution_log at lib/kvs.sh, exit_code=${exit_code}"
	fi
	
	return $exit_code
}

# Function: Save simple KVS key-value pair
# Usage: kvs_put "kType" "kKey" "kFactor" "kValue_json"
# Example: kvs_put "lssn" "71174" "test" '{"status":"ok"}'
kvs_put() {
	local ktype=$1
	local kkey=$2
	local kfactor=$3
	local kvalue_json=$4
	
	# Validate required variables
	if [ -z "$sk" ] || [ -z "$apiaddrv2" ]; then
		echo "[KVS-Put] ⚠️  Missing required variables (sk, apiaddrv2)" >&2
		return 1
	fi
	
	# Build API URL
	local kvs_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && kvs_url="${kvs_url}?code=${apiaddrcode}"
	
	# ✅ Follow giipapi_rules.md
	local text="KVSPut kType kKey kFactor"
	local jsondata="{\"kType\":\"${ktype}\",\"kKey\":\"${kkey}\",\"kFactor\":\"${kfactor}\",\"kValue\":${kvalue_json}}"
	
	# Call API
	wget -O /dev/null \
		--post-data="text=${text}&token=${sk}&jsondata=$(echo ${jsondata} | sed 's/ /%20/g')" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"${kvs_url}" \
		--no-check-certificate -q 2>&1
	
	return $?
}

# Function: Save Gateway status to KVS (backward compatibility)
# Usage: save_gateway_status "startup|error|sync" "{\"status\":\"...\"}"
save_gateway_status() {
	local status_type=$1
	local status_json=$2
	
	# Validate required variables
	if [ -z "$lssn" ] || [ -z "$sk" ] || [ -z "$apiaddrv2" ]; then
		echo "[Gateway-Status] ⚠️  Missing required variables" >&2
		return 1
	fi
	
	# Build API URL
	local kvs_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && kvs_url="${kvs_url}?code=${apiaddrcode}"
	
	# ✅ Follow giipapi_rules.md
	local text="KVSPut kType kKey kFactor"
	local kvs_data="{\"kType\":\"gateway_status\",\"kKey\":\"gateway_${lssn}_${status_type}\",\"kFactor\":${status_json}}"
	
	wget -O /dev/null \
		--post-data="text=${text}&token=${sk}&jsondata=$(echo ${kvs_data} | sed 's/ /%20/g')" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"${kvs_url}" \
		--no-check-certificate -q 2>&1
	
	return $?
}

# ============================================================================
# Export Functions
# ============================================================================

export -f save_execution_log
export -f kvs_put
export -f save_gateway_status

# ============================================================================
# Backward Compatibility Aliases
# ============================================================================

# Alias for backward compatibility
# Usage: log_kvs "event_type" "{\"details\":\"json\"}"
log_kvs() {
	save_execution_log "$@"
}

export -f log_kvs
