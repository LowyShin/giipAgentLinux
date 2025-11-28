#!/bin/bash
################################################################################
# SSH Connection Test from Gateway JSON File
# Purpose: Read gateway_servers_*.json and test SSH connections to each server
# Author: Generated Script
# Version: 1.0
# Date: 2025-11-27
#
# Usage:
#   ./test_ssh_from_gateway_json.sh [json_file]
#   ./test_ssh_from_gateway_json.sh /tmp/gateway_servers_12345.json
#   ./test_ssh_from_gateway_json.sh  # Uses latest gateway_servers_*.json in /tmp
#
# Features:
#   - Auto-detects latest gateway_servers_*.json if not specified
#   - Tests each server with simple output
#   - Supports both password and key-based authentication
#   - Generates summary report
#   - Color-coded output for easy reading
################################################################################

# Script configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
LIB_DIR="${PARENT_DIR}/lib"
LOG_DIR="/tmp/ssh_test_logs"
mkdir -p "$LOG_DIR"

REPORT_FILE="${LOG_DIR}/ssh_test_report_$(date +%Y%m%d_%H%M%S).txt"
RESULT_JSON="${LOG_DIR}/ssh_test_results_$(date +%Y%m%d_%H%M%S).json"

# Initialize counters
TOTAL_SERVERS=0
SUCCESS_COUNT=0
FAILURE_COUNT=0
SKIPPED_COUNT=0

# ============================================================================
# Load required modules
# ============================================================================

# Load target list module for display and color functions
if [ -f "${LIB_DIR}/target_list.sh" ]; then
	. "${LIB_DIR}/target_list.sh"
else
	echo "❌ Error: target_list.sh not found in ${LIB_DIR}"
	exit 1
fi

# Load CQE module for queue_get function
if [ -f "${LIB_DIR}/cqe.sh" ]; then
	. "${LIB_DIR}/cqe.sh"
else
	echo "⚠️  Warning: cqe.sh not found in ${LIB_DIR}, queue_get will not be available"
fi

################################################################################
# Utility Functions
################################################################################

# Error exit handler
exit_with_error() {
	local error_msg="$1"
	local exit_code="${2:-1}"
	
	print_error "$error_msg"
	log_message "FATAL" "$error_msg"
	
	# Create error report if possible
	if [ -w "$LOG_DIR" ] 2>/dev/null; then
		echo "{\"error\":\"${error_msg}\",\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"exit_code\":${exit_code}}" > "${LOG_DIR}/error_$(date +%Y%m%d_%H%M%S).json"
	fi
	
	exit "$exit_code"
}

# Log to file and console
log_message() {
	local level="$1"
	local message="$2"
	local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	echo "[${timestamp}] [${level}] ${message}" | tee -a "$REPORT_FILE"
}

