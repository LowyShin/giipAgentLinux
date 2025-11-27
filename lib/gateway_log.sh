#!/bin/bash
# Gateway Logging Functions
# Version: 1.00
# Purpose: Centralized logging for gateway operations
# Responsibility: Handle all logging output ONLY

# Function: Log gateway operation to both stderr AND tKVS
# Usage: gateway_log "🟢" "[5.4]" "Gateway 서버 목록 조회 시작" "additional_json_data"
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
	local json_payload="{\"event_type\":\"gateway_operation\",\"point\":\"${point}\""
	
	# Only append extra_json if provided (it must be valid JSON fragment)
	if [ -n "$extra_json" ]; then
		json_payload="${json_payload},${extra_json}}"
	else
		json_payload="${json_payload}}"
	fi
	
	# Call kvs_put with proper JSON object (NOT escaped string)
	if type kvs_put >/dev/null 2>&1; then
		kvs_put "lssn" "${lssn:-0}" "gateway_operation" "$json_payload" 2>/dev/null
	fi
}

# Export functions
export -f gateway_log
