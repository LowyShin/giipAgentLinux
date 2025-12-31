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

# ============================================================================
# ⭐ UTF-8 환경 강제 설정 (최우선!)
# ============================================================================
# 목적: 일본어/한글 로케일 환경에서 Python 인라인 코드 파싱 에러 방지
# 이슈: CentOS 7.4 일본어 환경에서 멀티바이트 문자 깨짐 문제 해결
# 날짜: 2025-12-28
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8


# set -e  # Removed to prevent early exit on optional module failures (e.g. Discovery, Net3D)


# ============================================================================
# Self-Cleanup / Singleton Logic (Emergency Add)
# ============================================================================
SCRIPT_ABS_PATH=$(readlink -f "${BASH_SOURCE[0]}")
CURRENT_PID=$$

# Relaxed Singleton Pattern: Kill only hung/stale processes (>5 minutes old)
while IFS= read -r other_pid; do
    if [ -n "$other_pid" ] && [ "$other_pid" != "$CURRENT_PID" ]; then
        elapsed_seconds=$(ps -o etimes= -p "$other_pid" 2>/dev/null | tr -d ' ')
        if [ -n "$elapsed_seconds" ] && [ "$elapsed_seconds" -gt 300 ]; then
            echo "⚠️  [$(date)] Killing hung process (PID=$other_pid, runtime=${elapsed_seconds}s > 5min)"
            kill -9 "$other_pid" 2>/dev/null
        fi
    fi
done < <(pgrep -f "bash $SCRIPT_ABS_PATH" | grep -v "^$CURRENT_PID$")

# ============================================================================
# Initialize Script Paths
# ============================================================================

# Get parent directory (giipAgentLinux folder) - scripts/normal_mode.sh → .. → giipAgentLinux
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LIB_DIR="${SCRIPT_DIR}/lib"
CONFIG_FILE="${SCRIPT_DIR}/../giipAgent.cnf"

# DEBUG: Print paths before loading modules
echo "[DEBUG] SCRIPT_DIR: $SCRIPT_DIR"
echo "[DEBUG] LIB_DIR: $LIB_DIR"
echo "[DEBUG] CONFIG_FILE: $CONFIG_FILE"
echo "[DEBUG] common.sh path: ${LIB_DIR}/common.sh"

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

# Load CQE queue functions
if [ -f "${LIB_DIR}/cqe.sh" ]; then
	. "${LIB_DIR}/cqe.sh"
else
	echo "❌ Error: cqe.sh not found in ${LIB_DIR}"
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

# ============================================================================
# Early Cleanup: Remove old GIIP temporary files
# ============================================================================
# Note: Cleanup is handled by caller (giipAgent3.sh) when needed
# Skipped here to avoid unnecessary operations

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

# Load Net3D module (Network Topology)
# Runs every 5 minutes to collect netstat/ss data
if [ -f "${LIB_DIR}/net3d.sh" ]; then
	. "${LIB_DIR}/net3d.sh"
	
	collect_net3d_data "${lssn}"
fi

# Load MSSQL Monitoring module
# Runs periodically (default 1 min) to collect SQL performance data
if [ -f "${LIB_DIR}/mssql.sh" ]; then
	. "${LIB_DIR}/mssql.sh"
	
	collect_mssql_data "${lssn}"
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
