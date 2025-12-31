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
	
	# Validate required global variables
	if [ -z "$sk" ] || [ -z "$apiaddrv2" ]; then
		echo "[queue_get] ⚠️  Missing required variables (sk, apiaddrv2)" >&2
		return 1
	fi
	
	# Build API URL
	local api_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && api_url="${api_url}?code=${apiaddrcode}"
	
	# ✅ Follow giipapi_rules.md: text contains parameter names only!
	local text="CQEQueueGet lssn hostname os op"
	local jsondata="{\"lssn\":${lssn},\"hostname\":\"${hostname}\",\"os\":\"${os}\",\"op\":\"op\"}"
	
	local temp_response="/tmp/queue_response_$$.json"
	
	# Clean up old temp files
	rm -f /tmp/queue_response_* 2>/dev/null
	
	# URL encode parameters (same pattern as kvs.sh for consistency)
	# This is required because curl -d does NOT automatically encode values
	local encoded_text=$(printf '%s' "$text" | jq -sRr '@uri' 2>/dev/null || echo "$text")
	local encoded_token=$(printf '%s' "$sk" | jq -sRr '@uri' 2>/dev/null || echo "$sk")
	local encoded_jsondata=$(printf '%s' "$jsondata" | jq -sRr '@uri' 2>/dev/null || echo "$jsondata")
	
	# Call CQEQueueGet API with URL-encoded parameters
	curl -s -X POST "$api_url" \
		-d "text=${encoded_text}&token=${encoded_token}&jsondata=${encoded_jsondata}" \
		-H "Content-Type: application/x-www-form-urlencoded" \
		--insecure -o "$temp_response" 2>&1
	
	local curl_exit_code=$?
	
	# Check if response file was created and has content
	if [ ! -s "$temp_response" ]; then
		rm -f "$temp_response"
		echo "[queue_get] ❌ API call failed or no response (curl exit code: $curl_exit_code)" >&2
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
		return 1
	fi
	
	# Extract script from JSON response
	# Try multiple methods to ensure robust parsing
	
	# Method 1: Using jq (most reliable)
	if command -v jq >/dev/null 2>&1; then
		local script=$(jq -r '.data[0].ms_body // .ms_body // empty' "$temp_response" 2>/dev/null)
		if [ -n "$script" ] && [ "$script" != "null" ]; then
			echo "$script" > "$output_file"
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
	
	echo "[queue_get] ❌ Failed to extract script from API response" >&2
	echo "[queue_get] DEBUG: Response content (first 1000 chars):" >&2
	echo "$response_content" >&2
	echo "[queue_get] DEBUG: API URL: $api_url" >&2
	echo "[queue_get] DEBUG: jsondata: $jsondata" >&2
	
	return 1
}

export -f queue_get
