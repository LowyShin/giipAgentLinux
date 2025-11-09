#!/bin/bash
#
# SYNOPSIS:
#   Test script for giipAgent2.sh KVS logging functionality
#
# USAGE:
#   ./test-kvs-logging.sh
#
# DESCRIPTION:
#   Tests save_execution_log function by sending various event types to KVS
#   Checks if data is properly saved with kFactor="giipagent"
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/log/test-kvs-logging_$(date +%Y%m%d).log"
mkdir -p "${SCRIPT_DIR}/log"

echo "===============================================" | tee -a "$LOG_FILE"
echo "KVS Logging Test - $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
echo "===============================================" | tee -a "$LOG_FILE"

# Load config
CFG_PATH="${SCRIPT_DIR}/giipAgent.cnf"
if [ ! -f "$CFG_PATH" ]; then
    echo "[ERROR] Config file not found: $CFG_PATH" | tee -a "$LOG_FILE"
    exit 1
fi

echo "[INFO] Loading config from: $CFG_PATH" | tee -a "$LOG_FILE"

# Source config
source "$CFG_PATH"

# Verify required variables
if [ -z "$sk" ] || [ -z "$lssn" ] || [ -z "$apiaddrv2" ]; then
    echo "[ERROR] Missing required config: sk, lssn, or apiaddrv2" | tee -a "$LOG_FILE"
    exit 1
fi

echo "[INFO] Config loaded successfully" | tee -a "$LOG_FILE"
echo "       LSSN: $lssn" | tee -a "$LOG_FILE"
echo "       API: $apiaddrv2" | tee -a "$LOG_FILE"

# Create temp directory for test data
TMP_DIR="${SCRIPT_DIR}/tmp"
mkdir -p "$TMP_DIR"

# Test 1: Agent startup event
echo "" | tee -a "$LOG_FILE"
echo "=== Test 1: Agent Startup Event ===" | tee -a "$LOG_FILE"

cat > "$TMP_DIR/test_startup.json" << EOF
{
  "event_type": "startup",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "lssn": ${lssn},
  "hostname": "$(hostname)",
  "mode": "normal",
  "version": "2.00",
  "details": {
    "pid": $$,
    "config_file": "giipAgent.cnf",
    "api_endpoint": "${apiaddrv2}",
    "test": true
  }
}
EOF

echo "[INFO] Sending startup event to KVS..." | tee -a "$LOG_FILE"
if bash "${SCRIPT_DIR}/giipscripts/kvsput.sh" "$TMP_DIR/test_startup.json" "giipagent" 2>&1 | tee -a "$LOG_FILE"; then
    echo "[SUCCESS] Startup event sent" | tee -a "$LOG_FILE"
else
    echo "[FAILED] Startup event failed" | tee -a "$LOG_FILE"
fi

sleep 1

# Test 2: Queue check event (no queue)
echo "" | tee -a "$LOG_FILE"
echo "=== Test 2: Queue Check Event (404) ===" | tee -a "$LOG_FILE"

cat > "$TMP_DIR/test_queue_check.json" << EOF
{
  "event_type": "queue_check",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "lssn": ${lssn},
  "hostname": "$(hostname)",
  "mode": "normal",
  "version": "2.00",
  "details": {
    "api_response": "404",
    "has_queue": false,
    "mssn": 0,
    "script_source": "none",
    "test": true
  }
}
EOF

echo "[INFO] Sending queue check event to KVS..." | tee -a "$LOG_FILE"
if bash "${SCRIPT_DIR}/giipscripts/kvsput.sh" "$TMP_DIR/test_queue_check.json" "giipagent" 2>&1 | tee -a "$LOG_FILE"; then
    echo "[SUCCESS] Queue check event sent" | tee -a "$LOG_FILE"
else
    echo "[FAILED] Queue check event failed" | tee -a "$LOG_FILE"
fi

sleep 1

# Test 3: Script execution event
echo "" | tee -a "$LOG_FILE"
echo "=== Test 3: Script Execution Event ===" | tee -a "$LOG_FILE"

cat > "$TMP_DIR/test_script_execution.json" << EOF
{
  "event_type": "script_execution",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "lssn": ${lssn},
  "hostname": "$(hostname)",
  "mode": "normal",
  "version": "2.00",
  "details": {
    "script_type": "bash",
    "exit_code": 0,
    "execution_time_seconds": 3,
    "test": true
  }
}
EOF

