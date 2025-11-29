#!/bin/bash
################################################################################
# GIIP Agent Gateway Mode - Standalone Script
# Version: 1.0
# Date: 2025-11-29
# Purpose: Execute gateway mode independently
# 
# Usage:
#   bash gateway_mode.sh                    # Auto-detect config
#   bash gateway_mode.sh /path/to/config    # Specify config file
#
# Features:
#   - Standalone gateway mode execution
#   - Independent from giipAgent3.sh
#   - SSH testing and remote server queue processing
#   - Maintains same logging and KVS integration
################################################################################

set -e  # Exit on error

# ============================================================================
# Initialize Script Paths
# ============================================================================

# Get parent directory (giipAgentLinux folder) - scripts/gateway_mode.sh → .. → giipAgentLinux
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LIB_DIR="${SCRIPT_DIR}/lib"
GATEWAY_DIR="${SCRIPT_DIR}/gateway"
CONFIG_FILE="${SCRIPT_DIR}/../giipAgent.cnf"

# DEBUG: Print paths before loading modules
echo "[DEBUG] SCRIPT_DIR: $SCRIPT_DIR"
echo "[DEBUG] LIB_DIR: $LIB_DIR"
echo "[DEBUG] GATEWAY_DIR: $GATEWAY_DIR"
echo "[DEBUG] CONFIG_FILE: $CONFIG_FILE"

# ============================================================================
# Load Library Modules
# ============================================================================

# Load common functions (config, logging, error handling)
if [ -f "${LIB_DIR}/common.sh" ]; then
	. "${LIB_DIR}/common.sh"
else
	echo "❌ Error: common.sh not found in ${LIB_DIR}"
	exit 1
fi

# Load KVS logging functions
if [ -f "${LIB_DIR}/kvs.sh" ]; then
	. "${LIB_DIR}/kvs.sh"
else
	echo "❌ Error: kvs.sh not found in ${LIB_DIR}"
	exit 1
fi

# Load gateway API functions
if [ -f "${LIB_DIR}/gateway_api.sh" ]; then
	. "${LIB_DIR}/gateway_api.sh"
else
	echo "❌ Error: gateway_api.sh not found in ${LIB_DIR}"
	exit 1
fi

# Load cleanup module
if [ -f "${LIB_DIR}/cleanup.sh" ]; then
	. "${LIB_DIR}/cleanup.sh"
else
	echo "❌ Error: cleanup.sh not found in ${LIB_DIR}"
	exit 1
fi

# ============================================================================
# Load Configuration
# ============================================================================

# Use provided config file or default
CONFIG_FILE="${1:-${CONFIG_FILE}}"

load_config "$CONFIG_FILE"
if [ $? -ne 0 ]; then
	echo "❌ Failed to load configuration from: $CONFIG_FILE"
	exit 1
fi

# ============================================================================
# Version and Metadata
# ============================================================================

sv="3.00"  # Version consistent with giipAgent3.sh

# Get Git commit hash (if available)
export GIT_COMMIT="unknown"
if command -v git >/dev/null 2>&1 && [ -d "${SCRIPT_DIR}/.git" ]; then
	GIT_COMMIT=$(git -C "${SCRIPT_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")
fi

# Get file modification date
export FILE_MODIFIED=$(stat -c %y "${BASH_SOURCE[0]}" 2>/dev/null || stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "${BASH_SOURCE[0]}" 2>/dev/null || echo "unknown")

echo "[gateway_mode.sh] 🟢 Starting GIIP Agent Gateway Mode"

# ============================================================================
# Initialize Logging
# ============================================================================

# Setup log directory
init_log_dir "$SCRIPT_DIR"

# Log startup
logdt=$(date '+%Y%m%d%H%M%S')
log_message "INFO" "========================================"
log_message "INFO" "Starting GIIP Agent Gateway Mode V${sv}"
log_message "INFO" "Config: ${CONFIG_FILE}"
log_message "INFO" "LSSN: ${lssn}"
log_message "INFO" "========================================"
log_message "INFO" "Git Commit: ${GIT_COMMIT}, File Modified: ${FILE_MODIFIED}"

# ============================================================================
# Detect System Information
# ============================================================================

# Detect OS
os=$(detect_os)
log_message "INFO" "Operating System: ${os}"

# Get hostname
hn=$(hostname)
log_message "INFO" "Hostname: ${hn}"

# ============================================================================
# Check Dependencies
# ============================================================================

check_dos2unix

# ============================================================================
# Gateway Mode Functions
# ============================================================================

# Function: Fetch remote servers from API
fetch_gateway_servers() {
	log_message "INFO" "Fetching remote server list from API..."
	
	local gateway_servers_file
	gateway_servers_file=$(get_gateway_servers)
	
	if [ $? -eq 0 ] && [ -f "$gateway_servers_file" ]; then
		log_message "INFO" "Remote server list saved to: $gateway_servers_file"
		echo "$gateway_servers_file"
		return 0
	else
		log_message "ERROR" "Failed to fetch remote server list from API"
		return 1
	fi
}

# Function: Execute SSH test script
run_ssh_tests() {
	local ssh_test_script="${GATEWAY_DIR}/ssh_test.sh"
	
	if [ ! -f "$ssh_test_script" ]; then
		log_message "ERROR" "SSH test script not found: $ssh_test_script"
		return 1
	fi
	
	log_message "INFO" "Calling gateway/ssh_test.sh..."
	
	# ⭐ RULE: All external scripts called with bash for independent execution
	if bash "$ssh_test_script"; then
		log_message "INFO" "SSH test script completed successfully"
		return 0
	else
		local ssh_test_exit_code=$?
		log_message "WARN" "SSH test script exited with code: $ssh_test_exit_code (continuing anyway)"
		return 0  # Don't fail - continue anyway
	fi
}

# ============================================================================
# Execute Gateway Mode
# ============================================================================

log_message "INFO" "Executing gateway mode..."

# Save startup to KVS
local startup_details="{\"pid\":$$,\"config_file\":\"giipAgent.cnf\",\"api_endpoint\":\"${apiaddrv2}\",\"is_gateway\":1,\"mode\":\"gateway\",\"git_commit\":\"${GIT_COMMIT}\",\"file_modified\":\"${FILE_MODIFIED}\",\"script_path\":\"${BASH_SOURCE[0]}\"}"
save_execution_log "startup" "$startup_details"

# Fetch remote servers
gateway_servers_file=$(fetch_gateway_servers)
if [ $? -ne 0 ]; then
	log_message "ERROR" "Failed to fetch gateway servers, aborting"
	exit 1
fi

# Run SSH tests
run_ssh_tests
GATEWAY_MODE_EXIT_CODE=$?

# ============================================================================
# Shutdown
# ============================================================================

# Record execution shutdown log
save_execution_log "shutdown" "{\"mode\":\"gateway\",\"status\":\"gateway_exit\",\"exit_code\":${GATEWAY_MODE_EXIT_CODE}}"

log_message "INFO" "GIIP Agent Gateway Mode V${sv} completed with exit code: ${GATEWAY_MODE_EXIT_CODE}"

exit $GATEWAY_MODE_EXIT_CODE
