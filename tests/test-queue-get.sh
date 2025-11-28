#!/bin/bash
################################################################################
# Test script for queue_get function
# Purpose: Test CQE queue fetching functionality
# Author: Generated Script
# Version: 1.0
# Date: 2025-11-28
#
# Usage:
#   ./test-queue-get.sh [lssn] [hostname] [os]
#   ./test-queue-get.sh 12345 "server1" "Linux"
#   ./test-queue-get.sh  # Uses default values
#
# Environment Variables Required:
#   sk: Session key/token for API authentication
#   apiaddrv2: API endpoint URL (CQEQueueGet service)
#   apiaddrcode: Optional API code parameter
################################################################################

set -o pipefail

# Script configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
LIB_DIR="${PARENT_DIR}/lib"

# 🔴 IMPORTANT: Config file path - same as giipAgent3.sh
# giipAgent3.sh uses: "../giipAgent.cnf" (relative to giipAgent3.sh location)
# tests/ is sibling of giipAgentLinux/, so we need to go up to find it
# From tests/test-queue-get.sh → ../giipAgent.cnf (go to giipAgentLinux folder)
CONFIG_FILE="${SCRIPT_DIR}/../giipAgent.cnf"

# Fallback: also check parent directory
if [ ! -f "$CONFIG_FILE" ]; then
	CONFIG_FILE="${PARENT_DIR}/../giipAgent.cnf"
fi

# Load configuration from giipAgent.cnf
if [ -f "$CONFIG_FILE" ]; then
	. "$CONFIG_FILE"
	# 🔴 CRITICAL: Export variables for child processes (wrapper script)
	# Without export, new bash processes won't have access to these variables
	export sk apiaddrv2 apiaddrcode lssn
else
	echo "❌ Config file not found at: ${SCRIPT_DIR}/../giipAgent.cnf or ${PARENT_DIR}/../giipAgent.cnf"
	exit 1
fi

# Test output directory
TEST_OUTPUT_DIR="/tmp/queue_get_test_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TEST_OUTPUT_DIR"

# Test parameters (can be overridden by command line arguments)
# If lssn not provided and config loaded, use lssn from config
if [ -z "$1" ]; then
	TEST_LSSN="${lssn:-12345}"
else
	TEST_LSSN="$1"
fi

TEST_HOSTNAME="${2:-test-server}"
TEST_OS="${3:-Linux}"
TEST_OUTPUT_FILE="${TEST_OUTPUT_DIR}/queue_output.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
	echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
	echo -e "${BLUE}$1${NC}"
	echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
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

print_info() {
	echo -e "${BLUE}ℹ️  $1${NC}"
}

# ============================================================================
# Validation Functions
# ============================================================================

validate_environment() {
	print_header "Step 1: Environment Check"
	
	local errors=0
	
	# Quick checks - minimal output
	[ ! -f "$CONFIG_FILE" ] && print_warning "[env] Config file not found: $CONFIG_FILE" || print_success "[env] Config file loaded"
	[ ! -f "${LIB_DIR}/cqe.sh" ] && { print_error "[env] cqe.sh not found"; ((errors++)); } || print_success "[env] cqe.sh found"
	! command -v curl &> /dev/null && { print_error "[env] curl not found"; ((errors++)); } || print_success "[env] curl found"
	! command -v jq &> /dev/null && print_warning "[env] jq not found (grep fallback will be used)" || print_success "[env] jq found"
	
	[ -z "$sk" ] && { print_error "[env] sk not set"; ((errors++)); } || print_success "[env] sk: ${#sk} chars"
	[ -z "$apiaddrv2" ] && { print_error "[env] apiaddrv2 not set"; ((errors++)); } || print_success "[env] apiaddrv2: ${apiaddrv2:0:40}..."
	
	echo ""
	[ $errors -gt 0 ] && return 1
	print_success "[env] ✅ Environment OK"
	return 0
}

