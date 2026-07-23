#!/bin/bash
#
# SYNOPSIS:
#   Run giipAgent2.sh and upload execution results to KVS
#
# USAGE:
#   ./run-agent2-with-kvs.sh
#
# DESCRIPTION:
#   - Executes giipAgent2.sh
#   - Captures stdout/stderr output
#   - Creates JSON result file
#   - Uploads to KVS using kvsput.sh
#

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Config file
CONFIG_FILE="${SCRIPT_DIR}/giipAgent.cnf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[ERROR] Config file not found: $CONFIG_FILE"
    exit 1
fi

# Read config for lssn and hostname
source "$CONFIG_FILE" 2>/dev/null || true
lssn="${lssn:-$(hostname)}"
hn="${hn:-$(hostname)}"

# Output files
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${SCRIPT_DIR}/log"
mkdir -p "$LOG_DIR"

OUTPUT_FILE="${LOG_DIR}/giipAgent2_run_${TIMESTAMP}.log"
JSON_FILE="${LOG_DIR}/giipAgent2_result_${TIMESTAMP}.json"

echo "=========================================="
echo "giipAgent2.sh Execution with KVS Upload"
echo "=========================================="
echo ""
echo "Server: ${hn} (lssn: ${lssn})"
echo "Timestamp: ${TIMESTAMP}"
echo "Output log: ${OUTPUT_FILE}"
echo "Result JSON: ${JSON_FILE}"
echo ""
echo "--- Starting giipAgent2.sh ---"
echo ""

# Run giipAgent2.sh and capture output
start_time=$(date +%s)
set +e
bash "${SCRIPT_DIR}/giipAgent2.sh" > "${OUTPUT_FILE}" 2>&1
exit_code=$?
set -e
end_time=$(date +%s)
duration=$((end_time - start_time))

echo ""
echo "--- Execution completed ---"
echo "Exit code: ${exit_code}"
echo "Duration: ${duration}s"
echo ""

# Display output
echo "--- Output (last 50 lines) ---"
tail -50 "${OUTPUT_FILE}"
echo ""
echo "--- End of output ---"
echo ""

# Parse output for key information
cqe_attempts=$(grep -c "\[CQE\]" "${OUTPUT_FILE}" 2>/dev/null || echo "0")
cqe_success=$(grep -c "✅" "${OUTPUT_FILE}" 2>/dev/null || echo "0")
cqe_errors=$(grep -c "❌" "${OUTPUT_FILE}" 2>/dev/null || echo "0")
cqe_no_queue=$(grep -c "No queue available" "${OUTPUT_FILE}" 2>/dev/null || echo "0")

# Extract API URL if present
api_url=$(grep -o "https://[^[:space:]]*" "${OUTPUT_FILE}" 2>/dev/null | head -1 || echo "N/A")

# Create JSON result
cat > "${JSON_FILE}" << EOF
{
  "execution": {
    "timestamp": "${TIMESTAMP}",
    "start_time": ${start_time},
    "end_time": ${end_time},
    "duration_seconds": ${duration},
    "exit_code": ${exit_code},
    "status": "$([ ${exit_code} -eq 0 ] && echo "success" || echo "failed")"
  },
  "server": {
    "lssn": "${lssn}",
    "hostname": "${hn}",
    "os": "$(uname -s)",
    "os_version": "$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"' || uname -r)"
  },
  "cqe_stats": {
    "total_attempts": ${cqe_attempts},
    "success_count": ${cqe_success},
    "error_count": ${cqe_errors},
    "no_queue_count": ${cqe_no_queue}
  },
  "api_info": {
    "url": "${api_url}",
    "version": "giipApiSk2"
  },
  "output": {
    "log_file": "${OUTPUT_FILE}",
    "line_count": $(wc -l < "${OUTPUT_FILE}"),
    "size_bytes": $(wc -c < "${OUTPUT_FILE}"),
    "sample": $(tail -10 "${OUTPUT_FILE}" | jq -Rs .)
  }
}
EOF

echo "✅ JSON result created: ${JSON_FILE}"
echo ""
cat "${JSON_FILE}" | jq .
echo ""

# Upload to KVS
KVSPUT_SCRIPT="${SCRIPT_DIR}/giipscripts/kvsput.sh"
if [ -f "$KVSPUT_SCRIPT" ]; then
    echo "--- Uploading to KVS ---"
    echo ""
    
    # kFactor format: agent2_run (indicates giipAgent2.sh execution)
    KFACTOR="agent2_run"
    
    echo "Executing: CONFIG_FILE=${CONFIG_FILE} bash ${KVSPUT_SCRIPT} ${JSON_FILE} ${KFACTOR}"
    echo ""
    echo "📋 KVS Upload Configuration:"
    echo "  - kType: lssn (fixed)"
    echo "  - kKey: ${lssn} (from giipAgent.cnf)"
    echo "  - kFactor: ${KFACTOR}"
    echo "  - kValue: <JSON data from file>"
    echo ""
    echo "📖 Specification: docs/KVSPUT_API_SPECIFICATION.md"
    echo ""
    
    if CONFIG_FILE="${CONFIG_FILE}" bash "${KVSPUT_SCRIPT}" "${JSON_FILE}" "${KFACTOR}"; then
        echo ""
        echo "✅ Successfully uploaded to KVS"
        echo ""
        echo "🔍 Verify upload:"
        echo "  Web UI: https://giip.littleworld.net/ko/kvslist?kKey=${lssn}&kFactor=${KFACTOR}"
        echo "  SQL: SELECT * FROM tKVS WHERE kKey='${lssn}' AND kFactor='${KFACTOR}' ORDER BY kRegdt DESC"
    else
        echo ""
        echo "⚠️  KVS upload failed (see above for details)"
        exit_code=1
    fi
else
    echo "⚠️  kvsput.sh not found, skipping KVS upload"
    echo "Expected location: ${KVSPUT_SCRIPT}"
fi

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Exit code: ${exit_code}"
echo "Duration: ${duration}s"
echo "CQE attempts: ${cqe_attempts}"
echo "CQE success: ${cqe_success}"
echo "CQE errors: ${cqe_errors}"
echo "Output log: ${OUTPUT_FILE}"
echo "Result JSON: ${JSON_FILE}"
echo ""

exit ${exit_code}
