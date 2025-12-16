#!/bin/bash
# lib/mssql.sh - MSSQL Monitoring Module
# Version: 1.0
# Date: 2025-12-16
# Purpose: Collect SQL Server performance/query data and upload to KVS
# Usage: source lib/mssql.sh && collect_mssql_data <lssn>

# ============================================================================
# Required Dependencies
# ============================================================================
if ! declare -f log_message >/dev/null 2>&1; then
	echo "❌ Error: log_message not found. common.sh must be loaded first" >&2
	exit 1
fi

if ! declare -f kvs_put >/dev/null 2>&1; then
	echo "❌ Error: kvs_put not found. kvs.sh must be loaded first" >&2
	exit 1
fi

# Configuration
MSSQL_INTERVAL=60  # Check every minute (adjust as needed)
MSSQL_STATE_FILE="${MSSQL_STATE_FILE:-/tmp/giip_mssql_state}"

# ============================================================================
# Helper: Parse Connection String
# ============================================================================
_parse_conn_string() {
    local conn_str="$1"
    local key="$2"
    
    # Simple parser assuming Key=Value; format
    echo "$conn_str" | tr ';' '\n' | grep -i "^${key}=" | cut -d'=' -f2- | tr -d '\r'
}

# ============================================================================
# Main Function: Collect and Upload MSSQL Data
# ============================================================================
collect_mssql_data() {
    local lssn="$1"
    
    # log_message "INFO" "[MSSQL] Starting MSSQL data collection check for LSSN=$lssn"
    echo "[MSSQL] 🔍 Starting MSSQL data collection check for LSSN=$lssn" >&2

    # 1. Check interval
    # Force run for debugging (comment out interval check)
    #if ! should_run_mssql "$lssn"; then
    #    echo "[MSSQL] ⏳ Skipping due to interval" >&2
    #    return 0
    #fi
    
    # 2. Check Prerequisites
    if ! command -v sqlcmd >/dev/null 2>&1; then
        # Use simple return to avoid spamming logs if sqlcmd is fundamentally missing
        log_message "WARN" "[MSSQL] sqlcmd not found. Skipping SQL monitoring."
        return 0
    fi
    
    # Try to manually parse SqlConnectionString if missing
    if [ -z "$SqlConnectionString" ]; then
        if [ -f "$CONFIG_FILE" ]; then
            local raw_conn=$(grep "^SqlConnectionString" "$CONFIG_FILE" | head -n 1 | cut -d'=' -f2-)
            SqlConnectionString=$(echo "$raw_conn" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        fi
    fi
    
    if [ -z "$SqlConnectionString" ]; then
        echo "[MSSQL] ❌ SqlConnectionString not defined in config." >&2
        log_message "WARN" "[MSSQL] SqlConnectionString not defined in config. Skipping."
        return 0
    else
        echo "[MSSQL] ✅ SqlConnectionString found (Length: ${#SqlConnectionString})" >&2
    fi
    
    # 3. Parse Connection Details
    # Supports "Server", "User Id" (or "Uid"), "Password" (or "Pwd")
    local db_server=$(_parse_conn_string "$SqlConnectionString" "Server")
    local db_user=$(_parse_conn_string "$SqlConnectionString" "User Id")
    [ -z "$db_user" ] && db_user=$(_parse_conn_string "$SqlConnectionString" "Uid")
    local db_pass=$(_parse_conn_string "$SqlConnectionString" "Password")
    [ -z "$db_pass" ] && db_pass=$(_parse_conn_string "$SqlConnectionString" "Pwd")
    
    if [ -z "$db_server" ] || [ -z "$db_user" ] || [ -z "$db_pass" ]; then
        log_message "ERROR" "[MSSQL] Failed to parse credentials from SqlConnectionString"
        return 1
    fi
    
    log_message "INFO" "[MSSQL] Collecting SQL Server data from $db_server"
    
    # 4. Construct Query (Produces JSON)
    # Emulates dpa-put-mssql.ps1 logic but utilizing T-SQL FOR JSON for aggregation
    local query="
    SET NOCOUNT ON;
    SELECT
        s.host_name,
        COUNT(*) as sessions,
        (
            SELECT
                s2.login_name,
                r.status,
                r.cpu_time,
                r.reads,
                r.writes,
                r.logical_reads,
                r.start_time,
                r.command,
                t.text as query_text
            FROM sys.dm_exec_requests r
            JOIN sys.dm_exec_sessions s2 ON r.session_id = s2.session_id
            OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
            WHERE s2.host_name = s.host_name AND s2.is_user_process = 1
            FOR JSON PATH
        ) as queries
    FROM sys.dm_exec_sessions s
    WHERE s.is_user_process = 1
    GROUP BY s.host_name
    FOR JSON PATH;
    "
    
    # 5. Execute Query
    # -y 0: No width limit (for large JSON)
    # -b: Exit on error
    local json_output
    if ! json_output=$(sqlcmd -S "$db_server" -U "$db_user" -P "$db_pass" -y 0 -Q "$query" -b 2>/dev/null); then
        log_message "ERROR" "[MSSQL] Failed to execute sqlcmd query"
        return 1
    fi
    
    # Clean output (remove headers if any) - sqlcmd might output standard headers
    # Usually -y 0 disables headers but let's be safe. FOR JSON produces one long line usually.
    # We strip empty lines and take the last valid line or join lines.
    # Actually sqlcmd may split JSON across lines.
    json_output=$(echo "$json_output" | tr -d '\r\n')
    
    if [ -z "$json_output" ]; then
        json_output="[]"
    fi
    
    # 6. Wrap in Message Envelope (matching dpa-put-mssql.ps1 structure)
    local timestamp=$(date '+%Y-%m-%dT%H:%M:%S')
    local hostname=$(hostname)
    
    local payload="{\"collected_at\":\"$timestamp\",\"collector_host\":\"$hostname\",\"sql_server\":\"$db_server\",\"hosts\":$json_output}"
    
    # 7. Upload to KVS
    # kFactor 'sqlnetinv' used by Windows Agent
    if kvs_put "lssn" "${lssn}" "sqlnetinv" "$payload"; then
        log_message "INFO" "[MSSQL] Successfully uploaded SQL inventory (${#payload} bytes)"
        echo "$(date +%s)" > "${MSSQL_STATE_FILE}_${lssn}"
        return 0
    else
        log_message "ERROR" "[MSSQL] Failed to upload SQL inventory"
        return 1
    fi
}

# ============================================================================
# Helper: Check run interval
# ============================================================================
should_run_mssql() {
    local lssn="$1"
    local state_file="${MSSQL_STATE_FILE}_${lssn}"
    
    if [ ! -f "$state_file" ]; then
        return 0
    fi
    
    local last_run=$(cat "$state_file")
    local current_time=$(date +%s)
    local elapsed=$((current_time - last_run))
    
    if (( elapsed >= MSSQL_INTERVAL )); then
        return 0
    else
        return 1
    fi
}