# ============================================================================
# Test Functions
# ============================================================================

test_queue_get() {
	print_header "Step 2: Running queue_get"
	
	echo "  LSSN: $TEST_LSSN | Host: $TEST_HOSTNAME | OS: $TEST_OS"
	echo "  Output: $TEST_OUTPUT_FILE"
	echo ""
	
	# Create temporary wrapper script to avoid function scope issues
	local wrapper_script="/tmp/queue_wrapper_$$.sh"
	cat > "$wrapper_script" << 'WRAPPER_EOF'
#!/bin/bash
LIB_DIR="$1"
CONFIG_FILE="$2"
TEST_LSSN="$3"
TEST_HOSTNAME="$4"
TEST_OS="$5"
TEST_OUTPUT_FILE="$6"

# Load config file first (same as how giipAgent3.sh does it)
if [ -f "$CONFIG_FILE" ]; then
	. "$CONFIG_FILE" || { echo "[wrapper] Failed to load config"; exit 1; }
else
	echo "[wrapper] Config file not found: $CONFIG_FILE" >&2
	exit 1
fi

# Verify required variables are available BEFORE loading modules
if [ -z "$sk" ] || [ -z "$apiaddrv2" ]; then
	echo "[wrapper] ❌ FAILED: sk or apiaddrv2 not loaded from config" >&2
	echo "[wrapper] DEBUG: sk='$sk' apiaddrv2='$apiaddrv2'" >&2
	exit 1
fi

# Load common module
[ -f "${LIB_DIR}/common.sh" ] && . "${LIB_DIR}/common.sh" 2>/dev/null || true

# Load CQE module with functions
. "${LIB_DIR}/cqe.sh" || { echo "[wrapper] Failed to load cqe.sh"; exit 1; }

# Call queue_get
queue_get "$TEST_LSSN" "$TEST_HOSTNAME" "$TEST_OS" "$TEST_OUTPUT_FILE"
exit $?
WRAPPER_EOF
	
	# Execute wrapper with timeout, capturing stdout and stderr separately
	local timestamp=$(date +%s%N)
	local stdout_file="/tmp/queue_out_$${timestamp}_$$.log"
	local stderr_file="/tmp/queue_err_$${timestamp}_$$.log"
	
	timeout 30 bash "$wrapper_script" "$LIB_DIR" "$CONFIG_FILE" "$TEST_LSSN" "$TEST_HOSTNAME" "$TEST_OS" "$TEST_OUTPUT_FILE" > "$stdout_file" 2> "$stderr_file"
	local exit_code=$?
	
	# Handle timeout vs other errors
	if [ $exit_code -eq 124 ]; then
		echo "[error] queue_get timeout: exceeded 30 second limit" >&2
		rm -f "$wrapper_script" "$stdout_file" "$stderr_file"
		return 1
	elif [ $exit_code -ne 0 ]; then
		echo "[error] queue_get failed with exit code $exit_code" >&2
		if [ -s "$stderr_file" ]; then
			cat "$stderr_file" | sed 's/^/  [stderr] /' >&2
		fi
		if [ -s "$stdout_file" ]; then
			cat "$stdout_file" | sed 's/^/  [stdout] /' >&2
		fi
		rm -f "$wrapper_script" "$stdout_file" "$stderr_file"
		return 1
	fi
	
	# Set secure permissions on output file
	if [ -f "$TEST_OUTPUT_FILE" ]; then
		chmod 600 "$TEST_OUTPUT_FILE" 2>/dev/null
	fi
	
	rm -f "$wrapper_script" "$stdout_file" "$stderr_file"
	return 0
}

# ============================================================================
# Result Validation Functions
# ============================================================================

