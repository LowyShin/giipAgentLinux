#!/bin/bash
# collect_server_logs.sh - Collect system and service logs for post-mortem diagnostics
# Purpose: Gather latest diagnostics log lines and upload to KVS under kFactor 'server_logs'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"

# 1. Load config if not already exported
if [ -z "$lssn" ] || [ -z "$sk" ] || [ -z "$apiaddrv2" ]; then
    if [ -f "${BASE_DIR}/lib/common.sh" ]; then
        . "${BASE_DIR}/lib/common.sh"
        load_config "${BASE_DIR}/giipAgent.cnf" >/dev/null 2>&1 || true
    fi
fi

# 2. Load KVS library
if [ -f "${BASE_DIR}/lib/kvs.sh" ]; then
    . "${BASE_DIR}/lib/kvs.sh"
fi

# Verify core config is available
if [ -z "$lssn" ]; then
    echo "❌ Error: LSSN is not loaded or set." >&2
    exit 1
fi

echo "🔍 Collecting server logs for LSSN: $lssn..."

# Helper: Read log file safely with sudo fallback or error messaging
read_log_file() {
    local file_path="$1"
    local lines="$2"
    if [ ! -f "$file_path" ]; then
        echo "File not found: $file_path"
    elif [ ! -r "$file_path" ]; then
        # Try running with sudo if passwordless sudo is configured
        if sudo -n true 2>/dev/null; then
            sudo tail -n "$lines" "$file_path" 2>/dev/null
        else
            echo "Permission denied: Cannot read $file_path (Run agent with sudo or add giip user to syslog group to read system logs)"
        fi
    else
        tail -n "$lines" "$file_path" 2>/dev/null
    fi
}

# Collect dmesg logs (focusing on errors, warnings, panics, oom killer, etc.)
collect_dmesg() {
    if command -v dmesg >/dev/null 2>&1; then
        # Attempt to get logs with error keywords first
        local dmesg_errs
        dmesg_errs=$(dmesg -T 2>/dev/null | tail -n 150 | grep -i -E "oom|kill|panic|segfault|error|crash" | tail -n 30)
        if [ -n "$dmesg_errs" ]; then
            echo "$dmesg_errs"
        else
            # Fallback to general last 30 lines
            dmesg -T 2>/dev/null | tail -n 30
        fi
    else
        echo "dmesg command not found"
    fi
}

# Collect datasets
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
DMESG_DATA=$(collect_dmesg)
MESSAGES_DATA=$(read_log_file "/var/log/messages" 50)
[ "$MESSAGES_DATA" = "File not found: /var/log/messages" ] && MESSAGES_DATA=$(read_log_file "/var/log/syslog" 50)
CRON_DATA=$(read_log_file "/tmp/giipAgent/cron.log" 30)

# Detect DB log files
DB_LOG=""
if [ -f "/var/log/mariadb/mariadb.log" ]; then
    DB_LOG=$(read_log_file "/var/log/mariadb/mariadb.log" 30)
elif [ -f "/var/log/mysql/error.log" ]; then
    DB_LOG=$(read_log_file "/var/log/mysql/error.log" 30)
elif [ -f "/var/log/postgresql/postgresql.log" ]; then
    DB_LOG=$(read_log_file "/var/log/postgresql/postgresql.log" 30)
else
    # Check if we can find any DB log files in common directories
    local found_db_log
    found_db_log=$(find /var/log -type f -name "mysql*.log" -o -name "mariadb*.log" -o -name "postgres*.log" 2>/dev/null | head -1)
    if [ -n "$found_db_log" ]; then
        DB_LOG=$(read_log_file "$found_db_log" 30)
    else
        DB_LOG="No Database error log found in standard paths (/var/log/mariadb/, /var/log/mysql/)"
    fi
fi

# Ensure jq is installed
if ! command -v jq >/dev/null 2>&1; then
    echo "❌ Error: jq is required but not installed." >&2
    exit 1
fi

# Build JSON using jq
LOGS_JSON=$(jq -n \
    --arg ts "$TIMESTAMP" \
    --arg hn "$(hostname)" \
    --arg lssn "$lssn" \
    --arg dmesg "$DMESG_DATA" \
    --arg messages "$MESSAGES_DATA" \
    --arg cron "$CRON_DATA" \
    --arg db "$DB_LOG" \
    '{
        timestamp: $ts,
        hostname: $hn,
        lssn: ($lssn | tonumber),
        dmesg: $dmesg,
        messages: $messages,
        cron_log: $cron,
        db_log: $db
    }')

# Send to KVS
if [ "$(type -t kvs_put)" = "function" ]; then
    kvs_put "lssn" "$lssn" "server_logs" "$LOGS_JSON"
    echo "✅ Server logs successfully uploaded to KVS"
else
    echo "❌ Error: kvs_put function not found. Sourcing kvs.sh failed." >&2
    exit 1
fi

exit 0
