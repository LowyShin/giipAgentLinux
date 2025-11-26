#!/bin/bash
# giipAgent KVS Logging Library
# Version: 2.00
# Date: 2025-01-10
# Purpose: KVS (Key-Value Store) logging functions for execution tracking
# Rule: Follow giipapi_rules.md - text contains parameter names only, jsondata contains actual values

# ⚠️ ⚠️ ⚠️ CRITICAL - DO NOT MODIFY WITHOUT EXPLICIT AUTHORIZATION ⚠️ ⚠️ ⚠️
# This library is used across the entire giipAgent system:
#   - giipAgent3.sh (main agent)
#   - check-process-flood.sh
#   - collect-server-diagnostics.sh
#   - collect-perfmon.sh
#   - lib/gateway.sh
#   - And many other scripts
#
# MODIFICATION RULE:
# - DO NOT MODIFY kvs_put() or any function without EXPLICIT user authorization
# - DO NOT CHANGE the JSON structure or API contract
# - ANY CHANGE HERE AFFECTS THE ENTIRE SYSTEM
# - Contact project owner BEFORE making any modifications
#
# Current API Contract (DO NOT BREAK):
#   kvs_put "kType" "kKey" "kFactor" '{"json":"object"}'
#   - kType: "lssn" (key type)
#   - kKey: LSSN value (string)
#   - kFactor: factor name (string) 
#   - kValue: RAW JSON object (NOT escaped string)
#
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
	
	# Debug: Print the JSON before sending
	echo "[KVS-Debug] event_type='${event_type}'" >&2
	echo "[KVS-Debug] details_json='${details_json}'" >&2
	echo "[KVS-Debug] kvalue='${kvalue}'" >&2
	
	# Build API URL
	local kvs_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && kvs_url="${kvs_url}?code=${apiaddrcode}"
	
	# ✅ Follow giipapi_rules.md: text contains parameter names only!
	local text="KVSPut kType kKey kFactor"
	
	# ✅ jsondata contains actual values
	local jsondata="{\"kType\":\"lssn\",\"kKey\":\"${lssn}\",\"kFactor\":\"giipagent\",\"kValue\":${kvalue}}"
	
	echo "[KVS-Debug] jsondata='${jsondata}'" >&2
	
	# Build POST data with proper URL encoding for each parameter
	# wget --post-data does NOT automatically encode values, so we must encode jsondata
	local encoded_text=$(printf '%s' "$text" | jq -sRr '@uri')
	local encoded_token=$(printf '%s' "$sk" | jq -sRr '@uri')
	local encoded_jsondata=$(printf '%s' "$jsondata" | jq -sRr '@uri')
	
	local post_data="text=${encoded_text}&token=${encoded_token}&jsondata=${encoded_jsondata}"
	
	# Debug: Save POST data to file for inspection
	echo "$post_data" > /tmp/kvs_post_data.txt
	echo "[KVS-Debug] POST data length: ${#post_data}" >&2
	echo "[KVS-Debug] POST data saved to /tmp/kvs_post_data.txt" >&2
	
	# Call API (using giipApiSk2 with token parameter)
	# Note: jsondata is URL-encoded to prevent special characters from breaking POST data
	# Save response to temp file for debugging
	local response_file=$(mktemp)
	local stderr_file=$(mktemp)
	wget -O "$response_file" \
		--post-data="$post_data" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"${kvs_url}" \
		--no-check-certificate \
		--server-response \
		-v 2>"$stderr_file"
	
	local exit_code=$?
	if [ $exit_code -eq 0 ]; then
		echo "[KVS-Log] ✅ Saved: ${event_type}"
		if [ -n "$LogFileName" ]; then
			echo "[KVS-Log] ✅ Saved: ${event_type}" >> "$LogFileName"
		fi
		rm -f "$response_file" "$stderr_file"
	else
		# Log error with API response and HTTP details
		local api_response=$(cat "$response_file" 2>/dev/null)
		local http_status=$(grep "HTTP/" "$stderr_file" 2>/dev/null | tail -1)
		local full_stderr=$(cat "$stderr_file" 2>/dev/null)
		echo "[KVS-Log] ⚠️  Failed to save: ${event_type} (exit_code=${exit_code})" >&2
		echo "[KVS-Log] ⚠️  HTTP Status: ${http_status}" >&2
		echo "[KVS-Log] ⚠️  API Response (full): ${api_response}" >&2
		echo "[KVS-Log] ⚠️  Request URL: ${kvs_url}" >&2
		echo "[KVS-Log] ⚠️  Sent encoded_jsondata (first 200 chars): ${encoded_jsondata:0:200}..." >&2
		echo "[KVS-Log] ⚠️  Full wget stderr output:" >&2
		echo "${full_stderr}" >&2
		if [ -n "$LogFileName" ]; then
			echo "[KVS-Log] ⚠️  Failed to save: ${event_type} (exit_code=${exit_code})" >> "$LogFileName"
			echo "[KVS-Log] ⚠️  HTTP Status: ${http_status}" >> "$LogFileName"
			echo "[KVS-Log] ⚠️  API Response: ${api_response}" >> "$LogFileName"
			echo "[KVS-Log] ⚠️  Request jsondata: ${jsondata:0:150}..." >> "$LogFileName"
		fi
		rm -f "$response_file" "$stderr_file"
		
		# Log error to database
		log_error "KVS logging failed: ${event_type}" "KVSError" "save_execution_log at lib/kvs.sh, exit_code=${exit_code}, http_status=${http_status}, response=${api_response}"
	fi
	
	return $exit_code
}

