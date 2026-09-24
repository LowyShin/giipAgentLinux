#!/bin/bash
################################################################################
# GIIP Agent Gateway Mode - Orchestrator
# Version: 2.0 (Refactored to orchestrator pattern)
# Date: 2025-12-04
# Purpose: Orchestrate gateway mode execution by calling independent scripts
# 
# Usage:
#   bash gateway_mode.sh                    # Auto-detect config
#   bash gateway_mode.sh /path/to/config    # Specify config file
#
# Architecture:
#   - gateway_mode.sh (this file) = Orchestrator
#   - gateway-fetch-servers.sh = Fetch remote server list
#   - gateway-ssh-test.sh = Execute SSH tests
#   - gateway/ssh_test.sh = Individual SSH test implementation
#
# Features:
#   - Standalone gateway mode execution
#   - Independent from giipAgent3.sh
#   - Modular architecture (all functionality in separate scripts)
#   - Maintains same logging and KVS integration
#
# Logging Points:
#   [3.0] Gateway Mode 시작
#   [3.1] 설정 로드 완료
#   [4.X] 리모트 서버 목록 조회 (gateway-fetch-servers.sh)
#   [5.X] SSH 테스트 실행 (gateway-ssh-test.sh)
################################################################################

# ============================================================================
# ⭐ UTF-8 환경 강제 설정 (최우선!)
# ============================================================================
# 목적: 일본어/한글 로케일 환경에서 Python 인라인 코드 파싱 에러 방지
# 이슈: CentOS 7.4 일본어 환경에서 멀티바이트 문자 깨짐 문제 해결
# 날짜: 2025-12-28
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# ============================================================================
# Initialize Script Paths
# ============================================================================

# Get parent directory (giipAgentLinux folder)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LIB_DIR="${SCRIPT_DIR}/lib"
CONFIG_FILE="${SCRIPT_DIR}/../giipAgent.cnf"

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

# 🔴 [로깅 포인트 #3.0] Gateway Mode 시작
echo "[gateway_mode.sh] 🟢 [3.0] Gateway Mode 시작: version=${sv}"

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
# Verify External Scripts
# ============================================================================

# Verify gateway-fetch-servers.sh exists
FETCH_SERVERS_SCRIPT="${SCRIPT_DIR}/scripts/gateway-fetch-servers.sh"
if [ ! -f "$FETCH_SERVERS_SCRIPT" ]; then
	log_message "ERROR" "Fetch servers script not found: $FETCH_SERVERS_SCRIPT"
	echo "❌ Error: Fetch servers script not found: $FETCH_SERVERS_SCRIPT" >&2
	exit 1
fi

# Verify gateway-ssh-test.sh exists
SSH_TEST_SCRIPT="${SCRIPT_DIR}/scripts/gateway-ssh-test.sh"
if [ ! -f "$SSH_TEST_SCRIPT" ]; then
	log_message "ERROR" "SSH test script not found: $SSH_TEST_SCRIPT"
	echo "❌ Error: SSH test script not found: $SSH_TEST_SCRIPT" >&2
	exit 1
fi

# ============================================================================
# Execute Gateway Mode
# ============================================================================

log_message "INFO" "Executing gateway mode orchestration..."

# 🔴 [로깅 포인트 #3.1] 설정 로드 완료
echo "[gateway_mode.sh] 🟢 [3.1] 설정 로드 완료: lssn=${lssn}, hostname=${hn}, os=${os}"

# Save startup to KVS
startup_details="{\"pid\":$$,\"config_file\":\"giipAgent.cnf\",\"api_endpoint\":\"${apiaddrv2}\",\"is_gateway\":1,\"mode\":\"gateway\",\"git_commit\":\"${GIT_COMMIT}\",\"file_modified\":\"${FILE_MODIFIED}\",\"script_path\":\"${BASH_SOURCE[0]}\"}"
save_execution_log "startup" "$startup_details"

# ============================================================================
# Step 1: Fetch Remote Servers
# ============================================================================

log_message "INFO" "[gateway_mode.sh] Calling gateway-fetch-servers.sh..."
echo "[gateway_mode.sh] Calling: bash '${FETCH_SERVERS_SCRIPT}' '${CONFIG_FILE}'"

bash "$FETCH_SERVERS_SCRIPT" "$CONFIG_FILE"
FETCH_EXIT_CODE=$?

if [ $FETCH_EXIT_CODE -ne 0 ]; then
	log_message "ERROR" "Failed to fetch remote servers (exit code: $FETCH_EXIT_CODE)"
	save_execution_log "shutdown" "{\"mode\":\"gateway\",\"status\":\"fetch_servers_failed\",\"exit_code\":${FETCH_EXIT_CODE}}"
	exit 1
fi

# ============================================================================
# Step 2: Run SSH Tests
# ============================================================================

log_message "INFO" "[gateway_mode.sh] Calling gateway-ssh-test.sh..."
echo "[gateway_mode.sh] Calling: bash '${SSH_TEST_SCRIPT}' '${CONFIG_FILE}'"

bash "$SSH_TEST_SCRIPT" "$CONFIG_FILE"
SSH_TEST_EXIT_CODE=$?

# SSH test can return non-zero but still continue (as per design)
log_message "INFO" "SSH tests completed with exit code: $SSH_TEST_EXIT_CODE"

# ============================================================================
# Step 3: Check Managed Databases
# ============================================================================

CHECK_DB_SCRIPT="${SCRIPT_DIR}/scripts/gateway-check-db.sh"
if [ -f "$CHECK_DB_SCRIPT" ]; then
	log_message "INFO" "[gateway_mode.sh] Calling gateway-check-db.sh..."
	echo "[gateway_mode.sh] Calling: bash '${CHECK_DB_SCRIPT}' '${CONFIG_FILE}'"
	
	bash "$CHECK_DB_SCRIPT" "$CONFIG_FILE"
	DB_CHECK_EXIT_CODE=$?
	
	log_message "INFO" "Database checks completed with exit code: $DB_CHECK_EXIT_CODE"
else
	log_message "WARN" "Database check script not found: $CHECK_DB_SCRIPT"
fi

# ============================================================================
# Shutdown
# ============================================================================

# Record execution shutdown log
save_execution_log "shutdown" "{\"mode\":\"gateway\",\"status\":\"gateway_exit\",\"exit_code\":${SSH_TEST_EXIT_CODE}}"

log_message "INFO" "GIIP Agent Gateway Mode V${sv} completed with exit code: ${SSH_TEST_EXIT_CODE}"

exit $SSH_TEST_EXIT_CODE
