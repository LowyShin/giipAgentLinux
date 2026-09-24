#!/bin/bash
# collect-perfmon.sh - Linux Server Performance Monitor (Enhanced v2.0)
# Purpose: Collect comprehensive system performance metrics for performance analysis:
#   1. Take simultaneous initial readings for CPU/network/disk I/O rate deltas
#   2. Sleep 1 second
#   3. Take second readings and calculate per-second rates
#   4. Collect snapshot metrics (memory, disk space, processes, etc.)
#   5. Save all data as local JSON for debugging
#   6. Upload the saved JSON to KVS via kvsput.sh
# kFactor: perfmon
# Version: 2.0
# Date: 2026-05-02

# ⏱️ Script timeout: 60 seconds (1s sleep + collection time)
(
    sleep 60
    kill -9 $$ 2>/dev/null
) &
TIMEOUT_PID=$!

# Cleanup timeout process and temp files on exit
TMP_DISK1="" TMP_DISK2=""
cleanup() {
    kill "$TIMEOUT_PID" 2>/dev/null
    rm -f "$TMP_DISK1" "$TMP_DISK2" 2>/dev/null
}
trap cleanup EXIT

# ============================================================================
# Initialize Script Paths
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"
CONFIG_FILE="${SCRIPT_DIR}/../giipAgent.cnf"

# ============================================================================
# Load Library Modules
# ============================================================================

if [ ! -f "${LIB_DIR}/common.sh" ]; then
    echo "❌ Error: common.sh not found in ${LIB_DIR}"
    exit 1
fi
source "${LIB_DIR}/common.sh"

load_config "$CONFIG_FILE"
if [ $? -ne 0 ]; then
    echo "❌ Failed to load configuration"
    exit 1
fi

if [ -z "$lssn" ] || [ -z "$sk" ] || [ -z "$apiaddrv2" ]; then
    echo "❌ Missing required config: lssn, sk, apiaddrv2"
    exit 1
fi

# jq is required (kvsput.sh also requires it)
if ! command -v jq >/dev/null 2>&1; then
    echo "❌ jq is required but not installed"
    exit 1
fi

# ============================================================================
# Local JSON storage for debugging
# ============================================================================

JSON_DIR="${SCRIPT_DIR}/../log/perfmon"
mkdir -p "$JSON_DIR"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TS_FILE=$(date '+%Y%m%d%H%M%S')
JSON_FILE="${JSON_DIR}/perfmon_${lssn}_${TS_FILE}.json"

# Keep only the last 7 days of local JSON files
find "$JSON_DIR" -name "perfmon_*.json" -mtime +7 -delete 2>/dev/null

echo "🔍 Collecting Linux server performance metrics..."

# ============================================================================
# Phase 1: Initial readings (before 1-second sleep)
# CPU: /proc/stat fields 2-9: user nice system idle iowait irq softirq steal
# ============================================================================

CPU1=($(awk '/^cpu / {print $2,$3,$4,$5,$6,$7,$8,$9}' /proc/stat))

# Disk I/O: /proc/diskstats fields: devname(3) sectors_read(6) sectors_written(10)
TMP_DISK1=$(mktemp /tmp/giip_disk1.XXXXXX)
awk '$3 ~ /^(sd[a-z]$|vd[a-z]$|xvd[a-z]$|nvme[0-9]+n[0-9]+$)/ {print $3,$6,$10}' \
    /proc/diskstats > "$TMP_DISK1" 2>/dev/null

# Network: identify default interface
IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
[ -z "$IFACE" ] && IFACE=$(ls /sys/class/net/ 2>/dev/null | grep -v '^lo$' | head -1)
[ -z "$IFACE" ] && IFACE="eth0"

NET_RX1=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
NET_TX1=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo 0)

# ============================================================================
# 1-second measurement interval
# ============================================================================
sleep 1

# ============================================================================
# Phase 2: Second readings
# ============================================================================

CPU2=($(awk '/^cpu / {print $2,$3,$4,$5,$6,$7,$8,$9}' /proc/stat))

