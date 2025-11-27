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
#   - Tests each server with detailed logging
#   - Supports both password and key-based authentication
#   - Generates summary report
#   - Color-coded output for easy reading
################################################################################

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOG_DIR="/tmp/ssh_test_logs"
mkdir -p "$LOG_DIR"

REPORT_FILE="${LOG_DIR}/ssh_test_report_$(date +%Y%m%d_%H%M%S).txt"
RESULT_JSON="${LOG_DIR}/ssh_test_results_$(date +%Y%m%d_%H%M%S).json"

# Initialize counters
TOTAL_SERVERS=0
SUCCESS_COUNT=0
FAILURE_COUNT=0
SKIPPED_COUNT=0

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

# Print colored output
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
	local connection_time=0
	
	# Build SSH command
	local ssh_cmd="ssh"
	local ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
	
	print_info "Testing SSH connection to: ${hostname} (${ssh_host}:${ssh_port}) [LSSN:${lssn}]"
	
	# ========================================================================
	# EXCEPTION HANDLING: Parameter validation
	# ========================================================================
	
	# Validate hostname
	if [ -z "$hostname" ] || [ "$hostname" = "null" ]; then
		error_msg="hostname is empty or null"
		print_warning "Skipping: ${error_msg}"
		log_message "SKIP" "hostname empty | LSSN:${lssn}"
		echo "{\"hostname\":\"${hostname:-NONE}\",\"ssh_host\":\"${ssh_host:-NONE}\",\"lssn\":${lssn:-0},\"status\":\"SKIPPED\",\"error\":\"${error_msg}\"}" >> "$RESULT_JSON"
		((SKIPPED_COUNT++))
		return 2
	fi
	
	# Validate ssh_host (CRITICAL - cannot connect without this)
	if [ -z "$ssh_host" ] || [ "$ssh_host" = "null" ]; then
		error_msg="ssh_host is empty or null (cannot connect)"
		print_warning "Skipping: ${error_msg}"
		log_message "SKIP" "ssh_host empty | hostname:${hostname} | LSSN:${lssn}"
		echo "{\"hostname\":\"${hostname}\",\"ssh_host\":\"${ssh_host:-NONE}\",\"lssn\":${lssn},\"status\":\"SKIPPED\",\"error\":\"${error_msg}\"}" >> "$RESULT_JSON"
		((SKIPPED_COUNT++))
		return 2
	fi
	
	# Validate ssh_user (CRITICAL - cannot connect without this)
	if [ -z "$ssh_user" ] || [ "$ssh_user" = "null" ]; then
		error_msg="ssh_user is empty or null (cannot connect)"
		print_warning "Skipping: ${error_msg}"
		log_message "SKIP" "ssh_user empty | hostname:${hostname} | ssh_host:${ssh_host} | LSSN:${lssn}"
		echo "{\"hostname\":\"${hostname}\",\"ssh_host\":\"${ssh_host}\",\"ssh_user\":\"${ssh_user:-NONE}\",\"lssn\":${lssn},\"status\":\"SKIPPED\",\"error\":\"${error_msg}\"}" >> "$RESULT_JSON"
		((SKIPPED_COUNT++))
		return 2
	fi
	
	# Validate ssh_port is numeric
	if ! [[ "$ssh_port" =~ ^[0-9]+$ ]]; then
		print_warning "ssh_port is not numeric (${ssh_port}), using default 22"
		log_message "WARN" "Invalid port ${ssh_port}, using default 22 | hostname:${hostname}"
		ssh_port="22"
	fi
	
	# Validate ssh_port range
	if [ "$ssh_port" -lt 1 ] || [ "$ssh_port" -gt 65535 ]; then
		print_warning "ssh_port out of range (${ssh_port}), using default 22"
		log_message "WARN" "Port out of range ${ssh_port}, using default 22 | hostname:${hostname}"
		ssh_port="22"
	fi
	
	# Initialize results JSON file if needed
	if [ ! -f "$RESULT_JSON" ]; then
		echo "{\"test_start\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"servers\":[" > "$RESULT_JSON" 2>/dev/null || {
			print_error "Cannot write to results JSON file"
			return 1
		}
	fi
	
	# ========================================================================
	# Measure connection time
	# ========================================================================
	
	local start_time=$(date +%s.%N 2>/dev/null || date +%s)
	local ssh_succeeded=0
	
	# ========================================================================
	# Try SSH connection with different authentication methods
	# ========================================================================
	
	if [ -n "$ssh_key_path" ] && [ "$ssh_key_path" != "null" ]; then
		# Check if key file exists
		if [ -f "$ssh_key_path" ]; then
			print_info "Using key-based authentication: ${ssh_key_path}"
			log_message "AUTH" "key_based | file:${ssh_key_path}"
			
			# Check key file permissions
			local key_perms=$(stat -f '%OLp' "$ssh_key_path" 2>/dev/null || stat -c '%a' "$ssh_key_path" 2>/dev/null || echo "unknown")
			if [[ "$key_perms" != "600" && "$key_perms" != "unknown" ]]; then
				print_warning "SSH key file has non-standard permissions (${key_perms}), attempting anyway"
			fi
			
			# Attempt connection with key
			if timeout 15 $ssh_cmd $ssh_opts -i "$ssh_key_path" -p "$ssh_port" "${ssh_user}@${ssh_host}" "echo 'SSH connection successful' && hostname && uname -a" &>/dev/null; then
				test_result="SUCCESS"
				ssh_succeeded=1
				print_success "Connected successfully to ${hostname} (key auth)"
			else
				error_msg="SSH key authentication failed"
				print_error "${error_msg}"
			fi
		else
			print_warning "SSH key file not found: ${ssh_key_path}, trying alternative methods..."
			log_message "WARN" "key_file_not_found | path:${ssh_key_path}"
		fi
	fi
	
	# If key auth failed or not available, try password auth
	if [ "$ssh_succeeded" -eq 0 ] && [ -n "$ssh_password" ] && [ "$ssh_password" != "null" ]; then
		# Check if sshpass is available
		if ! command -v sshpass &> /dev/null; then
			print_warning "sshpass not found, cannot test password-based authentication"
			log_message "SKIP" "sshpass_not_installed | hostname:${hostname}"
			if [ -z "$error_msg" ]; then
				error_msg="sshpass not installed"
			fi
		else
			print_info "Using password-based authentication"
			log_message "AUTH" "password_based"
			
			# Attempt connection with password
			if timeout 15 sshpass -p "$ssh_password" $ssh_cmd $ssh_opts -p "$ssh_port" "${ssh_user}@${ssh_host}" "echo 'SSH connection successful' && hostname && uname -a" &>/dev/null; then
				test_result="SUCCESS"
				ssh_succeeded=1
				print_success "Connected successfully to ${hostname} (password auth)"
			else
				error_msg="SSH password authentication failed"
				print_error "${error_msg}"
			fi
		fi
	fi
	
	# If all methods failed or unavailable, try default SSH key
	if [ "$ssh_succeeded" -eq 0 ]; then
		print_info "Using default SSH key from ~/.ssh"
		log_message "AUTH" "default_key"
		
		if timeout 15 $ssh_cmd $ssh_opts -p "$ssh_port" "${ssh_user}@${ssh_host}" "echo 'SSH connection successful' && hostname && uname -a" &>/dev/null; then
			test_result="SUCCESS"
			ssh_succeeded=1
			print_success "Connected successfully to ${hostname} (default key)"
		else
			if [ -z "$error_msg" ]; then
				error_msg="SSH connection with default key failed"
			fi
			print_error "${error_msg}"
		fi
	fi
	
	# Final status assignment
	if [ "$ssh_succeeded" -eq 0 ]; then
		test_result="FAILED"
		if [ -z "$error_msg" ]; then
			error_msg="SSH connection failed (no available authentication methods)"
		fi
	fi
	
	# ========================================================================
	# Calculate connection time
	# ========================================================================
	
	local end_time=$(date +%s.%N 2>/dev/null || date +%s)
	
	if command -v bc &> /dev/null; then
		connection_time=$(echo "${end_time} - ${start_time}" | bc 2>/dev/null || echo "0")
	else
		# Fallback: calculate in bash
		connection_time=$(echo "scale=3; ${end_time%.*} - ${start_time%.*}" | awk '{print $1}' 2>/dev/null || echo "0")
	fi
	
	# ========================================================================
	# Log and record results
	# ========================================================================
	
	log_message "SSH_TEST" "${test_result} | hostname:${hostname} | ${ssh_host}:${ssh_port} | user:${ssh_user} | LSSN:${lssn} | Time:${connection_time}s"
	
	# Append to JSON results (with comma handling)
	local json_entry="{\"hostname\":\"${hostname}\",\"ssh_host\":\"${ssh_host}\",\"ssh_user\":\"${ssh_user}\",\"ssh_port\":${ssh_port},\"lssn\":${lssn},\"status\":\"${test_result}\",\"connection_time_sec\":${connection_time},\"error\":\"${error_msg}\"}"
	
	# Remove trailing comma from previous entry if needed
	if [ -f "$RESULT_JSON" ]; then
		local last_line=$(tail -1 "$RESULT_JSON" 2>/dev/null)
		if [[ "$last_line" == *"}" ]]; then
			# Add comma to previous entry if it doesn't end with comma
			if [[ ! "$last_line" == *"}," ]]; then
				sed -i '$ s/}$/},/' "$RESULT_JSON" 2>/dev/null || echo "Note: Could not add comma to previous entry"
			fi
		fi
	fi
	
	echo "$json_entry" >> "$RESULT_JSON" 2>/dev/null || {
		print_error "Failed to write to results JSON file"
		return 1
	}
	
	# ========================================================================
	# Update counters
	# ========================================================================
	
	case $test_result in
		SUCCESS)
			((SUCCESS_COUNT++))
			return 0
			;;
		FAILED)
			((FAILURE_COUNT++))
			return 1
			;;
		SKIPPED)
			((SKIPPED_COUNT++))
			return 2
			;;
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
	
	print_info "Initializing output files..."
	
	# Clear old report file
	> "$REPORT_FILE"
	
	# Initialize JSON results file
	if ! echo "{\"test_start\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"source_file\":\"${json_file}\",\"servers\":[" > "$RESULT_JSON" 2>/dev/null; then
		exit_with_error "Failed to create JSON results file: ${RESULT_JSON}" 1
	fi
	
	print_success "Output files initialized"
	echo "  Report: ${REPORT_FILE}"
	echo "  Results: ${RESULT_JSON}"
	echo ""
	
	# ============================================================================
	# Step 8: Run SSH tests
	# ============================================================================
	
	print_success "Starting SSH connection tests from: ${json_file}"
	print_info "Report file: ${REPORT_FILE}"
	print_info "Results JSON: ${RESULT_JSON}"
	echo ""
	
	log_message "START" "SSH Connection Test Started"
	log_message "INFO" "Source file: ${json_file}"
	log_message "INFO" "File size: ${file_size} bytes"
	log_message "INFO" "Server count: ${server_count}"
	echo "═══════════════════════════════════════════════════════════════" | tee -a "$REPORT_FILE"
	
	# Parse JSON and extract servers
	local actual_server_count=0
	
	# Try using jq first
	if command -v jq &> /dev/null; then
		print_info "Using jq for JSON parsing"
		
		# Extract array of servers
		while IFS= read -r server_json; do
			[ -z "$server_json" ] && continue
			
			((TOTAL_SERVERS++))
			((actual_server_count++))
			
			# Extract parameters using jq
			local hostname=$(echo "$server_json" | jq -r '.hostname // empty' 2>/dev/null)
			local lssn=$(echo "$server_json" | jq -r '.lssn // empty' 2>/dev/null)
			local ssh_host=$(echo "$server_json" | jq -r '.ssh_host // empty' 2>/dev/null)
			local ssh_user=$(echo "$server_json" | jq -r '.ssh_user // empty' 2>/dev/null)
			local ssh_port=$(echo "$server_json" | jq -r '.ssh_port // 22' 2>/dev/null)
			local ssh_key_path=$(echo "$server_json" | jq -r '.ssh_key_path // empty' 2>/dev/null)
			local ssh_password=$(echo "$server_json" | jq -r '.ssh_password // empty' 2>/dev/null)
			
			echo ""
			test_ssh_connection "$hostname" "$ssh_host" "$ssh_user" "$ssh_port" "$ssh_key_path" "$ssh_password" "$lssn"
			
		done < <(jq -c '.data[]? // .[]? // .' "$json_file" 2>/dev/null)
	else
		# Fallback: use grep for JSON parsing
		print_warning "jq not found, using grep fallback for JSON parsing"
		
		# Normalize JSON and extract objects
		while IFS= read -r server_json; do
			[ -z "$server_json" ] && continue
			
			((TOTAL_SERVERS++))
			((actual_server_count++))
			
			# Extract parameters using grep fallback
			local hostname=$(echo "$server_json" | grep -o '"hostname"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			local lssn=$(echo "$server_json" | grep -o '"lssn"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
			local ssh_host=$(echo "$server_json" | grep -o '"ssh_host"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			local ssh_user=$(echo "$server_json" | grep -o '"ssh_user"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			local ssh_port=$(echo "$server_json" | grep -o '"ssh_port"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/' || echo "22")
			local ssh_key_path=$(echo "$server_json" | grep -o '"ssh_key_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			local ssh_password=$(echo "$server_json" | grep -o '"ssh_password"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			
			echo ""
			test_ssh_connection "$hostname" "$ssh_host" "$ssh_user" "$ssh_port" "$ssh_key_path" "$ssh_password" "$lssn"
			
		done < <(tr -d '\n' < "$json_file" | sed 's/}/}\n/g' | grep -o '{[^}]*}')
	fi
	
	# ============================================================================
	# Step 9: Finalize and summary
	# ============================================================================
	
	# Close JSON results file
	echo "]," >> "$RESULT_JSON"
	echo "\"test_end\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"summary\":{\"total\":${TOTAL_SERVERS},\"success\":${SUCCESS_COUNT},\"failed\":${FAILURE_COUNT},\"skipped\":${SKIPPED_COUNT},\"actual_processed\":${actual_server_count}}}" >> "$RESULT_JSON"
	
	# Print summary
	echo ""
	echo "═══════════════════════════════════════════════════════════════" | tee -a "$REPORT_FILE"
	echo "" | tee -a "$REPORT_FILE"
	print_info "Test Summary"
	log_message "SUMMARY" "Total servers: ${TOTAL_SERVERS}"
	log_message "SUMMARY" "Successfully connected: ${SUCCESS_COUNT}"
	log_message "SUMMARY" "Connection failed: ${FAILURE_COUNT}"
	log_message "SUMMARY" "Skipped: ${SKIPPED_COUNT}"
	log_message "SUMMARY" "Actually processed: ${actual_server_count}"
	log_message "END" "SSH Connection Test Completed"
	
	echo ""
	print_success "Report saved to: ${REPORT_FILE}"
	print_success "JSON results saved to: ${RESULT_JSON}"
	
	# Print JSON results file content for quick review
	echo ""
	print_info "JSON Results Preview:"
	
	if command -v jq &> /dev/null; then
		cat "$RESULT_JSON" | jq . 2>/dev/null || cat "$RESULT_JSON"
	else
		cat "$RESULT_JSON"
	fi
}

################################################################################
# Script Entry Point
################################################################################

main "$@"
