#!/bin/bash
# collect-server-diagnostics.sh - Collect Server Diagnostics and Save to KVS
# Purpose: Gather comprehensive server metrics and save to KVS as JSON
# Author: GIIP Team
# Date: 2025-11-12
# kFactor: server_diagnostics

# ⏱️ Script timeout: Auto-kill if runs longer than 60 seconds
(
    sleep 60
    kill -9 $$ 2>/dev/null
) &
TIMEOUT_PID=$!

# Cleanup timeout process on exit
trap "kill $TIMEOUT_PID 2>/dev/null" EXIT

# ============================================================================
# Initialize Script Paths (Following MODULAR_ARCHITECTURE.md Section 5)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
CONFIG_FILE="$SCRIPT_DIR/../giipAgent.cnf"

# ============================================================================
# Load Library Modules
# ============================================================================

# Load common functions
if [ ! -f "${LIB_DIR}/common.sh" ]; then
    echo "❌ Error: common.sh not found in ${LIB_DIR}"
    exit 1
fi

source "${LIB_DIR}/common.sh"

# Load configuration
load_config "../giipAgent.cnf"
if [ $? -ne 0 ]; then
    echo "❌ Failed to load configuration"
    exit 1
fi

# Load KVS functions
if [ ! -f "${LIB_DIR}/kvs.sh" ]; then
    echo "❌ Error: kvs.sh not found in ${LIB_DIR}"
    exit 1
fi

source "${LIB_DIR}/kvs.sh"

# Validate required variables
if [ -z "$lssn" ] || [ -z "$sk" ] || [ -z "$apiaddrv2" ] || [ -z "$apiaddrcode" ]; then
    echo "❌ Missing required config: lssn, sk, apiaddrv2, apiaddrcode"
    exit 1
fi

# ============================================================================
# Helper Functions
# ============================================================================

# Function: Escape JSON string
escape_json() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g' | tr -d '\n\r'
}

# Function: Get timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# ============================================================================
# Data Collection Functions
# ============================================================================

echo "🔍 Collecting server diagnostics..."
HOSTNAME=$(hostname)
TIMESTAMP=$(get_timestamp)

# ============================================================================
# 1. System Load Overview
# ============================================================================
echo "📊 1. Collecting system load..."

# Load average
LOAD_AVG=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
LOAD_1MIN=$(echo "$LOAD_AVG" | awk '{print $1}')
LOAD_5MIN=$(echo "$LOAD_AVG" | awk '{print $2}')
LOAD_15MIN=$(echo "$LOAD_AVG" | awk '{print $3}')

# CPU count
CPU_COUNT=$(grep -c ^processor /proc/cpuinfo)

# CPU usage from /proc/stat
cpu1=($(cat /proc/stat | grep '^cpu ' | awk '{print $2, $3, $4, $5, $6, $7, $8}'))
sleep 1
cpu2=($(cat /proc/stat | grep '^cpu ' | awk '{print $2, $3, $4, $5, $6, $7, $8}'))

idle1=${cpu1[3]}
idle2=${cpu2[3]}
total1=0
total2=0

for value in "${cpu1[@]}"; do
    total1=$((total1 + value))
done

for value in "${cpu2[@]}"; do
    total2=$((total2 + value))
done

idle_diff=$((idle2 - idle1))
total_diff=$((total2 - total1))

if [ $total_diff -eq 0 ]; then
    CPU_USAGE="0"
else
    CPU_USAGE=$(echo "scale=2; 100 * ($total_diff - $idle_diff) / $total_diff" | bc 2>/dev/null || echo "0")
fi

# Uptime
UPTIME_SEC=$(cat /proc/uptime | awk '{print int($1)}')
UPTIME_DAYS=$((UPTIME_SEC / 86400))
UPTIME_HOURS=$(((UPTIME_SEC % 86400) / 3600))

