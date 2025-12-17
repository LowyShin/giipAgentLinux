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
        echo "[MSSQL] ⏳ Skipping due to interval (not due yet)" >&2
        return 0
    fi
    
    # 2. Check Prerequisites (mssql-tools)
    if ! command -v sqlcmd >/dev/null 2>&1; then
        echo "[MSSQL] ⚠️  sqlcmd not found. Skipping." >&2
        return 0
    fi
    
    # 3. Fetch Registered Databases from API
    local api_url=$(build_api_url "${apiaddrv2}" "${apiaddrcode}")
    local mdb_list_file="/tmp/giip_mssql_list_${lssn}.json"
    local mdb_targets_file="/tmp/giip_mssql_targets_${lssn}.txt"
    
    echo "[MSSQL] 📡 Fetching DB list from API..." >&2
    
    # Prepare API payload
    local jsondata="{\"lssn\":${lssn}}"
    local text="ManagedDatabaseListForAgent lssn"
    
    # Call API
    curl -s -X POST "${api_url}" \
        -d "text=${text}&token=${sk}&jsondata=${jsondata}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --insecure \
        --connect-timeout 10 \
        --max-time 30 \
        -o "$mdb_list_file" 2>&1
        
    if [ ! -s "$mdb_list_file" ]; then
        echo "[MSSQL] ⚠️  Failed to fetch DB list (empty response or timeout)" >&2
        rm -f "$mdb_list_file"
        return 1
    fi
    
    # 4. Process DB List using Python
    local python_cmd="python3"
    if ! command -v python3 >/dev/null 2>&1; then
        python_cmd="python"
    fi
    
    $python_cmd -c "
import sys, json

try:
    with open('$mdb_list_file', 'r') as f:
        content = f.read()
        
    data = json.loads(content)
    if isinstance(data, dict) and 'data' in data:
        data = data['data']
    elif isinstance(data, dict) and 'RstVal' in data: 
        data = []
        
    if not isinstance(data, list):
        data = [data] if data else []

    with open('$mdb_targets_file', 'w') as out:
        for db in data:
            if not isinstance(db, dict): continue
            
            db_type = db.get('db_type', '').upper()
            if db_type == 'MSSQL':
                mdb_id = db.get('mdb_id', '')
                host = db.get('db_host', '')
                port = db.get('db_port', '1433')
                user = db.get('db_user', '')
                password = db.get('db_password', '')
                req = db.get('user_list_req', 0)
                if req is None: req = 0
                out.write(f'{mdb_id}|{host}|{port}|{user}|{password}|{req}\n')

except Exception as e:
    sys.exit(1)
"
    
    rm -f "$mdb_list_file"
    
    if [ ! -s "$mdb_targets_file" ]; then
        echo "[MSSQL] ℹ️  No registered MSSQL databases found." >&2
        rm -f "$mdb_targets_file"
        return 0
    fi
    
    local target_count=$(wc -l < "$mdb_targets_file")
    echo "[MSSQL] ✅ Found $target_count MSSQL target(s). Starting collection..." >&2
    
    # 5. Loop through targets and collect
    # 5. Loop through targets and collect
    # Use cat | while to avoid stdin interference from commands inside the loop
    if [ -s "$mdb_targets_file" ]; then
        cat "$mdb_targets_file" | while IFS= read -r line; do
            if [ -z "$line" ]; then continue; fi
            
            local mdb_id=$(echo "$line" | cut -d'|' -f1)
            local db_host=$(echo "$line" | cut -d'|' -f2)
            local db_port=$(echo "$line" | cut -d'|' -f3)
            local db_user=$(echo "$line" | cut -d'|' -f4)
            local db_pass=$(echo "$line" | cut -d'|' -f5)
            local user_list_req=$(echo "$line" | cut -d'|' -f6)
            
            echo "[MSSQL] ⏳ Processing ${db_host}:${db_port}..." >&2
            
            # Construct Query
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
            # Explicitly close stdin for sqlcmd just in case
            local json_output
            if ! json_output=$(sqlcmd -S "${db_host},${db_port}" -U "$db_user" -P "$db_pass" -y 0 -Q "$query" -b -t 5 < /dev/null 2>/dev/null); then
                echo "[MSSQL] ❌ Connection failed or query timeout for ${db_host}" >&2
                log_message "WARN" "[MSSQL] Failed to connect/query ${db_host}"
                continue
            fi
            
            json_output=$(echo "$json_output" | tr -d '\r\n')
            if [ -z "$json_output" ]; then json_output="[]"; fi
            
            local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            local hostname=$(hostname)
            local payload="{\"collected_at\":\"$timestamp\",\"collector_host\":\"$hostname\",\"sql_server\":\"${db_host}\",\"hosts\":$json_output}"
            
            kvs_put "lssn" "${lssn}" "sqlnetinv" "$payload" >/dev/null 2>&1
            echo "[MSSQL] ✅ Data collected and uploaded for ${db_host}" >&2
            
            # --- User List Collection Trigger ---
            if [ "$user_list_req" == "1" ]; then
                echo "[MSSQL] 👤 Collecting User List for ${db_host}..." >&2
                local user_query="SET NOCOUNT ON; SELECT name, type_desc as type, state_desc as status FROM sys.database_principals WHERE type IN ('S','U','G') FOR JSON PATH;"
                
                # Note: Complex role/grant queries omitted for brevity/compatibility. 
                # Ideally use a View or stored procedure on target DB if complex logic needed.
                # Expanded Query:
                user_query="SET NOCOUNT ON; SELECT dp.name, dp.type_desc as type, 'ENABLED' as status, (SELECT r.name + ',' FROM sys.database_role_members drm JOIN sys.database_principals r ON drm.role_principal_id = r.principal_id WHERE drm.member_principal_id = dp.principal_id FOR XML PATH('')) as roles FROM sys.database_principals dp WHERE dp.type IN ('S','U','G') FOR JSON PATH;"

                local user_json
                if user_json=$(sqlcmd -S "${db_host},${db_port}" -U "$db_user" -P "$db_pass" -y 0 -Q "$user_query" -b -t 10 < /dev/null 2>/dev/null); then
                    user_json=$(echo "$user_json" | tr -d '\r\n')
                    if [ -n "$user_json" ]; then
                         # Upload
                         local ul_text="Net3dUserListPut"
                         local ul_payload="{\"mdb_id\":${mdb_id},\"lssn\":${lssn},\"user_list\":${user_json}}"
                         curl -s -X POST "${api_url}" \
                            -d "text=${ul_text}&token=${sk}&jsondata=${ul_payload}" \
                            -H "Content-Type: application/x-www-form-urlencoded" \
                            --insecure >/dev/null 2>&1
                         echo "[MSSQL] 📤 User List uploaded for ${db_host}" >&2
                    else
                         echo "[MSSQL] ⚠️ Empty User List result" >&2
                    fi
                else
                    echo "[MSSQL] ❌ Failed to collect User List" >&2
                fi
            fi
            
        done
    fi
    
    rm -f "$mdb_targets_file"
    
    # Update state file
    echo "$(date +%s)" > "${MSSQL_STATE_FILE}_${lssn}"
    echo "[MSSQL] Cycle completed." >&2
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
