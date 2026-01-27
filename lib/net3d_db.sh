#!/bin/bash
# Net3D Database Active Sessions Module
# Purpose: Collect active session data (Client -> DB connections) for Net3D visualization
# Usage: Source this file and call collect_net3d_[type] functions

# ============================================================================
# MySQL Active Sessions
# Returns: JSON array [{ "client_net_address": "ip", "program_name": "", ... }]
# ============================================================================
collect_net3d_mysql() {
    local host="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    local database="${5:-information_schema}"

    if ! command -v mysql &>/dev/null; then
        echo "[]"
        return 1
    fi

    local query="SELECT host, user, db, command, time, info FROM information_schema.processlist WHERE command != 'Sleep' AND user NOT IN ('system user', 'event_scheduler')"

    # Execute query (TSV output)
    local result
    result=$(MYSQL_PWD="$password" timeout 5 mysql -h"$host" -P"$port" -u"$user" -D"$database" -sN -e "$query" 2>&1 | grep -v "Warning")

    if [ -z "$result" ]; then
        echo "[]"
        return 0
    fi

    # Parse with Python
    echo "$result" | python3 -c '
import sys, json

sessions = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    
    parts = line.split("\t")
    # Expected: host, user, db, command, time, info
    # MySQL output can vary if fields are empty/NULL, simple split might be fragile for "info"
    # But mysql -sN ensures tabs.
    
    if len(parts) >= 5:
        host_str = parts[0] # e.g. 192.168.1.5:12345
        client_ip = host_str.split(":")[0] if ":" in host_str else host_str
        
        # Skip local/internal if needed, but Net3D filters mostly on frontend.
        # However, keeping data clean is good.
        
        info_sql = parts[5] if len(parts) > 5 else ""
        
        sessions.append({
            "client_net_address": client_ip,
            "login_name": parts[1],
            "program_name": parts[3], # MySQL Command (Query, Execute, etc)
            "db_name": parts[2],
            "status": "active",
            "cpu_load": int(parts[4]) if parts[4].isdigit() else 0,
            "last_sql": info_sql
        })

print(json.dumps(sessions, ensure_ascii=False))
' 2>/dev/null
}

# ============================================================================
# PostgreSQL Active Sessions
# ============================================================================
collect_net3d_postgresql() {
    local host="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    local database="${5:-postgres}"

    if ! command -v psql &>/dev/null; then
        echo "[]"
        return 1
    fi

    local query="SELECT client_addr, application_name, usename, datname, state, query, EXTRACT(EPOCH FROM (now() - query_start))::int FROM pg_stat_activity WHERE state = 'active' AND client_addr IS NOT NULL"

    # Execute query (CSV/Aligned? -tA is best for pipe)
    # -t: tuples only (no header/footer)
    # -A: unaligned (no padding)
    # -F $'\t': tab separator
    local result
    result=$(PGPASSWORD="$password" timeout 5 psql -h "$host" -p "$port" -U "$user" -d "$database" -t -A -F $'\t' -c "$query" 2>/dev/null)

    if [ -z "$result" ]; then
        echo "[]"
        return 0
    fi

    echo "$result" | python3 -c '
import sys, json

sessions = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    
    parts = line.split("\t")
    if len(parts) >= 7:
        sessions.append({
            "client_net_address": parts[0],
            "program_name": parts[1],
            "login_name": parts[2],
            "db_name": parts[3],
            "status": parts[4],
            "last_sql": parts[5],
            "cpu_load": int(parts[6]) if parts[6].isdigit() else 0
        })

print(json.dumps(sessions, ensure_ascii=False))
' 2>/dev/null
}

