#!/bin/bash
# DEPRECATED KVS Functions
# Date: 2025-12-28
# Purpose: Backward compatibility - unused functions from kvs.sh
# Status: NOT USED - kept for reference only

# Function: Save Gateway status to KVS (backward compatibility)
# Usage: save_gateway_status "startup|error|sync" "{\"status\":\"...\"}"
# Status: NOT USED - replaced by save_execution_log
save_gateway_status() {
	# Clean up old kvs temp files BEFORE creating new ones
	rm -f /tmp/kvs_put_response_* /tmp/kvs_put_stderr_* 2>/dev/null
	
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

export -f save_gateway_status
