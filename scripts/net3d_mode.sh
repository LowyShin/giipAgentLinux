#!/bin/bash
################################################################################
# Net3D Mode Script
# Purpose: Network topology data collection (external script)
# Called by: giipAgent3.sh
# Usage: bash net3d_mode.sh /path/to/giipAgent.cnf
################################################################################

# ============================================================================
# UTF-8 환경 설정
# ============================================================================
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# ============================================================================
# Initialize Script Paths
# ============================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LIB_DIR="${SCRIPT_DIR}/lib"
CONFIG_FILE="${1:-${SCRIPT_DIR}/../giipAgent.cnf}"

# ============================================================================
# Load Library Modules
# ============================================================================

# Load common functions
if [ -f "${LIB_DIR}/common.sh" ]; then
    . "${LIB_DIR}/common.sh"
else
    echo "❌ Error: common.sh not found"
    exit 1
fi

# Load KVS functions
if [ -f "${LIB_DIR}/kvs.sh" ]; then
    . "${LIB_DIR}/kvs.sh"
else
    log_message "ERROR" "kvs.sh not found"
    exit 1
fi

# Load Net3D module
if [ -f "${LIB_DIR}/net3d.sh" ]; then
    . "${LIB_DIR}/net3d.sh"
else
    log_message "ERROR" "net3d.sh not found"
    exit 1
fi

# ============================================================================
# Load Configuration
# ============================================================================

load_config "$CONFIG_FILE"
if [ $? -ne 0 ]; then
    log_message "ERROR" "Failed to load configuration"
    exit 1
fi

# ============================================================================
# Execute Net3D Collection
# ============================================================================

log_message "INFO" "[Net3D Mode] Starting network topology data collection"

# Run Net3D collection
collect_net3d_data "${lssn}"
NET3D_EXIT_CODE=$?

if [ $NET3D_EXIT_CODE -eq 0 ]; then
    log_message "INFO" "[Net3D Mode] Network topology data collection completed successfully"
else
    log_message "WARN" "[Net3D Mode] Network topology data collection completed with warnings (exit code: $NET3D_EXIT_CODE)"
fi

exit $NET3D_EXIT_CODE