# Function: Save simple KVS key-value pair
# ⚠️ ⚠️ ⚠️ CRITICAL FUNCTION - DO NOT MODIFY WITHOUT EXPLICIT AUTHORIZATION ⚠️ ⚠️ ⚠️
# 
# This function is used throughout the system. Any modification will break:
#   - Gateway mode remote server processing
#   - Performance monitoring
#   - Server diagnostics collection
#   - Process flood detection
#   - And all other KVS logging
#
# DO NOT CHANGE:
# - Function signature
# - JSON structure or escaping method
# - Parameter handling or API contract
#
# IF YOU ENCOUNTER ISSUES:
# - DO NOT modify this function
# - Check the CALLING CODE instead
# - Verify that JSON is properly formed BEFORE calling kvs_put()
# - Use debug logging to trace the problem
#
# Usage: kvs_put "kType" "kKey" "kFactor" "kValue_json"
# Example: kvs_put "lssn" "71174" "test" '{"status":"ok"}'
# CRITICAL: kValue MUST be a raw JSON object, not an escaped string
kvs_put() {
	local ktype=$1
	local kkey=$2
	local kfactor=$3
	local kvalue_json=$4
	
	# ✅ Handle empty kvalue_json - record as empty/null for tracking
	if [ -z "$kvalue_json" ] || [ "$kvalue_json" = "null" ]; then
		echo "[KVS-Put] ⚠️  Warning: kvalue_json is empty or null for kFactor=$kfactor - recording as empty object" >&2
		kvalue_json="{}"  # Store empty object instead of skipping
	fi
	
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
	# Convert kvalue_json to JSON string (escape special characters for safe transmission)
	# This ensures the kValue is stored as a string in KVS, not as raw JSON object
	local kvalue_escaped=$(printf '%s' "$kvalue_json" | jq -R -s '.')
	local jsondata="{\"kType\":\"${ktype}\",\"kKey\":\"${kkey}\",\"kFactor\":\"${kfactor}\",\"kValue\":${kvalue_escaped}}"
	
	# URL-encode all POST parameters (wget --post-data does NOT auto-encode)
	local encoded_text=$(printf '%s' "$text" | jq -sRr '@uri')
	local encoded_token=$(printf '%s' "$sk" | jq -sRr '@uri')
	local encoded_jsondata=$(printf '%s' "$jsondata" | jq -sRr '@uri')
	
	# Call API with response capture for debugging
	local response_file=$(mktemp)
	local stderr_file=$(mktemp)
	wget -O "$response_file" \
		--post-data="text=${encoded_text}&token=${encoded_token}&jsondata=${encoded_jsondata}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"${kvs_url}" \
		--no-check-certificate \
		--server-response \
		-v 2>"$stderr_file"
	
	local exit_code=$?
	if [ $exit_code -ne 0 ]; then
		local api_response=$(cat "$response_file" 2>/dev/null | head -c 200)
		local http_status=$(grep "HTTP/" "$stderr_file" 2>/dev/null | tail -1)
		echo "[KVS-Put] ⚠️  Failed (exit_code=${exit_code}): ${api_response}" >&2
		echo "[KVS-Put] ⚠️  HTTP Status: ${http_status}" >&2
	fi
	rm -f "$response_file" "$stderr_file"
	
	return $exit_code
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

# Function: Save DPA (Database Performance Analysis) data to KVS
# Usage: save_dpa_data "db_name" '{"slow_queries":[...]}'
# kFactor: sqlnetinv (compatible with existing dpa-put-*.sh scripts)
save_dpa_data() {
	local db_name=$1
	local dpa_json=$2
	
	# Validate required variables
	if [ -z "$lssn" ] || [ -z "$sk" ] || [ -z "$apiaddrv2" ]; then
		echo "[DPA] ⚠️  Missing required variables (lssn, sk, apiaddrv2)" >&2
		return 1
	fi
	
	if [ -z "$db_name" ] || [ -z "$dpa_json" ]; then
		echo "[DPA] ⚠️  Missing db_name or dpa_json" >&2
		return 1
	fi
	
	# Build timestamp and hostname info
	local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	local hostname=$(hostname)
	
	# Build kValue JSON with DPA data
	local kvalue="{\"collected_at\":\"${timestamp}\",\"collector_host\":\"${hostname}\",\"lssn\":${lssn},\"db_name\":\"${db_name}\",\"dpa_data\":${dpa_json}}"
	
	echo "[DPA] Saving DPA data for ${db_name} to KVS (kFactor=sqlnetinv)..." >&2
	
	# Use kvs_put function with sqlnetinv kFactor
	kvs_put "lssn" "${lssn}" "sqlnetinv" "${kvalue}"
	
	local exit_code=$?
	if [ $exit_code -eq 0 ]; then
		echo "[DPA] ✅ Saved DPA data for ${db_name}" >&2
		if [ -n "$LogFileName" ]; then
			echo "[DPA] ✅ Saved DPA data for ${db_name}" >> "$LogFileName"
		fi
	else
		echo "[DPA] ⚠️  Failed to save DPA data for ${db_name}" >&2
		if [ -n "$LogFileName" ]; then
			echo "[DPA] ⚠️  Failed to save DPA data for ${db_name}" >> "$LogFileName"
		fi
	fi
	
	return $exit_code
}

# ============================================================================
# Export Functions
# ============================================================================

export -f save_execution_log
export -f kvs_put
export -f save_gateway_status
export -f save_dpa_data

# ============================================================================
# Backward Compatibility Aliases
# ============================================================================

# Alias for backward compatibility
# Usage: log_kvs "event_type" "{\"details\":\"json\"}"
log_kvs() {
	save_execution_log "$@"
}

export -f log_kvs
