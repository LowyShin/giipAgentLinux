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
CONFIG_FILE="${PARENT_DIR}/../giipAgent.cnf"

# Load configuration from giipAgent.cnf
if [ -f "$CONFIG_FILE" ]; then
	. "$CONFIG_FILE"
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
	print_header "Step 1: Validating Environment"
	
	local errors=0
	
	# Check configuration file
	if [ ! -f "$CONFIG_FILE" ]; then
		print_warning "Configuration file not found: $CONFIG_FILE"
		print_info "Trying to use environment variables instead"
	else
		print_success "Found configuration file: $CONFIG_FILE"
	fi
	
	echo ""
	
	# Check required libraries
	if [ ! -f "${LIB_DIR}/cqe.sh" ]; then
		print_error "cqe.sh not found in ${LIB_DIR}"
		((errors++))
	else
		print_success "Found cqe.sh"
	fi
	
	# Check required tools
	if ! command -v curl &> /dev/null; then
		print_error "curl not found"
		((errors++))
	else
		print_success "Found curl"
	fi
	
	if ! command -v jq &> /dev/null; then
		print_warning "jq not found (will use grep fallback)"
	else
		print_success "Found jq"
	fi
	
	if ! command -v sed &> /dev/null; then
		print_error "sed not found"
		((errors++))
	else
		print_success "Found sed"
	fi
	
	echo ""
	
	# Check API environment variables
	if [ -z "$sk" ]; then
		print_error "sk variable not set (API session key)"
		((errors++))
	else
		print_success "sk variable is set (length: ${#sk})"
	fi
	
	if [ -z "$apiaddrv2" ]; then
		print_error "apiaddrv2 variable not set (API endpoint URL)"
		((errors++))
	else
		print_success "apiaddrv2 is set: ${apiaddrv2:0:60}..."
	fi
	
	if [ -n "$apiaddrcode" ]; then
		print_success "apiaddrcode is set: ${apiaddrcode:0:20}..."
	else
		print_info "apiaddrcode not set (optional)"
	fi
	
	echo ""
	
	if [ $errors -gt 0 ]; then
		print_error "Environment validation failed with $errors error(s)"
		echo ""
		print_info "💡 How to fix:"
		echo "   1. Make sure giipAgent.cnf exists in parent directory"
		echo "   2. Or set environment variables:"
		echo "      export sk='your_session_key'"
		echo "      export apiaddrv2='https://api.example.com/endpoint'"
		echo "      export apiaddrcode='optional_code'"
		echo ""
		return 1
	fi
	
	print_success "Environment validation passed"
	return 0
}

# ============================================================================
# Test Functions
# ============================================================================

test_queue_get() {
	print_header "Step 2: Testing queue_get Function"
	
	# Load cqe module
	if ! . "${LIB_DIR}/cqe.sh"; then
		print_error "Failed to load cqe.sh"
		return 1
	fi
	print_success "Loaded cqe.sh module"
	
	# Display test parameters
	echo ""
	print_info "Test Parameters:"
	echo "  LSSN: ${TEST_LSSN}"
	echo "  Hostname: ${TEST_HOSTNAME}"
	echo "  OS: ${TEST_OS}"
	echo "  Output File: ${TEST_OUTPUT_FILE}"
	echo ""
	
	# Call queue_get function
	print_info "Calling queue_get function..."
	echo "  Command: queue_get \"${TEST_LSSN}\" \"${TEST_HOSTNAME}\" \"${TEST_OS}\" \"${TEST_OUTPUT_FILE}\""
	echo ""
	
	# Execute queue_get with timeout (30 seconds)
	timeout 30 queue_get "${TEST_LSSN}" "${TEST_HOSTNAME}" "${TEST_OS}" "${TEST_OUTPUT_FILE}"
	local exit_code=$?
	
	return $exit_code
}

# ============================================================================
# Result Validation Functions
# ============================================================================

validate_results() {
	print_header "Step 3: Validating Results"
	
	local errors=0
	
	# Check if output file was created
	if [ ! -f "${TEST_OUTPUT_FILE}" ]; then
		print_error "Output file not created: ${TEST_OUTPUT_FILE}"
		((errors++))
	else
		print_success "Output file created"
		
		# Check if file is not empty
		if [ -s "${TEST_OUTPUT_FILE}" ]; then
			print_success "Output file is not empty"
			
			# Get file size
			local file_size=$(wc -c < "${TEST_OUTPUT_FILE}")
			print_info "Output file size: ${file_size} bytes"
			
			# Display first 500 characters
			echo ""
			print_info "Output file contents (first 500 characters):"
			echo "---"
			head -c 500 "${TEST_OUTPUT_FILE}"
			echo ""
			echo "---"
			echo ""
		else
			print_error "Output file is empty"
			((errors++))
		fi
	fi
	
	# Check for shell script indicators
	if [ -f "${TEST_OUTPUT_FILE}" ] && [ -s "${TEST_OUTPUT_FILE}" ]; then
		if grep -q "#!/bin/bash\|#!/bin/sh\|^#\|^\s*[a-zA-Z_]" "${TEST_OUTPUT_FILE}"; then
			print_success "Output file appears to contain shell script content"
		else
			print_warning "Output file may not contain valid shell script"
		fi
	fi
	
	if [ $errors -gt 0 ]; then
		print_error "Result validation failed with $errors error(s)"
		return 1
	fi
	
	print_success "Result validation passed"
	return 0
}

