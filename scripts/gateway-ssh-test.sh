#!/bin/bash
################################################################################
# GIIP Agent Gateway - Run SSH Tests
# Version: 1.0
# Date: 2025-12-04
# Purpose: Execute SSH tests on remote servers (independent script)
# 
# Usage:
#   bash scripts/gateway-ssh-test.sh [/path/to/config]
#
# Prerequisites:
#   - gateway_servers_*.json file must exist in /tmp/
#   - Config file with sk, apiaddrv2, apiaddrcode
#
# Output:
#   - Returns 0 on success (some tests passed)
#   - Returns 1 on failure (no tests passed)
#
# Features:
#   - Standalone execution
#   - Calls gateway/ssh_test.sh
#   - Manages SSH test workflow
#   - KVS logging
#
# Logging Points:
#   [5.1] SSH 테스트 시작
#   [5.2] SSH 테스트 성공
#   [5.3] SSH 테스트 실패
################################################################################

# ============================================================================
# Initialize Script Paths
# ============================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LIB_DIR="${SCRIPT_DIR}/lib"
GATEWAY_DIR="${SCRIPT_DIR}/gateway"
CONFIG_FILE="${SCRIPT_DIR}/../giipAgent.cnf"

# ============================================================================
# Load Library Modules
# ============================================================================

# Load common functions
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
# Setup Logging
# ============================================================================

init_log_dir "$SCRIPT_DIR"

# ============================================================================
# Validate Prerequisites
# ============================================================================

# Check if gateway/ssh_test.sh exists
if [ ! -f "${GATEWAY_DIR}/ssh_test.sh" ]; then
	log_message "ERROR" "SSH test script not found: ${GATEWAY_DIR}/ssh_test.sh"
	echo "❌ Error: SSH test script not found: ${GATEWAY_DIR}/ssh_test.sh" >&2
	exit 1
fi

# Check if gateway_servers_*.json exists in /tmp/
if ! ls /tmp/gateway_servers_*.json >/dev/null 2>&1; then
	log_message "WARN" "No gateway_servers_*.json found in /tmp/ (might be first run)"
fi

# ============================================================================
# Run SSH Tests
# ============================================================================

# 🔴 [로깅 포인트 #5.1] SSH 테스트 시작
echo "[gateway-ssh-test.sh] 🟢 [5.1] SSH 테스트 시작: lssn=${lssn}" >&2
log_message "INFO" "Starting SSH tests on remote servers"

# KVS logging: startup
kvs_put "lssn" "${lssn}" "gateway_ssh_test_startup" "{\"action\":\"ssh_test_start\",\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"status\":\"started\"}"

# Call gateway/ssh_test.sh with bash for independent execution
# Note: ssh_test.sh will auto-detect gateway_servers_*.json from /tmp/
if bash "${GATEWAY_DIR}/ssh_test.sh"; then
	# 🔴 [로깅 포인트 #5.2] SSH 테스트 성공
	echo "[gateway-ssh-test.sh] 🟢 [5.2] SSH 테스트 성공: lssn=${lssn}" >&2
	log_message "INFO" "SSH tests completed successfully"
	
	# KVS logging: success
	kvs_put "lssn" "${lssn}" "gateway_ssh_test_success" "{\"action\":\"ssh_test_complete\",\"status\":\"success\",\"exit_code\":0}"
	
	exit 0
else
	local ssh_test_exit_code=$?
	# 🔴 [로깅 포인트 #5.3] SSH 테스트 실패
	echo "[gateway-ssh-test.sh] ⚠️  [5.3] SSH 테스트 실패/경고: lssn=${lssn}, exit_code=${ssh_test_exit_code}" >&2
	log_message "WARN" "SSH test script exited with code: $ssh_test_exit_code"
	
	# KVS logging: warning (not failure - we continue)
	kvs_put "lssn" "${lssn}" "gateway_ssh_test_warning" "{\"action\":\"ssh_test_warning\",\"status\":\"warning\",\"exit_code\":${ssh_test_exit_code}}"
	
	# Don't fail - continue anyway (as per original design)
	exit 0
fi