validate_results() {
	print_header "Step 3: Results"
	
	local errors=0
	
	# Check if output file was created
	if [ ! -f "${TEST_OUTPUT_FILE}" ]; then
		print_error "[validation] Output file not created"
		((errors++))
	else
		if [ -s "${TEST_OUTPUT_FILE}" ]; then
			local file_size=$(wc -c < "${TEST_OUTPUT_FILE}")
			print_success "[validation] Output file created (${file_size} bytes)"
			
			# Show first 200 chars
			echo ""
			echo "  Content preview:"
			head -c 200 "${TEST_OUTPUT_FILE}" | sed 's/^/    /'
			if [ $file_size -gt 200 ]; then
				echo "    ... ($(($file_size - 200)) more bytes)"
			fi
			echo ""
		else
			print_error "[validation] Output file is empty"
			((errors++))
		fi
	fi
	
	[ $errors -gt 0 ] && return 1
	return 0
}

# ============================================================================
# Report Generation
# ============================================================================

# Simplified report (if needed for debugging)
report_detail() {
	cat > "${TEST_OUTPUT_DIR}/test_report_detailed.txt" << EOF
Queue Get Test Detailed Report
Generated: $(date '+%Y-%m-%d %H:%M:%S')

Test Parameters:
- LSSN: ${TEST_LSSN}
- Hostname: ${TEST_HOSTNAME}
- OS: ${TEST_OS}

API Configuration:
- Endpoint: ${apiaddrv2}
- Code: ${apiaddrcode}

Output: ${TEST_OUTPUT_FILE}

Test artifacts:
EOF
	ls -lah "${TEST_OUTPUT_DIR}" >> "${TEST_OUTPUT_DIR}/test_report_detailed.txt" 2>/dev/null || true
}

# ============================================================================
# Helper Functions (coloring)
# ============================================================================

main() {
	print_header "Queue Get Test"
	echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
	echo ""
	
	# Step 1: Validate environment
	if ! validate_environment; then
		print_error "[main] Environment check failed"
		exit 1
	fi
	
	echo ""
	
	# Step 2: Test queue_get function
	if test_queue_get; then
		print_success "[main] ✅ queue_get executed"
		queue_get_exit_code=0
	else
		queue_get_exit_code=$?
		print_error "[main] ❌ queue_get failed (exit code: $queue_get_exit_code)"
		
		# Show debug info on failure
		echo ""
		print_header "Debug Info"
		echo "  API: ${apiaddrv2}${apiaddrcode:+?code=}${apiaddrcode}"
		echo "  Params: LSSN=$TEST_LSSN, Host=$TEST_HOSTNAME, OS=$TEST_OS"
		echo ""
	fi
	
	echo ""
	
	# Step 3: Validate results
	validate_results
	validation_exit_code=$?
	
	echo ""
	
	# Save minimal report
	local report_file="${TEST_OUTPUT_DIR}/test_report.txt"
	cat > "$report_file" << EOF
Queue Get Test Report
Generated: $(date '+%Y-%m-%d %H:%M:%S')

Parameters: LSSN=$TEST_LSSN, Host=$TEST_HOSTNAME, OS=$TEST_OS
Output: ${TEST_OUTPUT_FILE}
Status: $([ $queue_get_exit_code -eq 0 ] && echo "SUCCESS" || echo "FAILED")
EOF
	
	# Clear sensitive variables after use (security cleanup)
	unset sk apiaddrv2 apiaddrcode
	
	print_header "Summary"
	if [ $queue_get_exit_code -eq 0 ] && [ $validation_exit_code -eq 0 ]; then
		print_success "[main] ✅ TEST PASSED"
		echo ""
		echo "  Queue fetched successfully"
		echo "  Output: $TEST_OUTPUT_FILE"
		exit 0
	else
		print_error "[main] ❌ TEST FAILED"
		echo ""
		echo "  queue_get: $queue_get_exit_code"
		echo "  validation: $validation_exit_code"
		echo "  Report: $report_file"
		exit 1
	fi
}

################################################################################
# Script Entry Point
################################################################################

main "$@"
