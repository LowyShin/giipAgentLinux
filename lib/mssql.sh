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
    
    echo "[MSSQL] 🔍 Starting MSSQL data collection for LSSN=$lssn" >&2

    # 1. Check interval
    if ! should_run_mssql "$lssn"; then
        return 0
    fi
    
    # 2. Check Prerequisites (mssql-tools)
    if ! command -v sqlcmd >/dev/null 2>&1; then
        log_message "WARN" "[MSSQL] sqlcmd not found. Skipping SQL monitoring."
        return 0
    fi
    
    # 3. Fetch Registered Databases from API
    # API: ManagedDatabaseListForAgent
    local api_url=$(build_api_url "${apiaddrv2}" "${apiaddrcode}")
    local mdb_list_file="/tmp/giip_mssql_list_${lssn}.json"
    
    # Prepare API payload
    local jsondata="{\"lssn\":${lssn}}"
    local text="ManagedDatabaseListForAgent lssn"
    
    # Call API
    curl -s -X POST "${api_url}" \
        -d "text=${text}&token=${sk}&jsondata=${jsondata}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --insecure -o "$mdb_list_file" 2>&1
        
    if [ ! -s "$mdb_list_file" ]; then
        log_message "WARN" "[MSSQL] Failed to fetch DB list from API (empty response)"
        rm -f "$mdb_list_file"
        return 1
    fi
    
    # 4. Process DB List using Python
    # We use python to iterate and generate a shell script or perform actions, 
    # but here we'll use python to parse and output a structured list we can loop over in bash,
    # OR better, use python to drive the whole interaction? 
    # Let's keep bash driving sqlcmd for simplicity with environment variables.
    
    # Python script to extract MSSQL connection info
    # Output format: "MDB_ID|HOST|PORT|USER|PASS" (line by line)
    
    local python_cmd="python3"
    if ! command -v python3 >/dev/null 2>&1; then
        python_cmd="python"
    fi
    
    local db_targets=$($python_cmd -c "
import sys, json

try:
    with open('$mdb_list_file', 'r') as f:
        content = f.read()
        
    # Handle API wrapper
    data = json.loads(content)
    # If API returns { 'data': [...] }
    if isinstance(data, dict) and 'data' in data:
        data = data['data']
    elif isinstance(data, dict) and 'RstVal' in data: 
        # API might return just status if empty, or data field
        data = []
        
    if not isinstance(data, list):
        data = [data] if data else []

    for db in data:
        # Check if valid object
        if not isinstance(db, dict): continue
        
        # Filter for MSSQL
        db_type = db.get('db_type', '').upper()
        if db_type == 'MSSQL':
            mdb_id = db.get('mdb_id', '')
            host = db.get('db_host', '')
            port = db.get('db_port', '1433')
            user = db.get('db_user', '')
            password = db.get('db_password', '')
            
            # Escape pipes if necessary (unlikely in these fields but safety first: replace | with _)
            print(f'{mdb_id}|{host}|{port}|{user}|{password}')

except Exception as e:
    sys.exit(1)
")
    
    rm -f "$mdb_list_file"
    
    if [ -z "$db_targets" ]; then
        echo "[MSSQL] ℹ️  No registered MSSQL databases found." >&2
        return 0
    fi
    
    echo "[MSSQL] Found MSSQL targets, starting collection..." >&2
    
    # 5. Loop through targets and collect
    # We collect all into one JSON array for the final payload
    local all_hosts_json=""
    local first_host=1
    
    # Set Internal Field Separator to newline usually, but here we read line by line
    while IFS= read -r line; do
        if [ -z "$line" ]; then continue; fi
        
        # Parse line (delimiter |)
        local mdb_id=$(echo "$line" | cut -d'|' -f1)
        local db_host=$(echo "$line" | cut -d'|' -f2)
        local db_port=$(echo "$line" | cut -d'|' -f3)
        local db_user=$(echo "$line" | cut -d'|' -f4)
        local db_pass=$(echo "$line" | cut -d'|' -f5)
        
        echo "[MSSQL] Connecting to ${db_host}:${db_port}..." >&2
        
        # Construct Query (Same as before)
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
        
        # Execute sqlcmd
        # Use comma for port: -S host,port
        local json_output
        if ! json_output=$(sqlcmd -S "${db_host},${db_port}" -U "$db_user" -P "$db_pass" -y 0 -Q "$query" -b -t 5 2>/dev/null); then
            log_message "ERROR" "[MSSQL] Failed to connect/query ${db_host}"
            continue
        fi
        
        # Clean output
        json_output=$(echo "$json_output" | tr -d '\r\n')
        if [ -z "$json_output" ]; then json_output="[]"; fi
        
        # Since the Windows Agent structure expects "hosts": [...] which aggregates everything,
        # but here we might have multiple SQL servers.
        # The original Windows script collects from ONE server (SqlConnectionString).
        # But DbMonitor.ps1 collects stats separately.
        # The user requested "sqlnetinv" structure which is 'hosts' array.
        # IF we have multiple SQL Servers, we should probably aggregate them ALL into one large 'hosts' array?
        # Or upload separate payloads? 
        # dpa-put-mssql.ps1 structure has "sql_server": "endpoint" (singular).
        # So we should probably upload PER SQL SERVER.
        
        # Construct Payload per SQL Server
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local hostname=$(hostname)
        local payload="{\"collected_at\":\"$timestamp\",\"collector_host\":\"$hostname\",\"sql_server\":\"${db_host}\",\"hosts\":$json_output}"
        
        # Upload
        if kvs_put "lssn" "${lssn}" "sqlnetinv" "$payload"; then
            echo "[MSSQL] ✅ Data uploaded for ${db_host}" >&2
        else
            echo "[MSSQL] ❌ Upload failed for ${db_host}" >&2
        fi
        
    done <<< "$db_targets"
    
    # Update state file
    echo "$(date +%s)" > "${MSSQL_STATE_FILE}_${lssn}"
    return 0
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