# Test SSH connection
test_ssh_connection() {
	local hostname="$1"
	local ssh_host="$2"
	local ssh_user="$3"
	local ssh_port="${4:-22}"
	local ssh_key_path="$5"
	local ssh_password="$6"
	local lssn="$7"
	
	local test_result="PENDING"
	local error_msg=""
	
	# Build SSH command
	local ssh_cmd="ssh"
	local ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
	
	# ========================================================================
	# EXCEPTION HANDLING: Parameter validation
	# ========================================================================
	
	# Validate hostname
	if [ -z "$hostname" ] || [ "$hostname" = "null" ]; then
		error_msg="hostname is empty or null"
		print_error "  └─ ✗ ${hostname:-NONE} - SKIPPED"
		echo "{\"hostname\":\"${hostname:-NONE}\",\"ssh_host\":\"${ssh_host:-NONE}\",\"lssn\":${lssn:-0},\"status\":\"SKIPPED\",\"error\":\"${error_msg}\"}" >> "$RESULT_JSON"
		((SKIPPED_COUNT++))
		return 2
	fi
	
	# Validate ssh_host (CRITICAL - cannot connect without this)
	if [ -z "$ssh_host" ] || [ "$ssh_host" = "null" ]; then
		error_msg="ssh_host is empty or null (cannot connect)"
		print_error "  └─ ✗ ${hostname} - SKIPPED"
		echo "{\"hostname\":\"${hostname}\",\"ssh_host\":\"${ssh_host:-NONE}\",\"lssn\":${lssn},\"status\":\"SKIPPED\",\"error\":\"${error_msg}\"}" >> "$RESULT_JSON"
		((SKIPPED_COUNT++))
		return 2
	fi
	
	# Validate ssh_user (CRITICAL - cannot connect without this)
	if [ -z "$ssh_user" ] || [ "$ssh_user" = "null" ]; then
		error_msg="ssh_user is empty or null (cannot connect)"
		print_error "  └─ ✗ ${hostname} - SKIPPED"
		echo "{\"hostname\":\"${hostname}\",\"ssh_host\":\"${ssh_host}\",\"ssh_user\":\"${ssh_user:-NONE}\",\"lssn\":${lssn},\"status\":\"SKIPPED\",\"error\":\"${error_msg}\"}" >> "$RESULT_JSON"
		((SKIPPED_COUNT++))
		return 2
	fi
	
	# Validate ssh_port is numeric
	if ! [[ "$ssh_port" =~ ^[0-9]+$ ]]; then
		ssh_port="22"
	fi
	
	# Validate ssh_port range
	if [ "$ssh_port" -lt 1 ] || [ "$ssh_port" -gt 65535 ]; then
		ssh_port="22"
	fi
	
	# ========================================================================
	# Try SSH connection with different authentication methods
	# ========================================================================
	
	local ssh_succeeded=0
	local remote_os_info=""
	
	if [ -n "$ssh_key_path" ] && [ "$ssh_key_path" != "null" ] && [ -f "$ssh_key_path" ]; then
		# Try key-based auth - Get OS info directly
		remote_os_info=$(timeout 15 $ssh_cmd $ssh_opts -i "$ssh_key_path" -p "$ssh_port" "${ssh_user}@${ssh_host}" "cat /etc/os-release 2>/dev/null | grep '^NAME=' | cut -d'=' -f2 | tr -d '\"' || uname -s" 2>/dev/null | head -1)
		if [ -n "$remote_os_info" ] && [ "$remote_os_info" != "null" ]; then
			test_result="SUCCESS"
			ssh_succeeded=1
		fi
	fi
	
	# If key auth failed or not available, try password auth
	if [ "$ssh_succeeded" -eq 0 ] && [ -n "$ssh_password" ] && [ "$ssh_password" != "null" ] && command -v sshpass &> /dev/null; then
		# Try password-based auth - Get OS info directly
		remote_os_info=$(timeout 15 sshpass -p "$ssh_password" $ssh_cmd $ssh_opts -p "$ssh_port" "${ssh_user}@${ssh_host}" "cat /etc/os-release 2>/dev/null | grep '^NAME=' | cut -d'=' -f2 | tr -d '\"' || uname -s" 2>/dev/null | head -1)
		if [ -n "$remote_os_info" ] && [ "$remote_os_info" != "null" ]; then
			test_result="SUCCESS"
			ssh_succeeded=1
		fi
	fi
	
	# If all methods failed or unavailable, try default SSH key - Get OS info directly
	if [ "$ssh_succeeded" -eq 0 ]; then
		remote_os_info=$(timeout 15 $ssh_cmd $ssh_opts -p "$ssh_port" "${ssh_user}@${ssh_host}" "cat /etc/os-release 2>/dev/null | grep '^NAME=' | cut -d'=' -f2 | tr -d '\"' || uname -s" 2>/dev/null | head -1)
		if [ -n "$remote_os_info" ] && [ "$remote_os_info" != "null" ]; then
			test_result="SUCCESS"
			ssh_succeeded=1
		else
			test_result="FAILED"
		fi
	fi
	
	# Set default OS if detection failed
	if [ -z "$remote_os_info" ] || [ "$remote_os_info" = "null" ]; then
		remote_os_info="Linux"
	fi
	
	# ========================================================================
	# Log and record results
	# ========================================================================
	
	# Log to file for debugging
	log_message "SSH_TEST" "${test_result} | hostname:${hostname} | ${ssh_host}:${ssh_port} | user:${ssh_user} | LSSN:${lssn}"
	
	# Display simple output
	case $test_result in
		SUCCESS)
			print_success "  └─ ✓ ${hostname} (${ssh_host}:${ssh_port}) - LSSN:${lssn} - OS: ${remote_os_info}"
			((SUCCESS_COUNT++))
			;;
		FAILED)
			print_error "  └─ ✗ ${hostname} (${ssh_host}:${ssh_port}) - LSSN:${lssn}"
			((FAILURE_COUNT++))
			;;
		SKIPPED)
			print_warning "  └─ ⊘ ${hostname} (${ssh_host}:${ssh_port}) - LSSN:${lssn}"
			((SKIPPED_COUNT++))
			;;
	esac
	
	# Append to JSON results (with comma handling) - Include OS information
	local json_entry="{\"hostname\":\"${hostname}\",\"ssh_host\":\"${ssh_host}\",\"ssh_user\":\"${ssh_user}\",\"ssh_port\":${ssh_port},\"lssn\":${lssn},\"os\":\"${remote_os_info}\",\"status\":\"${test_result}\",\"error\":\"${error_msg}\"}"
	
	# Remove trailing comma from previous entry if needed
	if [ -f "$RESULT_JSON" ]; then
		local last_line=$(tail -1 "$RESULT_JSON" 2>/dev/null)
		if [[ "$last_line" == *"}" ]]; then
			# Add comma to previous entry if it doesn't end with comma
			if [[ ! "$last_line" == *"}," ]]; then
				sed -i '$ s/}$/},/' "$RESULT_JSON" 2>/dev/null || true
			fi
		fi
	fi
	
	echo "$json_entry" >> "$RESULT_JSON" 2>/dev/null || true
	
	# Export OS information for use by queue_get (via environment variable)
	if [ "$test_result" = "SUCCESS" ]; then
		export "SSH_OS_${lssn}=${remote_os_info}"
	fi
	
	# Return exit code based on result
	case $test_result in
		SUCCESS) return 0 ;;
		FAILED) return 1 ;;
		SKIPPED) return 2 ;;
	esac
}