LOAD_JSON="{
  \"timestamp\":\"$TIMESTAMP\",
  \"hostname\":\"$HOSTNAME\",
  \"lssn\":$lssn,
  \"load_average\":{
    \"1min\":$LOAD_1MIN,
    \"5min\":$LOAD_5MIN,
    \"15min\":$LOAD_15MIN
  },
  \"cpu\":{
    \"count\":$CPU_COUNT,
    \"usage_percent\":$CPU_USAGE
  },
  \"uptime\":{
    \"total_seconds\":$UPTIME_SEC,
    \"days\":$UPTIME_DAYS,
    \"hours\":$UPTIME_HOURS
  }
}"

echo "📤 Saving system load to KVS..."
kvs_put "lssn" "$lssn" "load_overview" "$LOAD_JSON"

# ============================================================================
# 2. Top CPU Processes
# ============================================================================
echo "📊 2. Collecting top CPU processes..."

TOP_CPU_PROCESSES=$(ps aux --sort=-%cpu | head -6 | tail -5 | awk '{
    printf "{\"user\":\"%s\",\"pid\":%s,\"cpu\":%.1f,\"mem\":%.1f,\"command\":\"%s\"},", 
    $1, $2, $3, $4, $11
}' | sed 's/,$//')

TOP_CPU_JSON="{
  \"timestamp\":\"$TIMESTAMP\",
  \"hostname\":\"$HOSTNAME\",
  \"lssn\":$lssn,
  \"top_processes\":[$TOP_CPU_PROCESSES]
}"

echo "📤 Saving top CPU processes to KVS..."
kvs_put "lssn" "$lssn" "top_cpu" "$TOP_CPU_JSON"

# ============================================================================
# 3. Top Memory Processes
# ============================================================================
echo "📊 3. Collecting top memory processes..."

TOP_MEM_PROCESSES=$(ps aux --sort=-%mem | head -6 | tail -5 | awk '{
    printf "{\"user\":\"%s\",\"pid\":%s,\"cpu\":%.1f,\"mem\":%.1f,\"command\":\"%s\"},", 
    $1, $2, $3, $4, $11
}' | sed 's/,$//')

TOP_MEM_JSON="{
  \"timestamp\":\"$TIMESTAMP\",
  \"hostname\":\"$HOSTNAME\",
  \"lssn\":$lssn,
  \"top_processes\":[$TOP_MEM_PROCESSES]
}"

echo "📤 Saving top memory processes to KVS..."
kvs_put "lssn" "$lssn" "top_memory" "$TOP_MEM_JSON"

# ============================================================================
# 4. Memory Status
# ============================================================================
echo "📊 4. Collecting memory status..."

MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_AVAILABLE=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
MEM_USED=$((MEM_TOTAL - MEM_AVAILABLE))
MEM_PERCENT=$(echo "scale=2; $MEM_USED * 100 / $MEM_TOTAL" | bc 2>/dev/null || echo "0")

SWAP_TOTAL=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
SWAP_FREE=$(grep SwapFree /proc/meminfo | awk '{print $2}')
SWAP_USED=$((SWAP_TOTAL - SWAP_FREE))

if [ "$SWAP_TOTAL" -gt 0 ]; then
    SWAP_PERCENT=$(echo "scale=2; $SWAP_USED * 100 / $SWAP_TOTAL" | bc 2>/dev/null || echo "0")
else
    SWAP_PERCENT="0"
fi

MEMORY_JSON="{
  \"timestamp\":\"$TIMESTAMP\",
  \"hostname\":\"$HOSTNAME\",
  \"lssn\":$lssn,
  \"memory\":{
    \"total_kb\":$MEM_TOTAL,
    \"used_kb\":$MEM_USED,
    \"available_kb\":$MEM_AVAILABLE,
    \"usage_percent\":$MEM_PERCENT
  },
  \"swap\":{
    \"total_kb\":$SWAP_TOTAL,
    \"used_kb\":$SWAP_USED,
    \"free_kb\":$SWAP_FREE,
    \"usage_percent\":$SWAP_PERCENT
  }
}"

echo "📤 Saving memory status to KVS..."
kvs_put "lssn" "$lssn" "memory_status" "$MEMORY_JSON"