echo "[INFO] Sending script execution event to KVS..." | tee -a "$LOG_FILE"
if bash "${SCRIPT_DIR}/giipscripts/kvsput.sh" "$TMP_DIR/test_script_execution.json" "giipagent" 2>&1 | tee -a "$LOG_FILE"; then
    echo "[SUCCESS] Script execution event sent" | tee -a "$LOG_FILE"
else
    echo "[FAILED] Script execution event failed" | tee -a "$LOG_FILE"
fi

sleep 1

# Test 4: Error event
echo "" | tee -a "$LOG_FILE"
echo "=== Test 4: Error Event ===" | tee -a "$LOG_FILE"

cat > "$TMP_DIR/test_error.json" << EOF
{
  "event_type": "error",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "lssn": ${lssn},
  "hostname": "$(hostname)",
  "mode": "normal",
  "version": "2.00",
  "details": {
    "error_type": "api_error",
    "error_message": "Test error for KVS logging validation",
    "error_code": 500,
    "context": "test_suite",
    "test": true
  }
}
EOF

echo "[INFO] Sending error event to KVS..." | tee -a "$LOG_FILE"
if bash "${SCRIPT_DIR}/giipscripts/kvsput.sh" "$TMP_DIR/test_error.json" "giipagent" 2>&1 | tee -a "$LOG_FILE"; then
    echo "[SUCCESS] Error event sent" | tee -a "$LOG_FILE"
else
    echo "[FAILED] Error event failed" | tee -a "$LOG_FILE"
fi

sleep 1

# Test 5: Shutdown event
echo "" | tee -a "$LOG_FILE"
echo "=== Test 5: Shutdown Event ===" | tee -a "$LOG_FILE"

cat > "$TMP_DIR/test_shutdown.json" << EOF
{
  "event_type": "shutdown",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "lssn": ${lssn},
  "hostname": "$(hostname)",
  "mode": "normal",
  "version": "2.00",
  "details": {
    "reason": "normal",
    "process_count": 999,
    "uptime_seconds": 0,
    "test": true
  }
}
EOF

echo "[INFO] Sending shutdown event to KVS..." | tee -a "$LOG_FILE"
if bash "${SCRIPT_DIR}/giipscripts/kvsput.sh" "$TMP_DIR/test_shutdown.json" "giipagent" 2>&1 | tee -a "$LOG_FILE"; then
    echo "[SUCCESS] Shutdown event sent" | tee -a "$LOG_FILE"
else
    echo "[FAILED] Shutdown event failed" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "===============================================" | tee -a "$LOG_FILE"
echo "Test completed!" | tee -a "$LOG_FILE"
echo "===============================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "📊 Next steps:" | tee -a "$LOG_FILE"
echo "1. Check if data was saved:" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "   SQL Query:" | tee -a "$LOG_FILE"
echo "   SELECT TOP 10" | tee -a "$LOG_FILE"
echo "       kRegdt," | tee -a "$LOG_FILE"
echo "       JSON_VALUE(kValue, '\$.event_type') AS event_type," | tee -a "$LOG_FILE"
echo "       JSON_VALUE(kValue, '\$.timestamp') AS timestamp," | tee -a "$LOG_FILE"
echo "       JSON_VALUE(kValue, '\$.details.test') AS is_test," | tee -a "$LOG_FILE"
echo "       kValue" | tee -a "$LOG_FILE"
echo "   FROM tKVS" | tee -a "$LOG_FILE"
echo "   WHERE kType = 'lssn'" | tee -a "$LOG_FILE"
echo "     AND kKey = '${lssn}'" | tee -a "$LOG_FILE"
echo "     AND kFactor = 'giipagent'" | tee -a "$LOG_FILE"
echo "     AND JSON_VALUE(kValue, '\$.details.test') = 'true'" | tee -a "$LOG_FILE"
echo "   ORDER BY kRegdt DESC" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "2. If no data found, check ErrorLogs:" | tee -a "$LOG_FILE"
echo "   - Source: giipApi" | tee -a "$LOG_FILE"
echo "   - Search: KVSPut, giipagent" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "3. Log file: $LOG_FILE" | tee -a "$LOG_FILE"

# Cleanup temp files
rm -f "$TMP_DIR/test_"*.json

echo "" | tee -a "$LOG_FILE"
echo "✅ Test data cleaned up" | tee -a "$LOG_FILE"
