#!/bin/bash
# scripts/collect_enhanced_metrics.sh - Enhanced Performance Metrics Collector
# Purpose: Collect detailed CPU, Memory, Disk, IO, and Network metrics in JSON format
# kFactors: cpu_usage_detail, mem_usage_detail, disk_usage_partition, io_statistics, network_traffic, top_processes
# Version: 1.0.0
# Date: 2026-05-13

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"
CONFIG_FILE="${SCRIPT_DIR}/../../giipAgent.cnf"
ENV_FILE="${SCRIPT_DIR}/../../agent_env.json"
LAST_RUN_FILE="/tmp/giip_enhanced_metrics_last_run"

# Load libraries
if [ -f "${LIB_DIR}/common.sh" ]; then
    source "${LIB_DIR}/common.sh"
else
    echo "❌ Error: common.sh not found"
    exit 1
fi

if [ -f "${LIB_DIR}/kvs.sh" ]; then
    source "${LIB_DIR}/kvs.sh"
else
    echo "❌ Error: kvs.sh not found"
    exit 1
fi

# Load configuration
load_config "$CONFIG_FILE"

# Determine interval (default 300s)
METRICS_INTERVAL=300
if [ -f "$ENV_FILE" ] && command -v jq >/dev/null 2>&1; then
    METRICS_INTERVAL=$(jq -r '.metrics_interval // 300' "$ENV_FILE")
fi
# Also check if it's in giipAgent.cnf (as a shell variable)
if [ -n "${metrics_interval}" ]; then
    METRICS_INTERVAL=$metrics_interval
fi

# Check if we should run now based on interval
CURRENT_TIME=$(date +%s)
if [ -f "$LAST_RUN_FILE" ]; then
    LAST_RUN=$(cat "$LAST_RUN_FILE")
    ELAPSED=$((CURRENT_TIME - LAST_RUN))
    if [ "$ELAPSED" -lt "$METRICS_INTERVAL" ]; then
        # echo "⏭️  Interval not reached ($ELAPSED < $METRICS_INTERVAL). Skipping."
        exit 0
    fi
fi

echo "🚀 Collecting enhanced performance metrics..."
echo "$CURRENT_TIME" > "$LAST_RUN_FILE"

# Force English locale for consistent command output
export LC_ALL=C
export LANG=C

# 1. cpu_usage_detail
# Collect User, System, Idle, IOWait, Steal (%)
# Using /proc/stat for most accurate results (delta over 1s)
CPU_STAT1=$(grep '^cpu ' /proc/stat)
sleep 1
CPU_STAT2=$(grep '^cpu ' /proc/stat)

CPU_VALS1=($CPU_STAT1)
CPU_VALS2=($CPU_STAT2)

USER1=${CPU_VALS1[1]}; NICE1=${CPU_VALS1[2]}; SYS1=${CPU_VALS1[3]}; IDLE1=${CPU_VALS1[4]}; IOW1=${CPU_VALS1[5]}; IRQ1=${CPU_VALS1[6]}; SIRQ1=${CPU_VALS1[7]}; STEAL1=${CPU_VALS1[8]}
USER2=${CPU_VALS2[1]}; NICE2=${CPU_VALS2[2]}; SYS2=${CPU_VALS2[3]}; IDLE2=${CPU_VALS2[4]}; IOW2=${CPU_VALS2[5]}; IRQ2=${CPU_VALS2[6]}; SIRQ2=${CPU_VALS2[7]}; STEAL2=${CPU_VALS2[8]}

DIFF_USER=$((USER2 - USER1))
DIFF_NICE=$((NICE2 - NICE1))
DIFF_SYS=$((SYS2 - SYS1))
DIFF_IDLE=$((IDLE2 - IDLE1))
DIFF_IOW=$((IOW2 - IOW1))
DIFF_IRQ=$((IRQ2 - IRQ1))
DIFF_SIRQ=$((SIRQ2 - SIRQ1))
DIFF_STEAL=$((STEAL2 - STEAL1))

DIFF_TOTAL=$((DIFF_USER + DIFF_NICE + DIFF_SYS + DIFF_IDLE + DIFF_IOW + DIFF_IRQ + DIFF_SIRQ + DIFF_STEAL))

if [ "$DIFF_TOTAL" -gt 0 ]; then
    PCT_USER=$(awk "BEGIN {printf \"%.2f\", ($DIFF_USER * 100 / $DIFF_TOTAL)}")
    PCT_SYS=$(awk "BEGIN {printf \"%.2f\", ($DIFF_SYS * 100 / $DIFF_TOTAL)}")
    PCT_IDLE=$(awk "BEGIN {printf \"%.2f\", ($DIFF_IDLE * 100 / $DIFF_TOTAL)}")
    PCT_IOW=$(awk "BEGIN {printf \"%.2f\", ($DIFF_IOW * 100 / $DIFF_TOTAL)}")
    PCT_STEAL=$(awk "BEGIN {printf \"%.2f\", ($DIFF_STEAL * 100 / $DIFF_TOTAL)}")
else
    PCT_USER="0.00"; PCT_SYS="0.00"; PCT_IDLE="100.00"; PCT_IOW="0.00"; PCT_STEAL="0.00"
fi

CPU_JSON=$(jq -n \
    --arg user "$PCT_USER" \
    --arg sys "$PCT_SYS" \
    --arg idle "$PCT_IDLE" \
    --arg iowait "$PCT_IOW" \
    --arg steal "$PCT_STEAL" \
    '{user_pct: ($user|tonumber), system_pct: ($sys|tonumber), idle_pct: ($idle|tonumber), iowait_pct: ($iowait|tonumber), steal_pct: ($steal|tonumber)}')