TMP_DISK2=$(mktemp /tmp/giip_disk2.XXXXXX)
awk '$3 ~ /^(sd[a-z]$|vd[a-z]$|xvd[a-z]$|nvme[0-9]+n[0-9]+$)/ {print $3,$6,$10}' \
    /proc/diskstats > "$TMP_DISK2" 2>/dev/null

NET_RX2=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo 0)
NET_TX2=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo 0)

# ============================================================================
# Phase 3: Calculate per-second rates
# ============================================================================

# --- CPU rate ---
u1=${CPU1[0]:-0}; n1=${CPU1[1]:-0}; s1=${CPU1[2]:-0}; id1=${CPU1[3]:-0}
io1=${CPU1[4]:-0}; ir1=${CPU1[5]:-0}; si1=${CPU1[6]:-0}; st1=${CPU1[7]:-0}
u2=${CPU2[0]:-0}; n2=${CPU2[1]:-0}; s2=${CPU2[2]:-0}; id2=${CPU2[3]:-0}
io2=${CPU2[4]:-0}; ir2=${CPU2[5]:-0}; si2=${CPU2[6]:-0}; st2=${CPU2[7]:-0}

TDIFF=$(( (u2+n2+s2+id2+io2+ir2+si2+st2) - (u1+n1+s1+id1+io1+ir1+si1+st1) ))

pct() { awk -v n="$1" -v t="$2" 'BEGIN{printf "%.2f", (t>0 ? n*100/t : 0)}'; }

if [ "$TDIFF" -le 0 ]; then
    CPU_PCT="0.00"; CPU_USER="0.00"; CPU_NICE="0.00"; CPU_SYS="0.00"
    CPU_IOWAIT="0.00"; CPU_STEAL="0.00"; CPU_IDLE="100.00"
else
    CPU_PCT=$(pct $((TDIFF-(id2-id1))) $TDIFF)
    CPU_USER=$(pct $((u2-u1)) $TDIFF)
    CPU_NICE=$(pct $((n2-n1)) $TDIFF)
    CPU_SYS=$(pct $((s2-s1)) $TDIFF)
    CPU_IOWAIT=$(pct $((io2-io1)) $TDIFF)
    CPU_STEAL=$(pct $((st2-st1)) $TDIFF)
    CPU_IDLE=$(pct $((id2-id1)) $TDIFF)
fi