# ============================================================================
# 5. Disk Usage
# ============================================================================
echo "📊 5. Collecting disk usage..."

DISK_ROOT=$(df / | tail -1)
DISK_TOTAL=$(echo "$DISK_ROOT" | awk '{print $2}')
DISK_USED=$(echo "$DISK_ROOT" | awk '{print $3}')
DISK_AVAILABLE=$(echo "$DISK_ROOT" | awk '{print $4}')
DISK_PERCENT=$(echo "$DISK_ROOT" | awk '{print $5}' | sed 's/%//')

DISK_JSON="{
  \"timestamp\":\"$TIMESTAMP\",
  \"hostname\":\"$HOSTNAME\",
  \"lssn\":$lssn,
  \"disk\":{
    \"mount\":\"/\",
    \"total_kb\":$DISK_TOTAL,
    \"used_kb\":$DISK_USED,
    \"available_kb\":$DISK_AVAILABLE,
    \"usage_percent\":$DISK_PERCENT
  }
}"

echo "📤 Saving disk usage to KVS..."
kvs_put "lssn" "$lssn" "disk_usage" "$DISK_JSON"

# ============================================================================
# 6. Network Connections
# ============================================================================
echo "📊 6. Collecting network connections..."

# Count connections by state
CONN_ESTABLISHED=$(netstat -an 2>/dev/null | grep -c ESTABLISHED || ss -tan 2>/dev/null | grep -c ESTAB)
CONN_TIME_WAIT=$(netstat -an 2>/dev/null | grep -c TIME_WAIT || ss -tan 2>/dev/null | grep -c TIME-WAIT)
CONN_CLOSE_WAIT=$(netstat -an 2>/dev/null | grep -c CLOSE_WAIT || ss -tan 2>/dev/null | grep -c CLOSE-WAIT)
CONN_LISTEN=$(netstat -an 2>/dev/null | grep -c LISTEN || ss -tan 2>/dev/null | grep -c LISTEN)

# Get network interface
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -z "$INTERFACE" ]; then
    INTERFACE="eth0"
fi

RX_BYTES=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes 2>/dev/null || echo "0")
TX_BYTES=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes 2>/dev/null || echo "0")
RX_MB=$(echo "scale=2; $RX_BYTES / 1048576" | bc 2>/dev/null || echo "0")
TX_MB=$(echo "scale=2; $TX_BYTES / 1048576" | bc 2>/dev/null || echo "0")

NETWORK_JSON="{
  \"timestamp\":\"$TIMESTAMP\",
  \"hostname\":\"$HOSTNAME\",
  \"lssn\":$lssn,
  \"connections\":{
    \"established\":$CONN_ESTABLISHED,
    \"time_wait\":$CONN_TIME_WAIT,
    \"close_wait\":$CONN_CLOSE_WAIT,
    \"listen\":$CONN_LISTEN
  },
  \"interface\":{
    \"name\":\"$INTERFACE\",
    \"rx_mb\":$RX_MB,
    \"tx_mb\":$TX_MB
  }
}"

echo "📤 Saving network status to KVS..."
kvs_put "lssn" "$lssn" "network_status" "$NETWORK_JSON"

# ============================================================================
# 7. Process Information
# ============================================================================
echo "📊 7. Collecting process information..."

TOTAL_PROC=$(ps aux | wc -l)
RUNNING_PROC=$(ps aux | awk '$8 ~ /R/ {print $0}' | wc -l)
SLEEPING_PROC=$(ps aux | awk '$8 ~ /S/ {print $0}' | wc -l)
ZOMBIE_PROC=$(ps aux | awk '$8 ~ /Z/ {print $0}' | wc -l)

PROCESS_JSON="{
  \"timestamp\":\"$TIMESTAMP\",
  \"hostname\":\"$HOSTNAME\",
  \"lssn\":$lssn,
  \"processes\":{
    \"total\":$TOTAL_PROC,
    \"running\":$RUNNING_PROC,
    \"sleeping\":$SLEEPING_PROC,
    \"zombie\":$ZOMBIE_PROC
  }
}"

