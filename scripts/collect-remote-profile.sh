#!/bin/bash
# ============================================================================
# GIIP Agent - Remote Server Profiling & KVS Upload Component
# Version: 1.0
# Purpose: Collect performance metrics from remote server via SSH and upload to KVS
# Usage: ./collect-remote-profile.sh <TARGET_IP> <TARGET_USER> <TARGET_LSSN> [SSH_KEY_PATH] [SSH_PASSWORD]
# Dependency: lib/common.sh, lib/kvs.sh (automatically loaded)
# ============================================================================

# Initialize Script Paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LIB_DIR="${SCRIPT_DIR}/lib"
CONFIG_FILE="${SCRIPT_DIR}/../giipAgent.cnf"

# Default Exit Code
EXIT_SUCCESS=0
EXIT_FAILURE=1

# ============================================================================
# 1. Parameter Validation
# ============================================================================

TARGET_HOST="$1"
TARGET_USER="$2"
TARGET_LSSN="$3"
SSH_KEY_PATH="$4"
SSH_PASSWORD="$5"

if [ -z "$TARGET_HOST" ] || [ -z "$TARGET_USER" ] || [ -z "$TARGET_LSSN" ]; then
    echo "Usage: $0 <TARGET_HOST> <TARGET_USER> <TARGET_LSSN> [SSH_KEY_PATH] [SSH_PASSWORD]"
    exit $EXIT_FAILURE
fi

# ============================================================================
# 2. Load Libraries & Configuration
# ============================================================================

# Load common library
if [ -f "${LIB_DIR}/common.sh" ]; then
    . "${LIB_DIR}/common.sh"
else
    echo "❌ Error: common.sh not found in ${LIB_DIR}"
    exit $EXIT_FAILURE
fi

# Load KVS library
if [ -f "${LIB_DIR}/kvs.sh" ]; then
    . "${LIB_DIR}/kvs.sh"
else
    echo "❌ Error: kvs.sh not found in ${LIB_DIR}"
    exit $EXIT_FAILURE
fi

# Load Config
load_config "$CONFIG_FILE"
if [ $? -ne 0 ]; then
    echo "❌ Failed to load configuration from $CONFIG_FILE"
    exit $EXIT_FAILURE
fi

# ============================================================================
# 3. Build SSH Command
# ============================================================================

SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 22"
SSH_CMD_BASE="ssh $SSH_OPTS"

# Remote Profiling Command (One-liner to output JSON)
# Retrieves: Load Average (1m), Memory Free (MB), Disk Usage (%) of root
REMOTE_CMD='
echo "{
  \"load_1min\": $(cat /proc/loadavg | awk "{print \$1}"),
  \"mem_free_mb\": $(free -m | grep Mem | awk "{print \$4}"),
  \"disk_usage_pct\": $(df -h / | tail -1 | awk "{print \$5}" | tr -d %),
  \"timestamp\": \"$(date "+%Y-%m-%d %H:%M:%S")\"
}" | tr -d "\n"
'
# Flatten command for safe passing
REMOTE_CMD=$(echo "$REMOTE_CMD" | tr -d '\n')

# Construct full command based on auth method
FULL_SSH_CMD=""

if [ -n "$SSH_KEY_PATH" ] && [ -f "$SSH_KEY_PATH" ]; then
    FULL_SSH_CMD="$SSH_CMD_BASE -i $SSH_KEY_PATH ${TARGET_USER}@${TARGET_HOST} '$REMOTE_CMD'"
elif [ -n "$SSH_PASSWORD" ] && command -v sshpass >/dev/null; then
    FULL_SSH_CMD="sshpass -p $SSH_PASSWORD $SSH_CMD_BASE ${TARGET_USER}@${TARGET_HOST} '$REMOTE_CMD'"
else
    # Fallback to default key or interactive (agent mode usually fails here if no key)
    FULL_SSH_CMD="$SSH_CMD_BASE ${TARGET_USER}@${TARGET_HOST} '$REMOTE_CMD'"
fi

# ============================================================================
# 4. Execute Remote Profiling
# ============================================================================

log_message "INFO" "Collecting profile from ${TARGET_HOST} (LSSN: ${TARGET_LSSN})..."

# Execute and capture output
PROFILE_DATA=$(eval "$FULL_SSH_CMD" 2>/dev/null)

# Check execution result
if [ $? -ne 0 ] || [ -z "$PROFILE_DATA" ]; then
    log_message "WARN" "Failed to collect profile from ${TARGET_HOST}. Check SSH connectivity."
    exit $EXIT_FAILURE
fi

# Validate JSON format (simple check)
if [[ ! "$PROFILE_DATA" =~ ^\{.*\}$ ]]; then
    log_message "WARN" "Invalid JSON data received from ${TARGET_HOST}: ${PROFILE_DATA}"
    exit $EXIT_FAILURE
fi

# Save to temp file (optional, for debugging or persistence)
TMP_FILE="/tmp/remote_profile_${TARGET_LSSN}_$(date +%Y%m%d).json"
echo "$PROFILE_DATA" > "$TMP_FILE"

log_message "INFO" "Profile collected: $PROFILE_DATA"

# ============================================================================
# 5. Upload to KVS (giipApiSk2)
# ============================================================================

# Mapping:
# kType = "lssn" (Standard for server metrics)
# kKey = TARGET_LSSN (The remote server's ID)
# kFactor = "remote_profile"
# kValue = The JSON data

kvs_put "lssn" "${TARGET_LSSN}" "remote_profile" "$PROFILE_DATA"

if [ $? -eq 0 ]; then
    log_message "INFO" "Successfully uploaded profile for LSSN ${TARGET_LSSN} to KVS."
    exit $EXIT_SUCCESS
else
    log_message "ERROR" "Failed to upload profile to KVS."
    exit $EXIT_FAILURE
fi
