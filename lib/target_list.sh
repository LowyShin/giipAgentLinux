#!/bin/bash
################################################################################
# Target Server List Module
# Purpose: Display and manage target server list for SSH connection tests
# Author: GIIP Agent
# Version: 1.0
# Date: 2025-11-27
#
# Usage:
#   . "${LIB_DIR}/target_list.sh"
#   display_target_servers "/tmp/gateway_servers_12345.json"
#
# This module provides:
#   - display_target_servers: Display servers from JSON file with formatting
################################################################################

# Color codes (if not already defined)
if [ -z "$RED" ]; then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[1;33m'
	BLUE='\033[0;34m'
	NC='\033[0m' # No Color
fi

# Print colored output functions
print_info() {
	echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
	echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
	echo -e "${RED}❌ $1${NC}"
}

print_warning() {
	echo -e "${YELLOW}⚠️  $1${NC}"
}

# Display target servers from JSON file
display_target_servers() {
	local json_file="$1"
	
	# Validate input
	if [ -z "$json_file" ]; then
		print_error "JSON file path not provided"
		return 1
	fi
	
	if [ ! -f "$json_file" ]; then
		print_error "JSON file not found: ${json_file}"
		return 1
	fi
	
	if [ ! -r "$json_file" ]; then
		print_error "JSON file is not readable: ${json_file}"
		return 1
	fi
	
	print_success "Starting SSH connection tests"
	echo ""
	print_info "📋 Target servers:"
	echo "═══════════════════════════════════════════════════════════════"
	
	local server_count=0
	
	# Try using jq first
	if command -v jq &> /dev/null; then
		# Extract and display servers using jq
		local temp_servers="/tmp/servers_to_display_$$.jsonl"
		jq -c '.data[]? // .[]? // .' "$json_file" 2>/dev/null > "$temp_servers"
		
		while IFS= read -r server_json; do
			[ -z "$server_json" ] && continue
			
			local hostname=$(echo "$server_json" | jq -r '.hostname // empty' 2>/dev/null)
			local lssn=$(echo "$server_json" | jq -r '.lssn // empty' 2>/dev/null)
			local ssh_host=$(echo "$server_json" | jq -r '.ssh_host // empty' 2>/dev/null)
			local ssh_user=$(echo "$server_json" | jq -r '.ssh_user // empty' 2>/dev/null)
			local ssh_port=$(echo "$server_json" | jq -r '.ssh_port // 22' 2>/dev/null)
			
			((server_count++))
			print_info "  [$server_count] ${hostname} (${ssh_host}:${ssh_port}) user:${ssh_user}"
		done < "$temp_servers"
		rm -f "$temp_servers"
	else
		# Fallback: use grep for JSON parsing
		print_warning "jq not found, using grep fallback for JSON parsing"
		
		local temp_servers="/tmp/servers_to_display_$$.jsonl"
		tr -d '\n' < "$json_file" | sed 's/}/}\n/g' | grep -o '{[^}]*}' > "$temp_servers"
		
		while IFS= read -r server_json; do
			[ -z "$server_json" ] && continue
			
			local hostname=$(echo "$server_json" | grep -o '"hostname"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			local lssn=$(echo "$server_json" | grep -o '"lssn"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
			local ssh_host=$(echo "$server_json" | grep -o '"ssh_host"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			local ssh_user=$(echo "$server_json" | grep -o '"ssh_user"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			local ssh_port=$(echo "$server_json" | grep -o '"ssh_port"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/' || echo "22")
			
			((server_count++))
			print_info "  [$server_count] ${hostname} (${ssh_host}:${ssh_port}) user:${ssh_user}"
		done < "$temp_servers"
		rm -f "$temp_servers"
	fi
	
	echo "═══════════════════════════════════════════════════════════════"
	
	if [ $server_count -eq 0 ]; then
		print_error "No servers found in JSON file"
		return 1
	fi
	
	print_success "Found $server_count server(s)"
	echo ""
	return 0
}

################################################################################
# Export functions for use in other scripts
################################################################################

export -f print_info
export -f print_success
export -f print_error
export -f print_warning
export -f display_target_servers
