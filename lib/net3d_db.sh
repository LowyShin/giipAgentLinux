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

    # Using generic sys.dm_exec_sessions
    local query="SET NOCOUNT ON; SELECT s.client_net_address, s.program_name, s.login_name, s.status, r.cpu_time, t.text FROM sys.dm_exec_sessions s LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t WHERE s.is_user_process = 1 AND s.status = 'running'"
    
    # sqlcmd output parsing is tricky due to fixed width. -W helps remove trailing spaces. -s works for separator.
    # col_separator matches Tab
    local result
    result=$(timeout 5 sqlcmd -S "$host,$port" -U "$user" -P "$password" -d "$database" -W -s $'\t' -Q "$query" 2>/dev/null | sed '1,2d')

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
    # expected 6 fields
    if len(parts) >= 4: # Allow missing sql/cpu
        sessions.append({
            "client_net_address": parts[0],
            "program_name": parts[1] if len(parts)>1 else "",
            "login_name": parts[2] if len(parts)>2 else "",
            "status": parts[3] if len(parts)>3 else "unknown",
            "cpu_load": int(parts[4]) if len(parts)>4 and parts[4].isdigit() else 0,
            "last_sql": parts[5] if len(parts)>5 else ""
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
