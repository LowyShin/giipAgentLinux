#!/bin/bash
# scripts/collect_perf.sh - Real-time Performance Collector (v1.2.0)
# Purpose: Patterns-based process monitoring + CPU/Mem stats for standard agent
# kFactor: perf_summary

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Load libraries
if [ -f "${LIB_DIR}/common.sh" ]; then
    source "${LIB_DIR}/common.sh"
else
    echo "❌ Error: common.sh not found in ${LIB_DIR}"
    exit 1
fi

if [ -f "${LIB_DIR}/kvs.sh" ]; then
    source "${LIB_DIR}/kvs.sh"
else
    echo "❌ Error: kvs.sh not found in ${LIB_DIR}"
    exit 1
fi

# Load configuration
load_config "${SCRIPT_DIR}/../giipAgent.cnf"
if [ $? -ne 0 ]; then
    echo "❌ Failed to load configuration"
    exit 1
fi

# Force English locale for consistent command output parsing
export LC_ALL=C
export LANG=C

# 1. CPU Usage
# Using top iteration 2 for real-time accuracy
CPU_USAGE=$(top -bn2 -d 0.1 | grep "Cpu(s)" | tail -n 1 | awk '{print 100 - $8}' || echo "0")
CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "1")
LOAD_AVG_RAW=$(cat /proc/loadavg 2>/dev/null || echo "0.0 0.0 0.0")
LOAD_AVG=$(echo "$LOAD_AVG_RAW" | awk '{print "[" $1 "," $2 "," $3 "]"}')

# 2. Memory Usage (MB)
MEM_INFO=$(free -m 2>/dev/null | grep "^Mem:")
if [ -n "$MEM_INFO" ]; then
    MEM_TOTAL=$(echo "$MEM_INFO" | awk '{print $2}')
    MEM_USED=$(echo "$MEM_INFO" | awk '{print $3}')
    MEM_FREE=$(echo "$MEM_INFO" | awk '{print $4}')
    MEM_PCT=$(awk "BEGIN {if ($MEM_TOTAL > 0) printf \"%.2f\", ($MEM_USED/$MEM_TOTAL)*100; else print \"0\"}" 2>/dev/null || echo "0")
else
    MEM_TOTAL=0; MEM_USED=0; MEM_FREE=0; MEM_PCT=0
fi

# 3. Process Patterns
PATTERNS=("git-auto-sync" "execmqe" "node" "execadm" "cleantable")
PROCESSES_JSON="[]"

if command -v jq > /dev/null 2>&1; then
    # Run ps once and store in variable to optimize
    PS_OUTPUT=$(ps -ef)
    for p in "${PATTERNS[@]}"; do
        count=$(echo "$PS_OUTPUT" | grep "$p" | grep -v grep | wc -l)
        status="OK"
        [ "$count" -eq 0 ] && status="WARNING"
        PROCESSES_JSON=$(echo "$PROCESSES_JSON" | jq -c --arg p "$p" --arg c "$count" --arg s "$status" '. + [{"pattern":$p, "count":($c|tonumber), "status":$s}]')
    done
fi

# 4. System Info
UPTIME=$(uptime -p 2>/dev/null || echo "up unknown")
OS_INFO=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "Linux")
HOSTNAME=$(hostname 2>/dev/null || echo "unknown")

# 5. Build Final JSON
if command -v jq > /dev/null 2>&1; then
    PERF_JSON=$(jq -n \
        --argjson cpu "{\"usage_pct\": $CPU_USAGE, \"cores\": $CPU_CORES, \"load_avg\": $LOAD_AVG}" \
        --argjson mem "{\"total_mb\": $MEM_TOTAL, \"used_mb\": $MEM_USED, \"free_mb\": $MEM_FREE, \"usage_pct\": $MEM_PCT}" \
        --argjson proc "$PROCESSES_JSON" \
        --argjson sys "{\"uptime\": \"$UPTIME\", \"os\": \"$OS_INFO\", \"hostname\": \"$HOSTNAME\"}" \
        --arg ts "$(date '+%Y-%m-%d %H:%M:%S')" \
        '{cpu: $cpu, memory: $mem, processes: $proc, system: $sys, timestamp: $ts}' 2>/dev/null)
else
    # Minimal fallback JSON
    PERF_JSON="{\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\", \"hostname\":\"$HOSTNAME\", \"error\":\"jq_missing\"}"
fi

# 6. Report to KVS (perf_summary)
if [ -n "$lssn" ] && [ -n "$sk" ] && [ -n "$apiaddrv2" ]; then
    echo "📤 Saving performance metrics to KVS (kFactor: perf_summary)..."
    kvs_put "lssn" "$lssn" "perf_summary" "$PERF_JSON"
    
    if [ $? -eq 0 ]; then
        echo "✅ Success"
    else
        echo "❌ Failed to save to KVS"
    fi
else
    echo "⚠️  Missing required variables (lssn, sk, apiaddrv2)"
fi

echo "Performance collection complete."