# ============================================================================
# Report Generation
# ============================================================================

generate_report() {
	print_header "Test Report"
	
	echo ""
	echo "Test Results:"
	echo "  Test Time: $(date '+%Y-%m-%d %H:%M:%S')"
	echo "  LSSN: ${TEST_LSSN}"
	echo "  Hostname: ${TEST_HOSTNAME}"
	echo "  OS: ${TEST_OS}"
	echo ""
	
	echo "API Configuration:"
	echo "  API Endpoint: ${apiaddrv2:0:50}..."
	[ -n "$apiaddrcode" ] && echo "  API Code: ${apiaddrcode:0:20}..."
	echo "  Session Key: ${sk:0:20}..."
	echo ""
	
	echo "Output Files:"
	echo "  Test Output Directory: ${TEST_OUTPUT_DIR}"
	echo "  Queue Output File: ${TEST_OUTPUT_FILE}"
	if [ -f "${TEST_OUTPUT_FILE}" ]; then
		echo "  File Size: $(wc -c < "${TEST_OUTPUT_FILE}") bytes"
		echo "  File Status: ✅ Exists and readable"
	else
		echo "  File Status: ❌ Not created"
	fi
	echo ""
	
	# Save report to file
	local report_file="${TEST_OUTPUT_DIR}/test_report.txt"
	cat > "$report_file" << EOF
Queue Get Test Report
Generated: $(date '+%Y-%m-%d %H:%M:%S')

Test Parameters:
- LSSN: ${TEST_LSSN}
- Hostname: ${TEST_HOSTNAME}
- OS: ${TEST_OS}

API Configuration:
- Endpoint: ${apiaddrv2}
- Code: ${apiaddrcode}

Output Directory: ${TEST_OUTPUT_DIR}
Output File: ${TEST_OUTPUT_FILE}

Test artifacts:
EOF
	
	if [ -d "${TEST_OUTPUT_DIR}" ]; then
		ls -lah "${TEST_OUTPUT_DIR}" >> "$report_file"
	fi
	
	print_success "Report saved to: ${report_file}"
}

# ============================================================================
# Cleanup Functions
# ============================================================================

cleanup() {
	print_header "Cleanup"
	
	# Optional: Remove old temp files (older than 24 hours)
	print_info "Cleaning up old temporary files..."
	find /tmp -name "queue_response_*" -type f -mtime +1 -delete 2>/dev/null
	find /tmp -name "queue_get_test_*" -type d -mtime +1 -exec rm -rf {} \; 2>/dev/null
	
	print_success "Cleanup completed"
	print_info "Test output directory: ${TEST_OUTPUT_DIR}"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
	print_header "Queue Get Function Test Suite"
	echo "Version: 1.0"
	echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
	echo ""
	
	# Step 1: Validate environment
	if ! validate_environment; then
		print_error "Environment validation failed. Exiting."
		exit 1
	fi
	
	echo ""
	
	# Step 2: Test queue_get function
	if test_queue_get; then
		print_success "queue_get function executed successfully"
		queue_get_exit_code=0
	else
		queue_get_exit_code=$?
		print_error "queue_get function failed with exit code: $queue_get_exit_code"
	fi
	
	echo ""
	
	# Step 3: Validate results
	validate_results
	validation_exit_code=$?
	
	echo ""
	
	# Step 4: Generate report
	generate_report
	
	echo ""
	
	# Step 5: Cleanup
	cleanup
	
	echo ""
	print_header "Test Execution Summary"
	echo ""
	
	if [ $queue_get_exit_code -eq 0 ] && [ $validation_exit_code -eq 0 ]; then
		print_success "✅ ALL TESTS PASSED"
		echo ""
		print_info "Queue was successfully fetched from API"
		print_info "Output saved to: ${TEST_OUTPUT_FILE}"
		exit 0
	else
		print_error "❌ SOME TESTS FAILED"
		echo ""
		print_info "queue_get exit code: $queue_get_exit_code"
		print_info "validation exit code: $validation_exit_code"
		echo ""
		print_warning "Check the output above for details"
		exit 1
	fi
}

################################################################################
# Script Entry Point
################################################################################

main "$@"
