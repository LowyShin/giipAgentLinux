#!/bin/bash
# giipAgent KVS Logging Library
# Version: 2.00
# Date: 2025-01-10
# Purpose: KVS (Key-Value Store) logging functions for execution tracking
# Rule: Follow giipapi_rules.md - text contains parameter names only, jsondata contains actual values

# ⚠️ ⚠️ ⚠️ CRITICAL - DO NOT MODIFY WITHOUT EXPLICIT AUTHORIZATION ⚠️ ⚠️ ⚠️
# 
# 🔒 ABSOLUTE RULES (절대 지켜야 할 규칙) - NEVER BREAK THESE:
#
# 1. 🚫 사용자 허락 없이 kvs.sh 사양을 변경하면 안 됨
#    - API Contract 변경 금지
#    - 함수 시그니처 변경 금지
#    - JSON 구조 변경 금지
#    - 에러 처리 로직 변경 금지
#    → 반드시 사용자 명시적 승인 필요
#
# 2. 🔄 kValue는 어떤 값이 들어가도 에러 없이 raw data로 저장
#    - JSON 객체도 가능: '{"key":"value"}'
#    - 일반 텍스트도 가능: 'Error message'
#    - 숫자도 가능: '12345'
#    - 특수문자도 가능: '含む特殊文字'
#    - 화면 표시 텍스트도 가능
#    - 어떤 값이든 그대로 저장됨 (에러 없음)
#    → 이것이 설계의 핵심 원칙
#
# 3. ✅ 호출 코드에서만 데이터를 처리할 것
#    - kvs_put()은 받은 값을 그대로 저장하기만 함
#    - 데이터 검증/변환은 호출 코드에서 담당
#    - kvs.sh는 절대 로직을 추가하지 말 것
#
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
# - DO NOT ESCAPE or TRANSFORM kValue (keep it raw)
# - ANY CHANGE HERE AFFECTS THE ENTIRE SYSTEM
# - Contact project owner BEFORE making any modifications
#
# Current API Contract (DO NOT BREAK):
#   kvs_put "kType" "kKey" "kFactor" '{"json":"object"}'
#   - kType: "lssn" (key type)
#   - kKey: LSSN value (string)
#   - kFactor: factor name (string) 
#   - kValue: RAW DATA AS-IS (어떤 값이든 그대로 저장)
#
# ============================================================================
# KVS Execution Logging Functions
# ============================================================================

