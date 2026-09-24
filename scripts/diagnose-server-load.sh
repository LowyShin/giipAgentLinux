#!/bin/bash
# diagnose-server-load.sh - Server Load Diagnostic Tool
# Purpose: Quickly identify the cause of high server load
# Author: GIIP Team
# Date: 2025-11-11

echo "========================================="
echo "🔍 Server Load Diagnostic Tool"
echo "========================================="
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Hostname: $(hostname)"
echo ""

# ============================================================================
# 1. System Load Overview
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 1. SYSTEM LOAD OVERVIEW"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Load average
echo "⚖️  Load Average:"
uptime
echo ""

# CPU count (for context)
CPU_COUNT=$(grep -c ^processor /proc/cpuinfo)
echo "💻 CPU Cores: $CPU_COUNT"
echo ""

# CPU usage per core
echo "🔥 CPU Usage:"
mpstat -P ALL 1 1 2>/dev/null || top -bn1 | grep "Cpu(s)" | head -1
echo ""

# ============================================================================
# 2. TOP CPU Consuming Processes
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚡ 2. TOP 10 CPU CONSUMING PROCESSES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ps aux --sort=-%cpu | head -11
echo ""

# ============================================================================
# 3. TOP Memory Consuming Processes
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💾 3. TOP 10 MEMORY CONSUMING PROCESSES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ps aux --sort=-%mem | head -11
echo ""

# ============================================================================
# 4. Memory Status
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧠 4. MEMORY STATUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
free -h
echo ""

# Check if swap is being used heavily
SWAP_USED=$(free | grep Swap | awk '{print $3}')
if [ "$SWAP_USED" != "0" ]; then
    echo "⚠️  WARNING: Swap is being used! This can cause severe slowdown."
    echo ""
fi

# ============================================================================
# 5. Disk I/O Status
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💿 5. DISK I/O STATUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Disk usage
echo "📊 Disk Usage:"
df -h / /home /var /tmp 2>/dev/null | grep -v "Filesystem"
echo ""

# I/O stats (if iostat available)
if command -v iostat >/dev/null 2>&1; then
    echo "📈 I/O Statistics:"
    iostat -x 1 2 | tail -20
    echo ""
else
    echo "ℹ️  iostat not available (install sysstat for detailed I/O stats)"
    echo ""
fi

# ============================================================================
# 6. Network Connections
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 6. NETWORK CONNECTIONS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Count connections by state
echo "📡 Connection States:"
netstat -an 2>/dev/null | awk '/^tcp/ {print $6}' | sort | uniq -c | sort -rn || \
ss -tan 2>/dev/null | awk 'NR>1 {print $1}' | sort | uniq -c | sort -rn
echo ""

# Top connection sources
echo "🔝 Top 10 Connection Sources:"
netstat -an 2>/dev/null | grep ESTABLISHED | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -10 || \
ss -tan state established 2>/dev/null | awk 'NR>1 {print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -10
echo ""

# ============================================================================
# 7. Running Processes Count
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚙️  7. PROCESS INFORMATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TOTAL_PROC=$(ps aux | wc -l)
RUNNING_PROC=$(ps aux | awk '$8 ~ /R/ {print $0}' | wc -l)
ZOMBIE_PROC=$(ps aux | awk '$8 ~ /Z/ {print $0}' | wc -l)

echo "📊 Process Count:"
echo "   Total: $TOTAL_PROC"
echo "   Running: $RUNNING_PROC"
echo "   Zombie: $ZOMBIE_PROC"
echo ""

if [ "$ZOMBIE_PROC" -gt 0 ]; then
    echo "⚠️  WARNING: Zombie processes detected!"
    echo "   Zombie processes:"
    ps aux | awk '$8 ~ /Z/ {print $0}'
    echo ""
fi

# ============================================================================
# 8. Recent High-Load Culprits (giipAgent, cron, etc.)
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔎 8. COMMON LOAD SUSPECTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check for multiple instances of scripts
echo "📌 Multiple Script Instances:"
for script in "giipAgent" "collect-perfmon" "test-managed-db"; do
    COUNT=$(ps aux | grep -v grep | grep -c "$script")
    if [ "$COUNT" -gt 1 ]; then
        echo "   ⚠️  $script: $COUNT instances running!"
        ps aux | grep -v grep | grep "$script"
    fi
done
echo ""

# Check cron jobs
echo "📅 Active Cron Jobs (current user):"
crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" || echo "   (None)"
echo ""

# ============================================================================
# 9. System Logs (Recent Errors)
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📜 9. RECENT SYSTEM ERRORS (Last 20 lines)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f /var/log/messages ]; then
    tail -20 /var/log/messages | grep -i "error\|fail\|warn" || echo "   No recent errors"
elif [ -f /var/log/syslog ]; then
    tail -20 /var/log/syslog | grep -i "error\|fail\|warn" || echo "   No recent errors"
else
    journalctl -n 20 --no-pager 2>/dev/null | grep -i "error\|fail\|warn" || echo "   No recent errors"
fi
echo ""

# ============================================================================
# 10. Quick Recommendations
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 10. QUICK DIAGNOSTICS & RECOMMENDATIONS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Analyze load vs CPU count
LOAD_1MIN=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs)
LOAD_THRESHOLD=$(echo "$CPU_COUNT * 1.5" | bc 2>/dev/null || echo "4")

echo "🎯 Load Analysis:"
echo "   1-min Load: $LOAD_1MIN"
echo "   CPU Count: $CPU_COUNT"
echo "   Threshold: $LOAD_THRESHOLD (1.5x CPU count)"

if command -v bc >/dev/null 2>&1; then
    IS_HIGH=$(echo "$LOAD_1MIN > $LOAD_THRESHOLD" | bc 2>/dev/null)
    if [ "$IS_HIGH" = "1" ]; then
        echo "   ⚠️  ALERT: Load is HIGH!"
    else
        echo "   ✅ Load is within normal range"
    fi
fi
echo ""

echo "🔧 Recommended Actions:"
echo ""

# Check memory pressure
MEM_AVAILABLE=$(free | grep Mem | awk '{print $7}')
MEM_TOTAL=$(free | grep Mem | awk '{print $2}')
MEM_PERCENT=$(echo "scale=2; $MEM_AVAILABLE * 100 / $MEM_TOTAL" | bc 2>/dev/null || echo "0")

if [ "$(echo "$MEM_PERCENT < 10" | bc 2>/dev/null)" = "1" ]; then
    echo "   🔴 CRITICAL: Low memory! ($MEM_PERCENT% available)"
    echo "      → Kill unnecessary processes"
    echo "      → Check for memory leaks"
    echo ""
fi

# Check running processes
if [ "$RUNNING_PROC" -gt "$CPU_COUNT" ]; then
    echo "   🟡 WARNING: More running processes ($RUNNING_PROC) than CPU cores ($CPU_COUNT)"
    echo "      → Review top CPU consumers above"
    echo ""
fi

# Check zombie processes
if [ "$ZOMBIE_PROC" -gt 0 ]; then
    echo "   🟠 WARNING: Zombie processes detected ($ZOMBIE_PROC)"
    echo "      → Restart parent processes"
    echo ""
fi

echo "========================================="
echo "✅ Diagnostic Complete"
echo "========================================="
echo ""
echo "💾 Save this output:"
echo "   bash diagnose-server-load.sh > load_report_\$(date +%Y%m%d_%H%M%S).txt"
echo ""
