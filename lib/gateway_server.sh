#!/bin/bash
# Gateway Server Management Functions
# Version: 1.00
# Purpose: Server extraction, validation, and processing
# Responsibility: Handle server JSON parsing and validation ONLY

# Function: Parse server JSON and return extracted values
# Returns: JSON string with all server parameters
# Usage: server_params=$(extract_server_params "$server_json")
# Note: 'enabled' field is no longer parsed or checked
extract_server_params() {
	local server_json="$1"
	local hostname ssh_user ssh_host ssh_port ssh_key_path ssh_password os_info lssn
	
	# 🔴 DEBUG: 입력 JSON 확인
	if type gateway_log >/dev/null 2>&1; then
		gateway_log "🔵" "[5.4.9-INPUT]" "extract_server_params input: $(echo -n "$server_json" | head -c 100)..."
	fi
	
	if command -v jq &> /dev/null; then
		# jq method
		hostname=$(echo "$server_json" | jq -r '.hostname // empty' 2>/dev/null)
		lssn=$(echo "$server_json" | jq -r '.lssn // empty' 2>/dev/null)
		ssh_host=$(echo "$server_json" | jq -r '.ssh_host // empty' 2>/dev/null)
		ssh_user=$(echo "$server_json" | jq -r '.ssh_user // empty' 2>/dev/null)
		ssh_port=$(echo "$server_json" | jq -r '.ssh_port // empty' 2>/dev/null)
		ssh_key_path=$(echo "$server_json" | jq -r '.ssh_key_path // empty' 2>/dev/null)
		ssh_password=$(echo "$server_json" | jq -r '.ssh_password // empty' 2>/dev/null)
		os_info=$(echo "$server_json" | jq -r '.os_info // empty' 2>/dev/null)
	else
		# grep fallback
		hostname=$(echo "$server_json" | grep -o '"hostname"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		lssn=$(echo "$server_json" | grep -o '"lssn"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
		ssh_host=$(echo "$server_json" | grep -o '"ssh_host"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		ssh_user=$(echo "$server_json" | grep -o '"ssh_user"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		ssh_port=$(echo "$server_json" | grep -o '"ssh_port"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
		ssh_key_path=$(echo "$server_json" | grep -o '"ssh_key_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		ssh_password=$(echo "$server_json" | grep -o '"ssh_password"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		os_info=$(echo "$server_json" | grep -o '"os_info"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
	fi
	
	# Return as JSON string (without enabled field)
	echo "{\"hostname\":\"${hostname}\",\"lssn\":\"${lssn}\",\"ssh_host\":\"${ssh_host}\",\"ssh_user\":\"${ssh_user}\",\"ssh_port\":${ssh_port:-22},\"ssh_key_path\":\"${ssh_key_path}\",\"ssh_password\":\"${ssh_password}\",\"os_info\":\"${os_info:-Linux}\"}"
}

# Function: Validate server parameters
# Returns: 0 if valid, 1 if should skip
# Usage: if validate_server_params "$server_params"; then...
# Note: No longer checks 'enabled' field - all servers are processed regardless of enabled status
validate_server_params() {
	local server_params="$1"
	
	# Check if hostname is empty
	local hostname=$(echo "$server_params" | jq -r '.hostname // empty' 2>/dev/null)
	if [ -z "$hostname" ]; then
		# Fallback: try grep
		hostname=$(echo "$server_params" | grep -o '"hostname"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
	fi
	
	[[ -z "$hostname" ]] && return 1
	return 0
}

# Export functions
export -f extract_server_params
export -f validate_server_params
