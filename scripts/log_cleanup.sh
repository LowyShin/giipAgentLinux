#!/bin/bash
# ============================================================================
# log_cleanup.sh
# Purpose: Clean up old log files (Log Rotation/Retention)
# Usage: ./log_cleanup.sh [retention_days]
# ============================================================================

# Default retention days
RETENTION_DAYS=${1:-7}

# Locate Log Directory (Assume standard structure)
# Script is in giipAgentLinux/scripts
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$BASE_DIR/../giipLogs"

# Resolve absolute path
if [ -d "$LOG_DIR" ]; then
    LOG_DIR=$(cd "$LOG_DIR" && pwd)
else
    # Try creating if not exists (though cleanup implies existing logs)
    mkdir -p "$LOG_DIR" 2>/dev/null
    LOG_DIR=$(cd "$LOG_DIR" && pwd)
fi

echo "[LogCleanup] Checking logs in $LOG_DIR older than $RETENTION_DAYS days..."

if [ -d "$LOG_DIR" ]; then
    # Find and delete files older than RETENTION_DAYS
    # -mtime +N means modified more than N*24 hours ago
    count=$(find "$LOG_DIR" -type f \( -name "*.log" -o -name "*.json" -o -name "*.txt" \) -mtime +$RETENTION_DAYS | wc -l)
    
    if [ "$count" -gt 0 ]; then
        find "$LOG_DIR" -type f \( -name "*.log" -o -name "*.json" -o -name "*.txt" \) -mtime +$RETENTION_DAYS -delete
        echo "[LogCleanup] Deleted $count old log files."
    else
        echo "[LogCleanup] No old logs found to delete."
    fi
else
    echo "[LogCleanup] Log directory not found."
fi