# Function: Save execution log to KVS (giipagent factor)
# Usage: save_execution_log "event_type" "{\"details\":\"json\"}" OR "event_type" "any text value"
# Event types: startup, queue_check, script_execution, error, shutdown, gateway_init, heartbeat
# 
# ⚠️ API Rules (giipapi_rules.md):
# - text: Parameter names only (e.g., "KVSPut kType kKey kFactor")
# - jsondata: Actual values as JSON string
# ⚠️ 중요: details_json은 JSON이어도 되고 텍스트여도 됨 - 어떤 값이든 처리됨
save_execution_log() {
	local event_type=$1
	local details_json=$2
	
	# Validate required variables
	if [ -z "$lssn" ] || [ -z "$sk" ] || [ -z "$apiaddrv2" ]; then
		echo "[KVS-Log] ⚠️  Missing required variables (lssn, sk, apiaddrv2)" >&2
		return 1
	fi
	
	# Clean up old kvs_exec temp files BEFORE creating new ones
	rm -f /tmp/kvs_exec_post_* /tmp/kvs_exec_response_* /tmp/kvs_exec_stderr_* 2>/dev/null
	
	local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	local hostname=$(hostname)
	local mode="${gateway_mode}"
	[ "$mode" = "1" ] && mode="gateway" || mode="normal"
	
	# Build kValue with details_json embedded as raw data (어떤 값이든 그대로 임베드)
	# details_json이 JSON이면 JSON으로, 텍스트면 텍스트로 그대로 저장됨
	local kvalue="{\"event_type\":\"${event_type}\",\"timestamp\":\"${timestamp}\",\"lssn\":${lssn},\"hostname\":\"${hostname}\",\"mode\":\"${mode}\",\"version\":\"${sv}\",\"details\":${details_json}}"
	
	# Minimal log for debugging if needed
	# echo "[KVS-Debug] event_type='${event_type}'" >&2
	
	# Build API URL
	local kvs_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && kvs_url="${kvs_url}?code=${apiaddrcode}"
	
	# ✅ Follow giipapi_rules.md: text contains parameter names only!
	local text="KVSPut kType kKey kFactor"
	
	# ✅ jsondata contains actual values
	local jsondata="{\"kType\":\"lssn\",\"kKey\":\"${lssn}\",\"kFactor\":\"giipagent\",\"kValue\":${kvalue}}"
	
	# echo "[KVS-Debug] jsondata='${jsondata}'" >&2
	
	# Build POST data with proper URL encoding for each parameter
	# wget --post-data does NOT automatically encode values, so we must encode jsondata
	local encoded_text=$(printf '%s' "$text" | jq -sRr '@uri')
	local encoded_token=$(printf '%s' "$sk" | jq -sRr '@uri')
	local encoded_jsondata=$(printf '%s' "$jsondata" | jq -sRr '@uri')
	
	local post_data="text=${encoded_text}&token=${encoded_token}&jsondata=${encoded_jsondata}"
	
	# Debug: Save POST data to file for inspection with specific naming
	local timestamp_ms=$(date +%s%N | cut -b1-13)
	local post_data_file="/tmp/kvs_exec_post_${timestamp_ms}.txt"
	echo "$post_data" > "$post_data_file"
	# echo "[KVS-Debug] POST data length: ${#post_data}" >&2
	# echo "[KVS-Debug] POST data saved to $post_data_file" >&2
	
	# Call API (using giipApiSk2 with token parameter)
	# Note: jsondata is URL-encoded to prevent special characters from breaking POST data
	# Save response to temp file for debugging
	local response_file="/tmp/kvs_exec_response_${timestamp_ms}"
	local stderr_file="/tmp/kvs_exec_stderr_${timestamp_ms}"
	wget -O "$response_file" \
		--timeout=30 --tries=1 \
		--post-data="$post_data" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"${kvs_url}" \
		--no-check-certificate \
		--server-response \
		-v 2>"$stderr_file"
	
	local exit_code=$?
	
	# Check wget exit code first
	if [ $exit_code -ne 0 ]; then
		# wget failed (network error, timeout, etc.)
		local api_response=$(cat "$response_file" 2>/dev/null)
		local http_status=$(grep "HTTP/" "$stderr_file" 2>/dev/null | tail -1)
		local full_stderr=$(cat "$stderr_file" 2>/dev/null)
		echo "[KVS-Log] ❌ wget failed: ${event_type} (exit_code=${exit_code})" >&2
		echo "[KVS-Log] ⚠️  HTTP Status: ${http_status}" >&2
		echo "[KVS-Log] ⚠️  Request URL: ${kvs_url}" >&2
		echo "[KVS-Log] ⚠️  Full wget stderr output:" >&2
		echo "${full_stderr}" >&2
		
		if [ -n "$LogFileName" ]; then
			echo "[KVS-Log] ❌ wget failed: ${event_type} (exit_code=${exit_code})" >> "$LogFileName"
			echo "[KVS-Log] ⚠️  HTTP Status: ${http_status}" >> "$LogFileName"
		fi
		
		rm -f "$response_file" "$stderr_file" "$post_data_file"
		
		# Log error to database
		log_error "KVS wget failed: ${event_type}" "NetworkError" "save_execution_log at lib/kvs.sh, exit_code=${exit_code}, http_status=${http_status}"
		
		return $exit_code
	fi
	
	# wget succeeded - now check API response (RstVal)
	local api_response=$(cat "$response_file" 2>/dev/null)
	
	# Parse RstVal from response
	local rst_val=$(echo "$api_response" | jq -r '.data[0].RstVal // .RstVal // "unknown"' 2>/dev/null)
	
	# If jq fails or RstVal not found, try grep
	if [ -z "$rst_val" ] || [ "$rst_val" = "unknown" ] || [ "$rst_val" = "null" ]; then
		rst_val=$(echo "$api_response" | grep -o '"RstVal"\s*:\s*"[^"]*"' 2>/dev/null | sed -n 's/.*"\([^"]*\)".*/\1/p' | head -1)
	fi
	
	# Check if API call was successful (RstVal = 200)
	if [ "$rst_val" = "200" ]; then
		# Success
		echo "[KVS-Log] ✅ Saved: ${event_type} (RstVal=200)"
		if [ -n "$LogFileName" ]; then
			echo "[KVS-Log] ✅ Saved: ${event_type} (RstVal=200)" >> "$LogFileName"
		fi
		rm -f "$response_file" "$stderr_file" "$post_data_file"
		return 0
	else
		# API returned error - extract details
		local rst_msg=$(echo "$api_response" | jq -r '.data[0].RstMsg // .RstMsg // .Proc_MSG // "unknown"' 2>/dev/null)
		local proc_name=$(echo "$api_response" | jq -r '.data[0].ProcName // .ProcName // "unknown"' 2>/dev/null)
		
		# Fallback grep if jq fails
		if [ -z "$rst_msg" ] || [ "$rst_msg" = "unknown" ] || [ "$rst_msg" = "null" ]; then
			rst_msg=$(echo "$api_response" | grep -o '"RstMsg"\s*:\s*"[^"]*"' 2>/dev/null | sed -n 's/.*"\([^"]*\)".*/\1/p' | head -1)
		fi
		if [ -z "$proc_name" ] || [ "$proc_name" = "unknown" ] || [ "$proc_name" = "null" ]; then
			proc_name=$(echo "$api_response" | grep -o '"ProcName"\s*:\s*"[^"]*"' 2>/dev/null | sed -n 's/.*"\([^"]*\)".*/\1/p' | head -1)
		fi
		
		# Log detailed error
		echo "[KVS-Log] ❌ API Error: ${event_type}" >&2
		echo "[KVS-Log] 📊 RstVal: ${rst_val}" >&2
		echo "[KVS-Log] 💬 RstMsg: ${rst_msg}" >&2
		echo "[KVS-Log] 🔧 ProcName: ${proc_name}" >&2
		echo "[KVS-Log] 📄 Full API Response: ${api_response}" >&2
		echo "[KVS-Log] 📤 Request URL: ${kvs_url}" >&2
		echo "[KVS-Log] 📤 Request jsondata (first 300 chars): ${jsondata:0:300}..." >&2
		
		if [ -n "$LogFileName" ]; then
			echo "[KVS-Log] ❌ API Error: ${event_type}" >> "$LogFileName"
			echo "[KVS-Log] 📊 RstVal: ${rst_val}" >> "$LogFileName"
			echo "[KVS-Log] 💬 RstMsg: ${rst_msg}" >> "$LogFileName"
			echo "[KVS-Log] 🔧 ProcName: ${proc_name}" >> "$LogFileName"
			echo "[KVS-Log] 📄 Full Response: ${api_response}" >> "$LogFileName"
			echo "[KVS-Log] 📤 Request jsondata (first 300 chars): ${jsondata:0:300}..." >> "$LogFileName"
		fi
		
		# Keep debug files for inspection
		echo "[KVS-Log] 🔍 Debug files saved:" >&2
		echo "  Response: $response_file" >&2
		echo "  Stderr: $stderr_file" >&2
		echo "  Post data: $post_data_file" >&2
		
		# Log error to database with detailed context
		local error_context="save_execution_log at lib/kvs.sh, event_type=${event_type}, RstVal=${rst_val}, RstMsg=${rst_msg}, ProcName=${proc_name}, API_URL=${kvs_url}, jsondata_preview=${jsondata:0:200}"
		log_error "KVS API failed: ${event_type} (RstVal=${rst_val})" "ApiError" "$error_context"
		
		return 1
	fi
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
		echo "[KVS-Put] ❌ ERROR: Missing required variables (sk, apiaddrv2)" >&2
		return 1
	fi
	
	# Build API URL
	local kvs_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && kvs_url="${kvs_url}?code=${apiaddrcode}"
	
	# ✅ Follow giipapi_rules.md
	local text="KVSPut kType kKey kFactor"
	# kValue: raw data as-is (can be JSON, text, numbers, anything)
	# No escaping - data embedded directly to preserve exact format
	local jsondata="{\"kType\":\"${ktype}\",\"kKey\":\"${kkey}\",\"kFactor\":\"${kfactor}\",\"kValue\":${kvalue_json}}"
	
	# URL-encode all POST parameters (wget --post-data does NOT auto-encode)
	local encoded_text=$(printf '%s' "$text" | jq -sRr '@uri')
	local encoded_token=$(printf '%s' "$sk" | jq -sRr '@uri')
	local encoded_jsondata=$(printf '%s' "$jsondata" | jq -sRr '@uri')
	
	# Call API with response capture for debugging
	# Use specific naming pattern for easier cleanup: kvs_put_response_<timestamp>
	local timestamp_ms=$(date +%s%N | cut -b1-13)
	local response_file="/tmp/kvs_put_response_${timestamp_ms}"
	local stderr_file="/tmp/kvs_put_stderr_${timestamp_ms}"
	
	wget -O "$response_file" \
		--timeout=30 --tries=1 \
		--post-data="text=${encoded_text}&token=${encoded_token}&jsondata=${encoded_jsondata}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"${kvs_url}" \
		--no-check-certificate \
		--server-response \
		-v 2>"$stderr_file"
	
	
	local exit_code=$?
	
	# Check wget exit code first
	if [ $exit_code -ne 0 ]; then
		# wget failed (network error, timeout, etc.)
		local api_response=$(cat "$response_file" 2>/dev/null | head -c 500)
		local http_status=$(grep "HTTP/" "$stderr_file" 2>/dev/null | tail -1)
		echo "[KVS-Put] ❌ wget failed: kType=$ktype, kKey=$kkey, kFactor=$kfactor, exit_code=$exit_code, HTTP: $http_status"
		echo "[KVS-Put] ❌ wget failed: kType=$ktype, kKey=$kkey, kFactor=$kfactor, exit_code=$exit_code, HTTP: $http_status" >&2
		rm -f "$response_file" "$stderr_file"
		return $exit_code
	fi
	
	# wget succeeded - now check API response (RstVal)
	local api_response=$(cat "$response_file" 2>/dev/null)
	
	# Parse RstVal from response
	local rst_val=$(echo "$api_response" | jq -r '.data[0].RstVal // .RstVal // "unknown"' 2>/dev/null)
	
	# If jq fails or RstVal not found, try grep
	if [ -z "$rst_val" ] || [ "$rst_val" = "unknown" ] || [ "$rst_val" = "null" ]; then
		rst_val=$(echo "$api_response" | grep -o '"RstVal"\s*:\s*"[^"]*"' 2>/dev/null | sed -n 's/.*"\([^"]*\)".*/\1/p' | head -1)
	fi
	
	# Check if API call was successful (RstVal = 200)
	if [ "$rst_val" = "200" ]; then
		# Success - silent (토큰 절약)
		rm -f "$response_file" "$stderr_file"
		return 0
	else
		# API returned error - extract details
		local rst_msg=$(echo "$api_response" | jq -r '.data[0].RstMsg // .RstMsg // .Proc_MSG // "unknown"' 2>/dev/null)
		local proc_name=$(echo "$api_response" | jq -r '.data[0].ProcName // .ProcName // "unknown"' 2>/dev/null)
		
		# Fallback grep if jq fails
		if [ -z "$rst_msg" ] || [ "$rst_msg" = "unknown" ] || [ "$rst_msg" = "null" ]; then
			rst_msg=$(echo "$api_response" | grep -o '"RstMsg"\s*:\s*"[^"]*"' 2>/dev/null | sed -n 's/.*"\([^"]*\)".*/\1/p' | head -1)
		fi
		if [ -z "$proc_name" ] || [ "$proc_name" = "unknown" ] || [ "$proc_name" = "null" ]; then
			proc_name=$(echo "$api_response" | grep -o '"ProcName"\s*:\s*"[^"]*"' 2>/dev/null | sed -n 's/.*"\([^"]*\)".*/\1/p' | head -1)
		fi
		
		# Log detailed error
		echo "[KVS-Put] ❌ API Error: kType=$ktype, kKey=$kkey, kFactor=$kfactor"
		echo "[KVS-Put] 📊 RstVal: $rst_val" >&2
		echo "[KVS-Put] 💬 RstMsg: $rst_msg" >&2
		echo "[KVS-Put] 🔧 ProcName: $proc_name" >&2
		echo "[KVS-Put] 📄 Full Response: $api_response" >&2
		echo "[KVS-Put] ❌ API Error: kType=$ktype, kKey=$kkey, kFactor=$kfactor" >&2
		
		# Keep debug files for inspection
		echo "[KVS-Put] 🔍 Debug files saved: response=$response_file, stderr=$stderr_file" >&2
		
		return 1
	fi
}

# Note: save_gateway_status() moved to lib/kvs_legacy.sh (not used)


# Function: Save DPA (Database Performance Analysis) data to KVS
# Usage: save_dpa_data "db_name" '{"slow_queries":[...]}'
# kFactor: sqlnetinv (compatible with existing dpa-put-*.sh scripts)
save_dpa_data() {
	# Clean up old kvs_put temp files BEFORE creating new ones
	rm -f /tmp/kvs_put_response_* /tmp/kvs_put_stderr_* 2>/dev/null
	
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



# ============================================================================
# Backward Compatibility Aliases
# ============================================================================

# Alias for backward compatibility
# Usage: log_kvs "event_type" "{\"details\":\"json\"}"
log_kvs() {
	save_execution_log "$@"
}

export -f log_kvs