CPU_CORES=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || nproc 2>/dev/null || echo 1)
CPU_MODEL=$(grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//' || echo "unknown")

# --- Disk I/O rate (KB/s from sector delta; 1 sector = 512 bytes = 0.5 KB) ---
DISK_IO_JSON=$(awk '
    NR==FNR { sr1[$1]=$2; sw1[$1]=$3; next }
    ($1 in sr1) {
        rk = int(($2 - sr1[$1]) / 2)
        wk = int(($3 - sw1[$1]) / 2)
        if (rk < 0) rk = 0
        if (wk < 0) wk = 0
        printf "{\"dev\":\"%s\",\"read_kb_per_sec\":%d,\"write_kb_per_sec\":%d},", $1, rk, wk
    }
' "$TMP_DISK1" "$TMP_DISK2" | sed 's/,$//')
DISK_IO_JSON="[${DISK_IO_JSON}]"

# --- Network rate ---
NET_RX_BPS=$(( NET_RX2 - NET_RX1 ))
NET_TX_BPS=$(( NET_TX2 - NET_TX1 ))
[ "$NET_RX_BPS" -lt 0 ] && NET_RX_BPS=0
[ "$NET_TX_BPS" -lt 0 ] && NET_TX_BPS=0
NET_RX_MB=$(awk -v b="$NET_RX2" 'BEGIN{printf "%.2f", b/1048576}')
NET_TX_MB=$(awk -v b="$NET_TX2" 'BEGIN{printf "%.2f", b/1048576}')

# ============================================================================
# Phase 4: Snapshot metrics (no interval needed)
# ============================================================================

# --- Memory (detailed breakdown) ---
MEM_TOTAL=$(awk '/^MemTotal:/{print $2}' /proc/meminfo || echo 0)
MEM_FREE=$(awk '/^MemFree:/{print $2}' /proc/meminfo || echo 0)
MEM_AVAIL=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo || echo 0)
MEM_BUFFERS=$(awk '/^Buffers:/{print $2}' /proc/meminfo || echo 0)
MEM_CACHED=$(awk '/^Cached:/{print $2}' /proc/meminfo | head -1 || echo 0)
MEM_SRECLAIM=$(awk '/^SReclaimable:/{print $2}' /proc/meminfo || echo 0)
SWAP_TOTAL=$(awk '/^SwapTotal:/{print $2}' /proc/meminfo || echo 0)
SWAP_FREE=$(awk '/^SwapFree:/{print $2}' /proc/meminfo || echo 0)

MEM_USED=$(( MEM_TOTAL - MEM_AVAIL ))
MEM_CACHED_TOTAL=$(( MEM_CACHED + MEM_SRECLAIM ))
SWAP_USED=$(( SWAP_TOTAL - SWAP_FREE ))
MEM_PCT=$(awk -v u="$MEM_USED" -v t="$MEM_TOTAL" 'BEGIN{printf "%.2f", (t>0 ? u*100/t : 0)}')
SWAP_PCT=$(awk -v u="$SWAP_USED" -v t="$SWAP_TOTAL" 'BEGIN{printf "%.2f", (t>0 ? u*100/t : 0)}')

# --- Disk filesystems (all physical partitions) ---
DISK_FS_JSON=$(df -k 2>/dev/null | awk '
    NR > 1 && $1 !~ /^(tmpfs|devtmpfs|udev|none|overlay|squashfs|shm)/ {
        pct = $5; gsub(/%/, "", pct)
        printf "{\"mount\":\"%s\",\"device\":\"%s\",\"total_kb\":%d,\"used_kb\":%d,\"avail_kb\":%d,\"use_pct\":%d},",
            $6, $1, $2+0, $3+0, $4+0, pct+0
    }' | sed 's/,$//')
DISK_FS_JSON="[${DISK_FS_JSON}]"

# --- Network errors and drops ---
NET_RX_ERR=$(cat /sys/class/net/$IFACE/statistics/rx_errors 2>/dev/null || echo 0)
NET_TX_ERR=$(cat /sys/class/net/$IFACE/statistics/tx_errors 2>/dev/null || echo 0)
NET_RX_DROP=$(cat /sys/class/net/$IFACE/statistics/rx_dropped 2>/dev/null || echo 0)
NET_TX_DROP=$(cat /sys/class/net/$IFACE/statistics/tx_dropped 2>/dev/null || echo 0)

# --- Network connections by state ---
if command -v ss >/dev/null 2>&1; then
    _SS=$(ss -tan 2>/dev/null)
    CONN_ESTAB=$(echo "$_SS" | grep -c 'ESTAB' 2>/dev/null; true)
    CONN_TW=$(echo "$_SS" | grep -c 'TIME-WAIT' 2>/dev/null; true)
    CONN_LISTEN=$(ss -tln 2>/dev/null | awk 'NR>1' | wc -l | tr -d ' ')
elif command -v netstat >/dev/null 2>&1; then
    _NS=$(netstat -an 2>/dev/null)
    CONN_ESTAB=$(echo "$_NS" | grep -c 'ESTABLISHED' 2>/dev/null; true)
    CONN_TW=$(echo "$_NS" | grep -c 'TIME_WAIT' 2>/dev/null; true)
    CONN_LISTEN=$(netstat -tln 2>/dev/null | grep -c 'LISTEN' 2>/dev/null; true)
else
    CONN_ESTAB=0; CONN_TW=0; CONN_LISTEN=0
fi

# --- Load average ---
LOAD_LINE=$(cat /proc/loadavg)
LOAD_1=$(echo "$LOAD_LINE" | awk '{print $1}')
LOAD_5=$(echo "$LOAD_LINE" | awk '{print $2}')
LOAD_15=$(echo "$LOAD_LINE" | awk '{print $3}')
PROCS_RUN=$(echo "$LOAD_LINE" | awk '{split($4,a,"/"); print a[1]+0}')
PROCS_TOT=$(echo "$LOAD_LINE" | awk '{split($4,a,"/"); print a[2]+0}')

# --- Top 5 processes by CPU ---
TOP_CPU_JSON=$(ps aux --sort=-%cpu 2>/dev/null | awk '
    NR>1 && NR<=6 {
        cmd = $11
        for (i = 12; i <= NF; i++) cmd = cmd " " $i
        gsub(/\\/, "\\\\", cmd); gsub(/"/, "\\\"", cmd)
        if (length(cmd) > 80) cmd = substr(cmd, 1, 80) "..."
        printf "{\"pid\":%s,\"user\":\"%s\",\"cpu_pct\":%.1f,\"mem_pct\":%.1f,\"vsz_kb\":%d,\"rss_kb\":%d,\"cmd\":\"%s\"},",
            $2, $1, $3, $4, $5+0, $6+0, cmd
    }' | sed 's/,$//')
TOP_CPU_JSON="[${TOP_CPU_JSON}]"

# --- Top 5 processes by memory ---
TOP_MEM_JSON=$(ps aux --sort=-%mem 2>/dev/null | awk '
    NR>1 && NR<=6 {
        cmd = $11
        for (i = 12; i <= NF; i++) cmd = cmd " " $i
        gsub(/\\/, "\\\\", cmd); gsub(/"/, "\\\"", cmd)
        if (length(cmd) > 80) cmd = substr(cmd, 1, 80) "..."
        printf "{\"pid\":%s,\"user\":\"%s\",\"cpu_pct\":%.1f,\"mem_pct\":%.1f,\"vsz_kb\":%d,\"rss_kb\":%d,\"cmd\":\"%s\"},",
            $2, $1, $3, $4, $5+0, $6+0, cmd
    }' | sed 's/,$//')
TOP_MEM_JSON="[${TOP_MEM_JSON}]"

# --- Process summary ---
PROC_TOTAL=$(ps ax 2>/dev/null | wc -l)
PROC_RUN=$(ps ax -o stat= 2>/dev/null | grep -c '^R' 2>/dev/null; true)
PROC_SLEEP=$(ps ax -o stat= 2>/dev/null | grep -c '^S' 2>/dev/null; true)
PROC_ZOMBIE=$(ps ax -o stat= 2>/dev/null | grep -c '^Z' 2>/dev/null; true)
PROC_UNINT=$(ps ax -o stat= 2>/dev/null | grep -c '^D' 2>/dev/null; true)

# --- File descriptors ---
FD_USED=$(awk '{print $1+0}' /proc/sys/fs/file-nr 2>/dev/null || echo 0)
FD_MAX=$(cat /proc/sys/fs/file-max 2>/dev/null || echo 0)

# --- Uptime ---
UPTIME_SEC=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)
UPTIME_DAYS=$(( UPTIME_SEC / 86400 ))
UPTIME_HOURS=$(( (UPTIME_SEC % 86400) / 3600 ))
UPTIME_MINS=$(( (UPTIME_SEC % 3600) / 60 ))

# --- System info ---
HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
KERNEL=$(uname -r 2>/dev/null || echo "unknown")
ARCH=$(uname -m 2>/dev/null || echo "unknown")
OS_PRETTY=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 \
    || cat /etc/redhat-release 2>/dev/null | head -1 \
    || uname -s 2>/dev/null || echo "Linux")

# ============================================================================
# Phase 5: Build comprehensive JSON using jq (safe escaping)
# ============================================================================

PERF_JSON=$(jq -n \
    --arg  ts          "$TIMESTAMP" \
    --arg  hostname    "$HOSTNAME" \
    --arg  lssn        "$lssn" \
    --arg  kernel      "$KERNEL" \
    --arg  arch        "$ARCH" \
    --arg  os          "$OS_PRETTY" \
    --arg  uptime_sec  "$UPTIME_SEC" \
    --arg  uptime_days "$UPTIME_DAYS" \
    --arg  uptime_hrs  "$UPTIME_HOURS" \
    --arg  uptime_mins "$UPTIME_MINS" \
    --arg  cpu_cores   "$CPU_CORES" \
    --arg  cpu_model   "$CPU_MODEL" \
    --arg  cpu_pct     "$CPU_PCT" \
    --arg  cpu_user    "$CPU_USER" \
    --arg  cpu_nice    "$CPU_NICE" \
    --arg  cpu_sys     "$CPU_SYS" \
    --arg  cpu_iowait  "$CPU_IOWAIT" \
    --arg  cpu_steal   "$CPU_STEAL" \
    --arg  cpu_idle    "$CPU_IDLE" \
    --arg  mem_total   "$MEM_TOTAL" \
    --arg  mem_used    "$MEM_USED" \
    --arg  mem_free    "$MEM_FREE" \
    --arg  mem_avail   "$MEM_AVAIL" \
    --arg  mem_buf     "$MEM_BUFFERS" \
    --arg  mem_cached  "$MEM_CACHED_TOTAL" \
    --arg  mem_pct     "$MEM_PCT" \
    --arg  swap_tot    "$SWAP_TOTAL" \
    --arg  swap_used   "$SWAP_USED" \
    --arg  swap_free   "$SWAP_FREE" \
    --arg  swap_pct    "$SWAP_PCT" \
    --argjson disk_fs  "$DISK_FS_JSON" \
    --argjson disk_io  "$DISK_IO_JSON" \
    --arg  net_iface   "$IFACE" \
    --arg  net_rx2     "$NET_RX2" \
    --arg  net_tx2     "$NET_TX2" \
    --arg  net_rx_mb   "$NET_RX_MB" \
    --arg  net_tx_mb   "$NET_TX_MB" \
    --arg  net_rx_bps  "$NET_RX_BPS" \
    --arg  net_tx_bps  "$NET_TX_BPS" \
    --arg  net_rx_err  "$NET_RX_ERR" \
    --arg  net_tx_err  "$NET_TX_ERR" \
    --arg  net_rx_drop "$NET_RX_DROP" \
    --arg  net_tx_drop "$NET_TX_DROP" \
    --arg  conn_estab  "$CONN_ESTAB" \
    --arg  conn_tw     "$CONN_TW" \
    --arg  conn_listen "$CONN_LISTEN" \
    --arg  load1       "$LOAD_1" \
    --arg  load5       "$LOAD_5" \
    --arg  load15      "$LOAD_15" \
    --arg  procs_run   "$PROCS_RUN" \
    --arg  procs_tot   "$PROCS_TOT" \
    --arg  proc_total  "$PROC_TOTAL" \
    --arg  proc_run    "$PROC_RUN" \
    --arg  proc_sleep  "$PROC_SLEEP" \
    --arg  proc_zombie "$PROC_ZOMBIE" \
    --arg  proc_unint  "$PROC_UNINT" \
    --argjson top_cpu  "$TOP_CPU_JSON" \
    --argjson top_mem  "$TOP_MEM_JSON" \
    --arg  fd_used     "$FD_USED" \
    --arg  fd_max      "$FD_MAX" \
    '{
        timestamp:  $ts,
        hostname:   $hostname,
        lssn:       ($lssn|tonumber),
        system: {
            kernel:          $kernel,
            arch:            $arch,
            os:              $os,
            uptime_seconds:  ($uptime_sec|tonumber),
            uptime_days:     ($uptime_days|tonumber),
            uptime_hours:    ($uptime_hrs|tonumber),
            uptime_minutes:  ($uptime_mins|tonumber)
        },
        cpu: {
            cores:      ($cpu_cores|tonumber),
            model:      $cpu_model,
            usage_pct:  ($cpu_pct|tonumber),
            user_pct:   ($cpu_user|tonumber),
            nice_pct:   ($cpu_nice|tonumber),
            system_pct: ($cpu_sys|tonumber),
            iowait_pct: ($cpu_iowait|tonumber),
            steal_pct:  ($cpu_steal|tonumber),
            idle_pct:   ($cpu_idle|tonumber)
        },
        memory: {
            total_kb:    ($mem_total|tonumber),
            used_kb:     ($mem_used|tonumber),
            free_kb:     ($mem_free|tonumber),
            available_kb: ($mem_avail|tonumber),
            buffers_kb:  ($mem_buf|tonumber),
            cached_kb:   ($mem_cached|tonumber),
            usage_pct:   ($mem_pct|tonumber),
            swap: {
                total_kb:    ($swap_tot|tonumber),
                used_kb:     ($swap_used|tonumber),
                free_kb:     ($swap_free|tonumber),
                usage_pct:   ($swap_pct|tonumber)
            }
        },
        disk: {
            filesystems:  $disk_fs,
            io_per_sec:   $disk_io
        },
        network: {
            interface:         $net_iface,
            rx_bytes_total:    ($net_rx2|tonumber),
            tx_bytes_total:    ($net_tx2|tonumber),
            rx_mb_total:       ($net_rx_mb|tonumber),
            tx_mb_total:       ($net_tx_mb|tonumber),
            rx_bytes_per_sec:  ($net_rx_bps|tonumber),
            tx_bytes_per_sec:  ($net_tx_bps|tonumber),
            rx_errors:         ($net_rx_err|tonumber),
            tx_errors:         ($net_tx_err|tonumber),
            rx_dropped:        ($net_rx_drop|tonumber),
            tx_dropped:        ($net_tx_drop|tonumber),
            connections: {
                established: ($conn_estab|tonumber),
                time_wait:   ($conn_tw|tonumber),
                listening:   ($conn_listen|tonumber)
            }
        },
        load_average: {
            "1min":         ($load1|tonumber),
            "5min":         ($load5|tonumber),
            "15min":        ($load15|tonumber),
            procs_running:  ($procs_run|tonumber),
            procs_total:    ($procs_tot|tonumber)
        },
        processes: {
            total:              ($proc_total|tonumber),
            running:            ($proc_run|tonumber),
            sleeping:           ($proc_sleep|tonumber),
            uninterruptible:    ($proc_unint|tonumber),
            zombie:             ($proc_zombie|tonumber),
            top_by_cpu:         $top_cpu,
            top_by_mem:         $top_mem
        },
        file_descriptors: {
            used: ($fd_used|tonumber),
            max:  ($fd_max|tonumber)
        }
    }')

if [ $? -ne 0 ] || [ -z "$PERF_JSON" ]; then
    echo "❌ Failed to build performance JSON"
    exit 1
fi

# ============================================================================
# Phase 6: Save JSON locally for debugging
# ============================================================================

echo "$PERF_JSON" > "$JSON_FILE"
echo "💾 Performance data saved locally: $JSON_FILE"

# Print summary to stdout
echo ""
echo "📊 Performance Metrics Summary:"
echo "  ⏰ Timestamp:    $TIMESTAMP"
echo "  🖥️  Hostname:     $HOSTNAME"
echo "  📍 LSSN:         $lssn"
echo "  🔥 CPU Usage:    ${CPU_PCT}% (user=${CPU_USER}% sys=${CPU_SYS}% iowait=${CPU_IOWAIT}% steal=${CPU_STEAL}%)"
echo "  💾 Memory:       ${MEM_PCT}% used (${MEM_USED}KB / ${MEM_TOTAL}KB)"
echo "  🔄 Swap:         ${SWAP_PCT}% used"
echo "  📡 Load Avg:     ${LOAD_1} ${LOAD_5} ${LOAD_15} (1/5/15min)"
echo "  🌐 Network:      RX ${NET_RX_BPS}B/s  TX ${NET_TX_BPS}B/s"
echo "  ⚙️  Processes:    total=${PROC_TOTAL} run=${PROC_RUN} sleep=${PROC_SLEEP} zombie=${PROC_ZOMBIE}"
echo ""

# ============================================================================
# Phase 7: Upload to KVS via kvsput.sh
# ============================================================================

KVSPUT="${SCRIPT_DIR}/kvsput.sh"
if [ ! -f "$KVSPUT" ]; then
    echo "❌ kvsput.sh not found at $KVSPUT"
    exit 1
fi

# Export CONFIG_FILE so kvsput.sh resolves the correct config path
export CONFIG_FILE

echo "📤 Uploading to KVS (kFactor: perfmon)..."
bash "$KVSPUT" "$JSON_FILE" "perfmon"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Performance metrics uploaded to KVS successfully"
else
    echo "❌ Failed to upload to KVS (exit=$EXIT_CODE). Local file kept: $JSON_FILE"
fi

exit $EXIT_CODE