echo "📤 Saving process information to KVS..."
kvs_put "lssn" "$lssn" "process_info" "$PROCESS_JSON"

# ============================================================================
# 8. Health Summary
# ============================================================================
echo "📊 8. Generating health summary..."

# Calculate health score (0-100)
HEALTH_SCORE=100

# Deduct points for high CPU
if (( $(echo "$CPU_USAGE > 80" | bc -l 2>/dev/null || echo 0) )); then
    HEALTH_SCORE=$((HEALTH_SCORE - 20))
elif (( $(echo "$CPU_USAGE > 50" | bc -l 2>/dev/null || echo 0) )); then
    HEALTH_SCORE=$((HEALTH_SCORE - 10))
fi

# Deduct points for high memory
if (( $(echo "$MEM_PERCENT > 90" | bc -l 2>/dev/null || echo 0) )); then
    HEALTH_SCORE=$((HEALTH_SCORE - 20))
elif (( $(echo "$MEM_PERCENT > 70" | bc -l 2>/dev/null || echo 0) )); then
    HEALTH_SCORE=$((HEALTH_SCORE - 10))
fi

# Deduct points for high disk
if [ "$DISK_PERCENT" -gt 90 ]; then
    HEALTH_SCORE=$((HEALTH_SCORE - 15))
elif [ "$DISK_PERCENT" -gt 80 ]; then
    HEALTH_SCORE=$((HEALTH_SCORE - 5))
fi

# Deduct points for zombies
if [ "$ZOMBIE_PROC" -gt 0 ]; then
    HEALTH_SCORE=$((HEALTH_SCORE - 10))
fi

# Deduct points for high load
LOAD_THRESHOLD=$(echo "$CPU_COUNT * 1.5" | bc 2>/dev/null || echo "4")
if (( $(echo "$LOAD_1MIN > $LOAD_THRESHOLD" | bc -l 2>/dev/null || echo 0) )); then
    HEALTH_SCORE=$((HEALTH_SCORE - 15))
fi

# Determine status
if [ "$HEALTH_SCORE" -ge 80 ]; then
    HEALTH_STATUS="healthy"
elif [ "$HEALTH_SCORE" -ge 60 ]; then
    HEALTH_STATUS="warning"
else
    HEALTH_STATUS="critical"
fi

SUMMARY_JSON="{
  \"timestamp\":\"$TIMESTAMP\",
  \"hostname\":\"$HOSTNAME\",
  \"lssn\":$lssn,
  \"health\":{
    \"score\":$HEALTH_SCORE,
    \"status\":\"$HEALTH_STATUS\"
  },
  \"summary\":{
    \"cpu_usage\":$CPU_USAGE,
    \"memory_usage\":$MEM_PERCENT,
    \"disk_usage\":$DISK_PERCENT,
    \"load_1min\":$LOAD_1MIN,
    \"zombie_processes\":$ZOMBIE_PROC
  }
}"

echo "📤 Saving health summary to KVS..."
kvs_put "lssn" "$lssn" "health_summary" "$SUMMARY_JSON"

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "========================================="
echo "✅ Server Diagnostics Collection Complete"
echo "========================================="
echo "Timestamp: $TIMESTAMP"
echo "Hostname: $HOSTNAME"
echo "LSSN: $lssn"
echo ""
echo "📊 Collected Metrics:"
echo "  1. Load Overview (kFactor: load_overview)"
echo "  2. Top CPU Processes (kFactor: top_cpu)"
echo "  3. Top Memory Processes (kFactor: top_memory)"
echo "  4. Memory Status (kFactor: memory_status)"
echo "  5. Disk Usage (kFactor: disk_usage)"
echo "  6. Network Status (kFactor: network_status)"
echo "  7. Process Info (kFactor: process_info)"
echo "  8. Health Summary (kFactor: health_summary)"
echo ""
echo "🏥 Health Score: $HEALTH_SCORE/100 ($HEALTH_STATUS)"
echo "========================================="
echo ""

exit 0
