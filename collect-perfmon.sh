#!/bin/bash
# collect-perfmon.sh - Linux Server Performance Monitor
# Purpose: Collect system performance metrics and save to KVS
# Author: GIIP Team
# Date: 2025-11-11
# kFactor: perfmon

# ⏱️ Script timeout: Auto-kill if runs longer than 30 seconds
(
    sleep 30
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
# Performance Collection Functions
# ============================================================================

# Function: Collect CPU usage
collect_cpu_usage() {
    # Get CPU usage from /proc/stat (safer than top)
    # Read twice with 1 second interval for accurate calculation
    local cpu1=($(cat /proc/stat | grep '^cpu ' | awk '{print $2, $3, $4, $5, $6, $7, $8}'))
    sleep 1
    local cpu2=($(cat /proc/stat | grep '^cpu ' | awk '{print $2, $3, $4, $5, $6, $7, $8}'))
    
    # Calculate idle and total time
    local idle1=${cpu1[3]}
    local idle2=${cpu2[3]}
    local total1=0
    local total2=0
    
    for value in "${cpu1[@]}"; do
        total1=$((total1 + value))
    done
    
    for value in "${cpu2[@]}"; do
        total2=$((total2 + value))
    done
    
    # Calculate CPU usage percentage
    local idle_diff=$((idle2 - idle1))
    local total_diff=$((total2 - total1))
    
    if [ $total_diff -eq 0 ]; then
        echo "0"
        return
    fi
    
    local cpu_usage=$(echo "scale=2; 100 * ($total_diff - $idle_diff) / $total_diff" | bc 2>/dev/null || echo "0")
    echo "$cpu_usage"
}

# Function: Collect memory usage
collect_memory_usage() {
    # Get memory info from /proc/meminfo
    local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    
    if [ -z "$mem_total" ] || [ -z "$mem_available" ]; then
        echo "0"
        return
    fi
    
    local mem_used=$((mem_total - mem_available))
    local mem_percent=$(echo "scale=2; $mem_used * 100 / $mem_total" | bc 2>/dev/null || echo "0")
    
    # Return JSON
    echo "{\"total_kb\":$mem_total,\"used_kb\":$mem_used,\"available_kb\":$mem_available,\"usage_percent\":$mem_percent}"
}

# Function: Collect disk usage
collect_disk_usage() {
    # Get root partition usage
    local disk_info=$(df -h / | tail -1)
    local disk_total=$(echo "$disk_info" | awk '{print $2}')
    local disk_used=$(echo "$disk_info" | awk '{print $3}')
    local disk_available=$(echo "$disk_info" | awk '{print $4}')
    local disk_percent=$(echo "$disk_info" | awk '{print $5}' | sed 's/%//')
    
    # Return JSON
    echo "{\"total\":\"$disk_total\",\"used\":\"$disk_used\",\"available\":\"$disk_available\",\"usage_percent\":$disk_percent}"
}

# Function: Collect network stats
collect_network_stats() {
    # Get network interface stats (default: eth0, ens33, or first non-lo interface)
    local interface=$(ip route | grep default | awk '{print $5}' | head -1)
    
    if [ -z "$interface" ]; then
        interface="eth0"
    fi
    
    # Read RX/TX bytes
    local rx_bytes=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo "0")
    local tx_bytes=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo "0")
    
    # Convert to MB
    local rx_mb=$(echo "scale=2; $rx_bytes / 1048576" | bc 2>/dev/null || echo "0")
    local tx_mb=$(echo "scale=2; $tx_bytes / 1048576" | bc 2>/dev/null || echo "0")
    
    # Return JSON
    echo "{\"interface\":\"$interface\",\"rx_mb\":$rx_mb,\"tx_mb\":$tx_mb}"
}

# Function: Collect load average
collect_load_average() {
    # Get 1, 5, 15 minute load averages
    local load_avg=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
    local load_1min=$(echo "$load_avg" | awk '{print $1}')
    local load_5min=$(echo "$load_avg" | awk '{print $2}')
    local load_15min=$(echo "$load_avg" | awk '{print $3}')
    
    # Return JSON
    echo "{\"1min\":$load_1min,\"5min\":$load_5min,\"15min\":$load_15min}"
}

# Function: Collect process count
collect_process_count() {
    # Count total processes
    local total_processes=$(ps aux | wc -l)
    local running_processes=$(ps aux | grep -c " R ")
    local sleeping_processes=$(ps aux | grep -c " S ")
    
    # Return JSON
    echo "{\"total\":$total_processes,\"running\":$running_processes,\"sleeping\":$sleeping_processes}"
}

# Function: Get uptime
collect_uptime() {
    # Get system uptime in seconds
    local uptime_sec=$(cat /proc/uptime | awk '{print int($1)}')
    local uptime_days=$((uptime_sec / 86400))
    local uptime_hours=$(((uptime_sec % 86400) / 3600))
    
    # Return JSON
    echo "{\"total_seconds\":$uptime_sec,\"days\":$uptime_days,\"hours\":$uptime_hours}"
}

# ============================================================================
# Main Performance Collection
# ============================================================================

echo "🔍 Collecting Linux server performance metrics..."

# Get hostname
HOSTNAME=$(hostname)

# Collect all metrics
CPU_USAGE=$(collect_cpu_usage)
MEMORY_USAGE=$(collect_memory_usage)
DISK_USAGE=$(collect_disk_usage)
NETWORK_STATS=$(collect_network_stats)
LOAD_AVERAGE=$(collect_load_average)
PROCESS_COUNT=$(collect_process_count)
UPTIME=$(collect_uptime)

# Get timestamp
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Build performance JSON
PERF_JSON="{
  \"timestamp\":\"$TIMESTAMP\",
  \"hostname\":\"$HOSTNAME\",
  \"lssn\":$lssn,
  \"cpu_usage_percent\":$CPU_USAGE,
  \"memory\":$MEMORY_USAGE,
  \"disk\":$DISK_USAGE,
  \"network\":$NETWORK_STATS,
  \"load_average\":$LOAD_AVERAGE,
  \"processes\":$PROCESS_COUNT,
  \"uptime\":$UPTIME
}"

# Pretty print collected metrics
echo ""
echo "📊 Performance Metrics:"
echo "  ⏰ Timestamp: $TIMESTAMP"
echo "  🖥️  Hostname: $HOSTNAME"
echo "  📍 LSSN: $lssn"
echo "  🔥 CPU Usage: ${CPU_USAGE}%"
echo "  💾 Memory: $(echo "$MEMORY_USAGE" | grep -o '"usage_percent":[0-9.]*' | cut -d':' -f2)%"
echo "  💿 Disk: $(echo "$DISK_USAGE" | grep -o '"usage_percent":[0-9]*' | cut -d':' -f2)%"
echo "  📡 Load Avg: $(echo "$LOAD_AVERAGE" | grep -o '"1min":[0-9.]*' | cut -d':' -f2) (1min)"
echo "  ⚙️  Processes: $(echo "$PROCESS_COUNT" | grep -o '"total":[0-9]*' | cut -d':' -f2)"
echo ""

# Save to KVS using kvs_put function
echo "📤 Saving to KVS (kFactor: perfmon)..."

# Use kvs_put function from kvs.sh
kvs_put "lssn" "$lssn" "perfmon" "$PERF_JSON"

if [ $? -eq 0 ]; then
    echo "✅ Performance metrics saved to KVS successfully"
    exit 0
else
    echo "❌ Failed to save performance metrics to KVS"
    exit 1
fi