# ============================================================================
# MSSQL Active Sessions
# ============================================================================
collect_net3d_mssql() {
    local host="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    local database="${5:-master}"

    if ! command -v sqlcmd &>/dev/null; then
        echo "[]"
        return 1
    fi

    # Enhanced query to capture Running Queries OR Open Transactions
    # Columns: client_net_address, program_name, login_name, status, cpu_time, sql_text, is_open_tran, duration, tran_state
    local query="SET NOCOUNT ON; 
    SELECT 
        ISNULL(s.client_net_address, '') AS client_net_address,
        ISNULL(s.program_name, '') AS program_name,
        ISNULL(s.login_name, '') AS login_name,
        s.status,
        ISNULL(r.cpu_time, 0) AS cpu_time,
        ISNULL(REPLACE(REPLACE(t.text, CHAR(13), ' '), CHAR(10), ' '), '') AS sql_text,
        CASE WHEN trans.session_id IS NOT NULL THEN 1 ELSE 0 END as is_open_tran,
        ISNULL(DATEDIFF(MINUTE, trans.transaction_begin_time, GETDATE()), 0) as tran_duration,
        ISNULL(trans.transaction_state_desc, '') as tran_state
    FROM sys.dm_exec_sessions s
    LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
    LEFT JOIN (
        SELECT
            st.session_id,
            t.transaction_begin_time,
            CASE t.transaction_state
                WHEN 0 THEN 'Not initialized'
                WHEN 1 THEN 'Initialized'
                WHEN 2 THEN 'Active'
                WHEN 3 THEN 'Ended (Read-Only)'
                WHEN 4 THEN 'Commit initiated'
                WHEN 5 THEN 'Prepared'
                WHEN 6 THEN 'Committed'
                WHEN 7 THEN 'Rolling back'
                WHEN 8 THEN 'Rolled back'
            END AS transaction_state_desc
        FROM sys.dm_tran_active_transactions t
        INNER JOIN sys.dm_tran_session_transactions st ON t.transaction_id = st.transaction_id
    ) trans ON s.session_id = trans.session_id
    WHERE 
        s.is_user_process = 1 
        AND (s.status = 'running' OR trans.session_id IS NOT NULL)"
    
    # Execute with sqlcmd
    # -W: remove trailing spaces
    # -s: separator (TAB)
    # -h-1: no headers
    local result
    result=$(timeout 5 sqlcmd -S "$host,$port" -U "$user" -P "$password" -d "$database" -W -s $'\t' -h -1 -Q "$query" 2>/dev/null)

    if [ -z "$result" ]; then
        echo "[]"
        return 0
    fi

    echo "$result" | python3 -c '
import sys, json

sessions = []
for line in sys.stdin:
    line = line.strip()
    if not line or "rows affected" in line: continue
    
    parts = line.split("\t")
    # Expected 9 columns
    if len(parts) >= 1: 
        # Safe extraction with defaults
        def get(idx, default=""):
            return parts[idx] if len(parts) > idx else default

        sessions.append({
            "client_net_address": get(0),
            "program_name": get(1),
            "login_name": get(2),
            "status": get(3, "unknown"),
            "cpu_load": int(get(4)) if get(4).isdigit() else 0,
            "last_sql": get(5),
            "is_open_tran": (get(6) == "1"),
            "tran_duration": int(get(7)) if get(7).isdigit() else 0,
            "tran_state": get(8)
        })

print(json.dumps(sessions, ensure_ascii=False))
' 2>/dev/null
}

# ============================================================================
# Main Helper (Interactive / Standalone Mode)
# allows executing this script directly:
# ./net3d_db.sh mysql 1.2.3.4 3306 root pass db
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    TYPE=$1
    shift
    
    case "$TYPE" in
        mysql)
            collect_net3d_mysql "$@"
            ;;
        postgresql)
            collect_net3d_postgresql "$@"
            ;;
        mssql)
            collect_net3d_mssql "$@"
            ;;
        *)
            echo "Usage: $0 [mysql|postgresql|mssql] [host] [port] [user] [password] [db]"
            exit 1
            ;;
    esac
fi

