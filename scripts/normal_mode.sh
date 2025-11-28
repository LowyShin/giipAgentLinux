#!/bin/bash
################################################################################
# GIIP Agent Normal Mode - Standalone Script
# Version: 1.0
# Date: 2025-11-28
# Purpose: Execute normal mode independently without gateway mode
# 
# Usage:
#   bash normal_mode.sh                    # Auto-detect config
#   bash normal_mode.sh /path/to/config    # Specify config file
#
# Features:
#   - Standalone normal mode execution
#   - Independent from giipAgent3.sh
#   - Can be called from cron, systemd, or manually
#   - Maintains same logging and KVS integration
################################################################################

set -e  # Exit on error

# ============================================================================
# Initialize Script Paths
# ============================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="${SCRIPT_DIR}/../lib"

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
CONFIG_FILE="${1:-../giipAgent.cnf}"

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

# ============================================================================
# Early Cleanup: Remove old GIIP temporary files
# ============================================================================

cleanup_all_temp_files
echo ""

echo "[normal_mode.sh] 🟢 Starting GIIP Agent Normal Mode"

# ============================================================================
# Initialize Logging
# ============================================================================

# Setup log directory
init_log_dir "$SCRIPT_DIR"

# Log startup
logdt=$(date '+%Y%m%d%H%M%S')
log_message "INFO" "========================================"
log_message "INFO" "Starting GIIP Agent Normal Mode V${sv}"
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
# Load Optional Modules
# ============================================================================

# Load discovery module (safe integration with error handling)
if [ -f "${LIB_DIR}/discovery.sh" ]; then
	. "${LIB_DIR}/discovery.sh"
	
	# Run discovery if needed (6시간 주기)
	if collect_infrastructure_data "${lssn}"; then
		log_message "INFO" "Discovery completed successfully"
	else
		log_message "WARN" "Discovery failed but continuing"
	fi
fi

# ============================================================================
# Load Normal Mode Functions
# ============================================================================

if [ -f "${LIB_DIR}/normal.sh" ]; then
	. "${LIB_DIR}/normal.sh"
else
	log_message "ERROR" "normal.sh not found"
	exit 1
fi

# ============================================================================
# Execute Normal Mode
# ============================================================================

log_message "INFO" "Executing normal mode..."

# Run normal mode
run_normal_mode "$lssn" "$hn" "$os"
NORMAL_MODE_EXIT_CODE=$?

# ============================================================================
# Shutdown
# ============================================================================

# Record execution shutdown log
save_execution_log "shutdown" "{\"mode\":\"normal\",\"status\":\"normal_exit\",\"exit_code\":${NORMAL_MODE_EXIT_CODE}}"

log_message "INFO" "GIIP Agent Normal Mode V${sv} completed with exit code: ${NORMAL_MODE_EXIT_CODE}"

exit $NORMAL_MODE_EXIT_CODE