################################################################################
# Main Function
################################################################################

main() {
	local json_file="$1"
	
	# ============================================================================
	# Step 1: Validate LOG_DIR existence and write permission
	# ============================================================================
	if [ ! -d "$LOG_DIR" ]; then
		if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
			exit_with_error "Failed to create log directory: ${LOG_DIR}" 1
		fi
	fi
	
	if [ ! -w "$LOG_DIR" ]; then
		exit_with_error "No write permission for log directory: ${LOG_DIR}" 1
	fi
	
	# ============================================================================
	# Step 2: JSON file detection and validation
	# ============================================================================
	
	# Find or use specified JSON file
	if [ -z "$json_file" ]; then
		print_info "JSON file not specified, searching for latest gateway_servers_*.json..."
		
		# Find the latest gateway_servers_*.json file
		if ! command -v find &> /dev/null; then
			exit_with_error "find command not available" 1
		fi
		
		json_file=$(find /tmp -maxdepth 1 -name "gateway_servers_*.json" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
		
		if [ -z "$json_file" ]; then
			print_error "No gateway_servers_*.json file found in /tmp"
			echo ""
			print_info "Usage:"
			echo "  $0                                           # Auto-detect latest file"
			echo "  $0 /tmp/gateway_servers_12345.json          # Use specific file"
			echo ""
			print_warning "To generate gateway_servers_*.json file, run:"
			echo "  cd $(dirname "$SCRIPT_DIR")"
			echo "  ./giipAgent3.sh                              # In gateway mode"
			echo ""
			exit_with_error "No gateway_servers_*.json file found in /tmp" 1
		fi
		
		print_success "Found latest file: ${json_file}"
	fi
	
	# ============================================================================
	# Step 3: Validate specified JSON file
	# ============================================================================
	
	# Check file existence
	if [ ! -f "$json_file" ]; then
		exit_with_error "JSON file not found: ${json_file}" 1
	fi
	
	# Check file readability
	if [ ! -r "$json_file" ]; then
		exit_with_error "JSON file is not readable (permission denied): ${json_file}" 1
	fi
	
	# Check file is not empty
	if [ ! -s "$json_file" ]; then
		exit_with_error "JSON file is empty: ${json_file}" 1
	fi
	
	# Check file size (avoid extremely large files)
	local file_size=$(wc -c < "$json_file")
	if [ "$file_size" -gt 104857600 ]; then  # 100MB limit
		exit_with_error "JSON file is too large (${file_size} bytes, max 100MB): ${json_file}" 1
	fi
	
	# ============================================================================
	# Step 4: Validate JSON format
	# ============================================================================
	
	print_info "Validating JSON format..."
	
	# Try jq validation if available
	if command -v jq &> /dev/null; then
		if ! jq empty "$json_file" 2>/dev/null; then
			exit_with_error "JSON file is malformed (jq validation failed): ${json_file}" 1
		fi
		print_success "JSON format validation passed (using jq)"
	else
		# Basic validation using grep
		if ! grep -q '^[{[]' "$json_file"; then
			exit_with_error "JSON file does not start with { or [ (basic validation failed): ${json_file}" 1
		fi
		print_warning "JSON format validation passed (basic grep check only, jq not available)"
	fi
	
	# ============================================================================
	# Step 5: Validate JSON has server data
	# ============================================================================
	
	print_info "Checking for server data in JSON..."
	
	# Count potential servers
	local server_count=0
	if command -v jq &> /dev/null; then
		server_count=$(jq '[.data[]? // .[]? // .]? | length' "$json_file" 2>/dev/null || echo "0")
	else
		server_count=$(grep -o '{[^}]*}' "$json_file" | wc -l)
	fi
	
	if [ "$server_count" -eq 0 ]; then
		exit_with_error "No server data found in JSON file: ${json_file}" 1
	fi
	
	print_success "Found ${server_count} server(s) in JSON file"
	
	# ============================================================================
	# Step 6: Check required tools
	# ============================================================================
	
	print_info "Checking required tools..."
	
	if ! command -v curl &> /dev/null; then
		exit_with_error "Required tool 'curl' not found" 1
	fi
	
	if ! command -v ssh &> /dev/null; then
		exit_with_error "Required tool 'ssh' not found" 1
	fi
	
	if ! command -v timeout &> /dev/null; then
		exit_with_error "Required tool 'timeout' not found" 1
	fi
	
	# Check optional tools
	if ! command -v jq &> /dev/null; then
		print_warning "Optional tool 'jq' not found, will use grep fallback (slower)"
	fi
	
	if ! command -v sshpass &> /dev/null; then
		print_warning "Optional tool 'sshpass' not found, password authentication will be skipped"
	fi
	
	print_success "Tool check completed"
	
	# ============================================================================
	# Step 7: Initialize output files
	# ============================================================================
	
	# Clear old report file
	> "$REPORT_FILE"
	
	# Initialize JSON results file
	if ! echo "{\"test_start\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"source_file\":\"${json_file}\",\"servers\":[" > "$RESULT_JSON" 2>/dev/null; then
		exit_with_error "Failed to create JSON results file: ${RESULT_JSON}" 1
	fi
	
	# ============================================================================
	# Step 8: Display target servers and run SSH tests
	# ============================================================================
	
	# Display target servers using target_list module
	display_target_servers "$json_file" || exit_with_error "Failed to display target servers" 1
	
	print_info "🔄 Testing connection..."
	echo "═══════════════════════════════════════════════════════════════" | tee -a "$REPORT_FILE"
	echo ""
	
	# Parse JSON and extract servers
	local actual_server_count=0
	declare -a server_list
	
	# Try using jq first
	if command -v jq &> /dev/null; then
		# Extract to temp file first to preserve array in main shell
		local temp_servers="/tmp/servers_to_test_$$.jsonl"
		jq -c '.data[]? // .[]? // .' "$json_file" 2>/dev/null > "$temp_servers"
		
		while IFS= read -r server_json; do
			[ -z "$server_json" ] && continue
			server_list+=("$server_json")
		done < "$temp_servers"
		rm -f "$temp_servers"
		
		# Test connections
		for server_json in "${server_list[@]}"; do
			((TOTAL_SERVERS++))
			((actual_server_count++))
			
		# Extract parameters using jq
		local hostname=$(echo "$server_json" | jq -r '.hostname // empty' 2>/dev/null) || true
		local lssn=$(echo "$server_json" | jq -r '.lssn // empty' 2>/dev/null) || true
		local ssh_host=$(echo "$server_json" | jq -r '.ssh_host // empty' 2>/dev/null) || true
		local ssh_user=$(echo "$server_json" | jq -r '.ssh_user // empty' 2>/dev/null) || true
		local ssh_port=$(echo "$server_json" | jq -r '.ssh_port // 22' 2>/dev/null) || true
		local ssh_key_path=$(echo "$server_json" | jq -r '.ssh_key_path // empty' 2>/dev/null) || true
		local ssh_password=$(echo "$server_json" | jq -r '.ssh_password // empty' 2>/dev/null) || true
		
		# Test SSH connection
		test_ssh_connection "$hostname" "$ssh_host" "$ssh_user" "$ssh_port" "$ssh_key_path" "$ssh_password" "$lssn"
		local test_result=$?
		
		# Call queue_get on successful SSH connection (only if SSH test passed)
		if [ $test_result -eq 0 ]; then
			if declare -f queue_get &>/dev/null; then
				# Get OS information from environment variable set by test_ssh_connection
				local os_var_name="SSH_OS_${lssn}"
				local detected_os="${!os_var_name:-Linux}"
				
				local queue_file="/tmp/giip_queue_${lssn}_$$.sh"
				queue_get "$lssn" "$hostname" "$detected_os" "$queue_file"
				local queue_result=$?
				if [ $queue_result -eq 0 ]; then
					if [ -s "$queue_file" ]; then
						log_message "INFO" "Queue fetched for LSSN:$lssn ($(wc -c < "$queue_file") bytes)"
					fi
					rm -f "$queue_file"
				fi
			fi
		fi
	done
	else
		# Fallback: use grep for JSON parsing
		print_warning "jq not found, using grep fallback for JSON parsing"
		
		# Extract to temp file first to preserve array in main shell
		local temp_servers="/tmp/servers_to_test_$$.jsonl"
		tr -d '\n' < "$json_file" | sed 's/}/}\n/g' | grep -o '{[^}]*}' > "$temp_servers"
		
		while IFS= read -r server_json; do
			[ -z "$server_json" ] && continue
			server_list+=("$server_json")
		done < "$temp_servers"
		rm -f "$temp_servers"
		
		# Test connections
		for server_json in "${server_list[@]}"; do
			((TOTAL_SERVERS++))
			((actual_server_count++))
			
			# Extract parameters using grep fallback
			local hostname=$(echo "$server_json" | grep -o '"hostname"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/') || true
			local lssn=$(echo "$server_json" | grep -o '"lssn"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/') || true
			local ssh_host=$(echo "$server_json" | grep -o '"ssh_host"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/') || true
			local ssh_user=$(echo "$server_json" | grep -o '"ssh_user"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/') || true
			local ssh_port=$(echo "$server_json" | grep -o '"ssh_port"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/' || echo "22")
			local ssh_key_path=$(echo "$server_json" | grep -o '"ssh_key_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/') || true
			local ssh_password=$(echo "$server_json" | grep -o '"ssh_password"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/') || true
			
		test_ssh_connection "$hostname" "$ssh_host" "$ssh_user" "$ssh_port" "$ssh_key_path" "$ssh_password" "$lssn"
		local test_result=$?
		
		# Call queue_get on successful SSH connection (only if SSH test passed)
		if [ $test_result -eq 0 ]; then
			if declare -f queue_get &>/dev/null; then
				# Get OS information from environment variable set by test_ssh_connection
				local os_var_name="SSH_OS_${lssn}"
				local detected_os="${!os_var_name:-Linux}"
				
				local queue_file="/tmp/giip_queue_${lssn}_$$.sh"
				queue_get "$lssn" "$hostname" "$detected_os" "$queue_file"
				local queue_result=$?
				if [ $queue_result -eq 0 ]; then
					if [ -s "$queue_file" ]; then
						log_message "INFO" "Queue fetched for LSSN:$lssn ($(wc -c < "$queue_file") bytes)"
					fi
					rm -f "$queue_file"
				fi
			fi
		fi
	done
	# ============================================================================
	# Step 9: Finalize and summary
	# ============================================================================
	
	# Close JSON results file
	echo "]," >> "$RESULT_JSON"
	echo "\"test_end\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"summary\":{\"total\":${TOTAL_SERVERS},\"success\":${SUCCESS_COUNT},\"failed\":${FAILURE_COUNT},\"skipped\":${SKIPPED_COUNT},\"actual_processed\":${actual_server_count}}}" >> "$RESULT_JSON"
	
	# Print summary
	echo ""
	echo "═══════════════════════════════════════════════════════════════" | tee -a "$REPORT_FILE"
	print_success "✓ Test completed"
	echo "═══════════════════════════════════════════════════════════════" | tee -a "$REPORT_FILE"
	print_success "✓ Report: ${REPORT_FILE}"
	print_success "✓ Results: ${RESULT_JSON}"
	echo ""
}

################################################################################
# Script Entry Point
################################################################################

main "$@"