# ============================================================================
# Collect User List and Upload (User Request Handler)
# ============================================================================
collect_net3d_user_list() {
    local mdb_id="$1"
    local db_type="$2"
    local host="$3"
    local port="$4"
    local user="$5"
    local password="$6"
    local database="$7"
    local lssn="$8"  # Gateway LSSN

    log_message "INFO" "[Net3D-UserList] Collecting users for DB: $db_name (Type: $db_type, ID: $mdb_id)"

    local user_list_json="[]"

    if [ "$db_type" == "MySQL" ] || [ "$db_type" == "MariaDB" ]; then
        if command -v mysql &>/dev/null; then
            local query="SELECT User, Host, authentication_string FROM mysql.user" 
            # Note: authentication_string might differ by version (Password in 5.6)
            # Use a safer query if unsure, or just format simply.
            
            # Simple query for safety across versions
            query="SELECT User, Host FROM mysql.user"

            local result=$(MYSQL_PWD="$password" timeout 5 mysql -h"$host" -P"$port" -u"$user" -sN -e "$query" 2>/dev/null)
            if [ -n "$result" ]; then
                 user_list_json=$(echo "$result" | python3 -c '
import sys, json
users = []
for line in sys.stdin:
    parts = line.strip().split("\t")
    if len(parts) >= 2:
        users.append({"name": parts[0] + "@" + parts[1], "type": "SQL User", "status": "ENABLED", "roles": [], "grants": []})
print(json.dumps(users))
')
            fi
        fi
    elif [ "$db_type" == "MSSQL" ]; then
        if command -v sqlcmd &>/dev/null; then
             local query="SET NOCOUNT ON; SELECT name, type_desc, is_disabled FROM sys.server_principals WHERE type IN ('S', 'U', 'G')"
             local result=$(timeout 5 sqlcmd -S "$host,$port" -U "$user" -P "$password" -W -s $'\t' -h -1 -Q "$query" 2>/dev/null)
             if [ -n "$result" ]; then
                 user_list_json=$(echo "$result" | python3 -c '
import sys, json
users = []
for line in sys.stdin:
    parts = line.strip().split("\t")
    if len(parts) >= 3:
        status = "DISABLED" if parts[2] == "1" else "ENABLED"
        users.append({"name": parts[0], "type": parts[1], "status": status, "roles": [], "grants": []})
print(json.dumps(users))
')
             fi
        fi
    fi

    if [ "$user_list_json" == "[]" ] || [ -z "$user_list_json" ]; then
        log_message "WARN" "[Net3D-UserList] No users found or collection failed."
        # Even if empty, we might want to upload to clear the flag?
        # Yes, upload empty list to clear the request.
        user_list_json="[]"
    fi

    # Upload using Net3dUserListPut
    # Need to verify API logic here. `Net3dUserListPut` expects `jsondata` with `mdb_id`, `lssn`, `user_list`.
    # AND `sk` is required. `sk` should be available in environment (loaded by common.sh/check_managed_databases.sh).

    log_message "INFO" "[Net3D-UserList] Uploading user list..."
    
    local text="Net3dUserListPut mdb_id lssn user_list"
    # mdb_id is integer in JSON?
    local jsondata="{\"mdb_id\":$mdb_id,\"lssn\":$lssn,\"user_list\":$user_list_json}"
    
    # URL encode
    local encoded_text=$(printf '%s' "$text" | jq -sRr '@uri')
    local encoded_token=$(printf '%s' "$sk" | jq -sRr '@uri')
    local encoded_jsondata=$(printf '%s' "$jsondata" | jq -sRr '@uri')

    wget -O /dev/null --quiet \
        --post-data="text=${encoded_text}&token=${encoded_token}&jsondata=${encoded_jsondata}" \
        --header="Content-Type: application/x-www-form-urlencoded" \
        "${apiaddrv2}?code=${apiaddrcode}" \
        --no-check-certificate
    
    if [ $? -eq 0 ]; then
        log_message "INFO" "[Net3D-UserList] Upload success."
    else
        log_message "ERROR" "[Net3D-UserList] Upload failed."
    fi
}
