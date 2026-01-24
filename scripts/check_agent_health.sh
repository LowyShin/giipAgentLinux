#!/bin/bash
################################################################################
# GIIP Agent - Performance Monitor
# Purpose: Check process counts and trigger alerts via kvs_put
# Requirement: 2026-01-24 Task
################################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Load KVS library
if [ -f "${BASE_DIR}/lib/kvs.sh" ]; then
    . "${BASE_DIR}/lib/kvs.sh"
fi

TARGET_LSSN=$1
[ -z "$TARGET_LSSN" ] && TARGET_LSSN=$lssn

if [ -z "$TARGET_LSSN" ]; then
    echo "❌ Error: LSSN is required."
    exit 1
fi

echo "🔍 Monitoring Performance for LSSN: $TARGET_LSSN..."

# 1. Collect Process Metrics
TOTAL_PROC_COUNT=$(ps -ef | wc -l)
JQ_COUNT=$(pgrep -c jq 2>/dev/null || echo 0)
CURL_COUNT=$(pgrep -c curl 2>/dev/null || echo 0)

echo "📊 Metrics: Total=$TOTAL_PROC_COUNT, jq=$JQ_COUNT, curl=$CURL_COUNT"

# 2. Alert Logic
STATUS="NORMAL"
if [ "$TOTAL_PROC_COUNT" -gt 500 ]; then
    STATUS="CRITICAL"
elif [ "$TOTAL_PROC_COUNT" -gt 300 ]; then
    STATUS="WARNING"
fi

# 3. Construct JSON
CHECK_TIME=$(date '+%Y-%m-%d %H:%M:%S')
METRICS_JSON=$(cat <<EOF
{
  "check_time": "$CHECK_TIME",
  "status": "$STATUS",
  "total_process_count": $TOTAL_PROC_COUNT,
  "cpu_usage": $(get_cpu_usage),
  "mem_usage": $(get_mem_usage),
  "jq_count": $JQ_COUNT,
  "curl_count": $CURL_COUNT
}
EOF
)

# 4. Report to KVS
if [ "$(type -t kvs_put)" = "function" ]; then
    # Always report metrics
    kvs_put "lssn" "$TARGET_LSSN" "agent_performance_metrics" "$METRICS_JSON"
    
    # Trigger alert factor if abnormal
    if [ "$STATUS" != "NORMAL" ]; then
        echo "⚠️  Triggering Performance Alert: $STATUS (Total Processes: $TOTAL_PROC_COUNT)"
        kvs_put "lssn" "$TARGET_LSSN" "agent_performance_alert" "$METRICS_JSON"
    fi
fi

echo "✅ Performance monitoring completed with status: $STATUS"
