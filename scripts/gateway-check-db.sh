#!/bin/bash
# Gateway Managed Database Check Script
# Wrapper for lib/check_managed_databases.sh
# Called by gateway_mode.sh

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LIB_DIR="${SCRIPT_DIR}/lib"
CONFIG_FILE="${1:-${SCRIPT_DIR}/../giipAgent.cnf}"

# Load Libraries
if [ -f "${LIB_DIR}/common.sh" ]; then . "${LIB_DIR}/common.sh"; else echo "❌ Error: common.sh not found"; exit 1; fi
if [ -f "${LIB_DIR}/kvs.sh" ]; then . "${LIB_DIR}/kvs.sh"; else echo "❌ Error: kvs.sh not found"; exit 1; fi
if [ -f "${LIB_DIR}/check_managed_databases.sh" ]; then . "${LIB_DIR}/check_managed_databases.sh"; else echo "❌ Error: check_managed_databases.sh not found"; exit 1; fi

# Load Config
load_config "$CONFIG_FILE"
if [ $? -ne 0 ]; then
    echo "❌ Failed to load configuration"
    exit 1
fi

# Init Log
init_log_dir "$SCRIPT_DIR"

log_message "INFO" "[gateway-check-db.sh] Starting Managed Database Check..."

# Execute Function from lib/check_managed_databases.sh
check_managed_databases
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    log_message "INFO" "[gateway-check-db.sh] Database check completed successfully"
else
    log_message "ERROR" "[gateway-check-db.sh] Database check failed with code $EXIT_CODE"
fi

exit $EXIT_CODE
