#!/bin/bash
################################################################################
# GIIP Agent Gateway - Fetch Remote Servers
# Version: 1.0
# Date: 2025-12-04
# Purpose: Fetch remote server list from API (independent script)
# 
# Usage:
#   bash scripts/gateway-fetch-servers.sh [/path/to/config]
#
# Output:
#   - Returns path to gateway_servers_*.json file on stdout
#   - Returns 0 on success, 1 on failure
#
# Features:
#   - Standalone execution
#   - Independent from gateway_mode.sh
#   - API call to GatewayRemoteServerListForAgent
#   - KVS logging
################################################################################

# ============================================================================
# Initialize Script Paths
# ============================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LIB_DIR="${SCRIPT_DIR}/lib"
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

# Load gateway API functions
if [ -f "${LIB_DIR}/gateway_api.sh" ]; then
	. "${LIB_DIR}/gateway_api.sh"
else
	echo "❌ Error: gateway_api.sh not found in ${LIB_DIR}"
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
# Fetch Remote Servers
# ============================================================================

log_message "INFO" "[gateway-fetch-servers.sh] 🟢 Starting remote server fetch"
log_message "INFO" "LSSN: ${lssn}, API: ${apiaddrv2}"

# 🔴 [로깅 포인트 #4.1] 리모트 서버 목록 조회 시작
echo "[gateway-fetch-servers.sh] 🟢 [4.1] 리모트 서버 목록 조회 시작: lssn=${lssn}, api=${apiaddrv2}" >&2

# Call get_gateway_servers() from gateway_api.sh
gateway_servers_file=$(get_gateway_servers)
if [ $? -eq 0 ] && [ -f "$gateway_servers_file" ]; then
	# 🔴 [로깅 포인트 #4.2] 리모트 서버 목록 조회 성공
	echo "[gateway-fetch-servers.sh] 🟢 [4.2] 리모트 서버 목록 조회 성공: file=${gateway_servers_file}" >&2
	log_message "INFO" "Remote server list saved to: $gateway_servers_file"
	
	# KVS logging
	kvs_put "lssn" "${lssn}" "gateway_fetch_servers_success" "{\"file\":\"${gateway_servers_file}\",\"status\":\"success\"}"
	
	# Output the file path to stdout
	echo "$gateway_servers_file"
	exit 0
else
	# 🔴 [로깅 포인트 #4.3] 리모트 서버 목록 조회 실패
	echo "[gateway-fetch-servers.sh] ❌ [4.3] 리모트 서버 목록 조회 실패: lssn=${lssn}, error='API call failed'" >&2
	log_message "ERROR" "Failed to fetch remote server list from API"
	
	# KVS logging
	kvs_put "lssn" "${lssn}" "gateway_fetch_servers_failed" "{\"error\":\"API call failed\",\"status\":\"failure\"}"
	
	exit 1
fi
