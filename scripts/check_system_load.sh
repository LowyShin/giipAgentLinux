#!/bin/bash
# -----------------------------------------------------------------------------
# giipAgentLinux - System Load & Performance Monitor
# Created: 2026-01-24
# Description: Checks for high CPU usage, total process count, and specific
#              stuck processes (jq, curl). Reports to tKVS.
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Load KVS functions
if [ -f "${LIB_DIR}/kvs.sh" ]; then
    . "${LIB_DIR}/kvs.sh"
else
    echo "❌ Error: kvs.sh not found" >&2
    exit 1
fi

# Load config to get LSSN
if [ -f "${SCRIPT_DIR}/../../giipAgent.cnf" ]; then
    source "${SCRIPT_DIR}/../../giipAgent.cnf"
else
    # Fallback/Try to load normally if source fails
    lssn=$(grep 'lssn=' "${SCRIPT_DIR}/../../giipAgent.cnf" | cut -d'"' -f2 || echo "0")
fi

# 1. Check Total Process Count
PROC_COUNT=$(ps -e | wc -l)

# 2. Check Specific Process Counts (jq, curl)
JQ_COUNT=$(pgrep -x jq | wc -l || echo "0")
CURL_COUNT=$(pgrep -x curl | wc -l || echo "0")

# 3. Check CPU Usage (1-minute load average)
LOAD_AVG=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1 | tr -d ' ')

# 4. Logical Alert Conditions
ALERT_TRIGGERED=0
ALERT_MSG=""

if [ "$PROC_COUNT" -gt 500 ]; then
    ALERT_TRIGGERED=1
    ALERT_MSG="${ALERT_MSG} High process count: ${PROC_COUNT}."
fi

if [ "$JQ_COUNT" -gt 20 ] || [ "$CURL_COUNT" -gt 20 ]; then
    ALERT_TRIGGERED=1
    ALERT_MSG="${ALERT_MSG} High jq/curl count: jq=${JQ_COUNT}, curl=${CURL_COUNT}."
fi

# 5. Report to tKVS if triggered
if [ "$ALERT_TRIGGERED" -eq 1 ]; then
    echo "⚠️  [$(date)] Performance Alert: $ALERT_MSG"
    
    JSON_DATA=$(jq -n \
        --arg lssn "$lssn" \
        --arg ts "$(date '+%Y-%m-%d %H:%M:%S')" \
        --arg cpu "$(get_cpu_usage)" \
        --arg mem "$(get_mem_usage)" \
        --arg load "$LOAD_AVG" \
        --arg proc "$PROC_COUNT" \
        --arg jq_c "$JQ_COUNT" \
        --arg curl_c "$CURL_COUNT" \
        --arg msg "$ALERT_MSG" \
        '{lssn: $lssn, timestamp: $ts, cpu_usage: $cpu, mem_usage: $mem, load_avg: $load, total_procs: $proc, jq_count: $jq_c, curl_count: $curl_c, alert: $msg}')
    
    kvs_put "lssn" "$lssn" "agent_performance_alert" "$JSON_DATA"
fi

exit 0