# 2. mem_usage_detail
# Total, Used, Free, Shared, Buffers, Cached (MB)
MEM_INFO=$(cat /proc/meminfo)
M_TOT=$(echo "$MEM_INFO" | grep "^MemTotal:" | awk '{print int($2/1024)}')
M_FREE=$(echo "$MEM_INFO" | grep "^MemFree:" | awk '{print int($2/1024)}')
M_BUF=$(echo "$MEM_INFO" | grep "^Buffers:" | awk '{print int($2/1024)}')
M_CACHED=$(echo "$MEM_INFO" | grep "^Cached:" | awk '{print int($2/1024)}')
M_SHR=$(echo "$MEM_INFO" | grep "^Shmem:" | awk '{print int($2/1024)}' || echo 0)
M_AVAIL=$(echo "$MEM_INFO" | grep "^MemAvailable:" | awk '{print int($2/1024)}' || echo $((M_FREE + M_BUF + M_CACHED)))

M_USED=$((M_TOT - M_AVAIL))

MEM_JSON=$(jq -n \
    --arg tot "$M_TOT" \
    --arg used "$M_USED" \
    --arg free "$M_FREE" \
    --arg shared "$M_SHR" \
    --arg buf "$M_BUF" \
    --arg cached "$M_CACHED" \
    '{total_mb: ($tot|tonumber), used_mb: ($used|tonumber), free_mb: ($free|tonumber), shared_mb: ($shared|tonumber), buffers_mb: ($buf|tonumber), cached_mb: ($cached|tonumber)}')

# 3. disk_usage_partition
# 마운트별 Total, Used, Avail, Use%
DISK_JSON=$(df -h -P | grep '^/' | awk '
BEGIN { printf "[" }
{
    if (NR > 1) printf ","
    printf "{\"device\":\"%s\",\"total\":\"%s\",\"used\":\"%s\",\"avail\":\"%s\",\"use_pct\":\"%s\",\"mount\":\"%s\"}", $1, $2, $3, $4, $5, $6
}
END { printf "]" }
')

# 4. io_statistics
# 디스크별 tps, read/write speed, wait time
# Use iostat if available, otherwise fallback to /proc/diskstats
if command -v iostat >/dev/null 2>&1; then
    # Use second report for interval statistics
    IO_JSON=$(iostat -dx 1 2 | awk '
    BEGIN { printf "[" }
    /^[sv]d[a-z]|nvme|mmcblk/ {
        if (count > 0) {
            if (found > 0) printf ","
            # Device: $1, r/s: $4, w/s: $5, rkB/s: $6, wkB/s: $7, await: $10
            # tps = r/s + w/s
            tps = $4 + $5
            printf "{\"device\":\"%s\",\"tps\":%.2f,\"read_kb_s\":%.2f,\"write_kb_s\":%.2f,\"avg_wait\":%.2f}", $1, tps, $6, $7, $10
            found++
        }
    }
    /^Device/ { count++ }
    END { printf "]" }
    ')
else
    # Minimal fallback from /proc/diskstats (delta not calculated for simplicity in first version)
    IO_JSON="[]"
fi

# 5. network_traffic
# 인터페이스별 RX/TX bytes/packets
NET_JSON=$(cat /proc/net/dev | awk '
BEGIN { printf "[" }
/^[ ]*[a-zA-Z0-9]+:/ {
    if (found > 0) printf ","
    sub(/:/, "", $1)
    printf "{\"interface\":\"%s\",\"rx_bytes\":%s,\"rx_packets\":%s,\"tx_bytes\":%s,\"tx_packets\":%s}", $1, $2, $3, $10, $11
    found++
}
END { printf "]" }
')

# 6. top_processes
# CPU/MEM 점유율 상위 10개 프로세스 정보
TOP_PROCS_JSON=$(ps -eo pid,ppid,cmd,%cpu,%mem --sort=-%cpu | head -n 11 | awk '
BEGIN { printf "[" }
NR > 1 {
    if (NR > 2) printf ","
    pid=$1; ppid=$2; cpu=$(NF-1); mem=$NF;
    # Command is everything between ppid and cpu
    # But awk is tricky with spaces. 
    # Let s use fixed positions if possible or rebuild cmd.
    cmd=""; for(i=3; i<NF-1; i++) { cmd = (cmd=="" ? $i : cmd" "$i) }
    gsub(/"/, "\\\"", cmd);
    printf "{\"pid\":%d,\"ppid\":%d,\"cpu_pct\":%.1f,\"mem_pct\":%.1f,\"cmd\":\"%s\"}", pid, ppid, cpu, mem, cmd
}
END { printf "]" }
')

# Upload to KVS
if [ -n "$lssn" ] && [ -n "$sk" ] && [ -n "$apiaddrv2" ]; then
    kvs_put "lssn" "$lssn" "cpu_usage_detail" "$CPU_JSON"
    kvs_put "lssn" "$lssn" "mem_usage_detail" "$MEM_JSON"
    kvs_put "lssn" "$lssn" "disk_usage_partition" "$DISK_JSON"
    kvs_put "lssn" "$lssn" "io_statistics" "$IO_JSON"
    kvs_put "lssn" "$lssn" "network_traffic" "$NET_JSON"
    kvs_put "lssn" "$lssn" "top_processes" "$TOP_PROCS_JSON"
    echo "✅ Enhanced metrics uploaded to KVS."
else
    echo "⚠️  Missing required variables for KVS upload."
    exit 1
fi

exit 0
