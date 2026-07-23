#!/bin/bash
#===============================================================================
# PostgreSQL DPA (Database Performance Analysis) Module
# 
# Description:
#   PostgreSQL 서버의 느린 쿼리(50초 이상 실행)를 수집하여 JSON으로 반환
#
# Version: 1.0.0
# Date: 2025-11-13
#
# Usage:
#   source lib/dpa_postgresql.sh
#   result=$(collect_postgresql_dpa "host" "port" "user" "password" "database")
#
# Returns:
#   JSON array of slow queries or empty array []
#===============================================================================

# ============================================================================
# PostgreSQL DPA 데이터 수집 함수
# ============================================================================
# Parameters:
#   $1 - host (required)
#   $2 - port (required)
#   $3 - user (required)
#   $4 - password (required)
#   $5 - database (required)
#   $6 - threshold_seconds (optional, default: 50)
#
# Returns:
#   JSON array of slow queries
# ============================================================================
collect_postgresql_dpa() {
    local host="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    local database="${5:-postgres}"
    local threshold="${6:-50}"
    
    # Validate required parameters
    if [ -z "$host" ] || [ -z "$port" ] || [ -z "$user" ] || [ -z "$password" ]; then
        echo "[]"
        return 1
    fi
    
    # Check psql client availability
    if ! command -v psql &>/dev/null; then
        echo "[]"
        return 1
    fi
    
    # Set password environment variable
    export PGPASSWORD="$password"
    
    # Build query
    local query="
SELECT 
    COALESCE(client_addr::text, 'localhost') as host_name,
    COALESCE(usename, 'unknown') as login_name,
    COALESCE(state, 'unknown') as status,
    EXTRACT(EPOCH FROM (now() - query_start))::int as cpu_time,
    0 as reads,
    0 as writes,
    0 as logical_reads,
    to_char(query_start, 'YYYY-MM-DD HH24:MI:SS') as start_time,
    'QUERY' as command,
    COALESCE(SUBSTRING(query, 1, 500), '') as query_text
FROM pg_stat_activity
WHERE state = 'active'
  AND usename NOT IN ('postgres', 'rdsadmin')
  AND query_start < now() - interval '$threshold seconds'
  AND query NOT LIKE '%pg_stat_activity%'
ORDER BY query_start
LIMIT 100;
"
    
    # Execute query and capture result
    local result
    result=$(psql -h "$host" -p "$port" -U "$user" -d "$database" \
        -t -A -F $'\t' \
        -c "$query" 2>&1)
    
    local exit_code=$?
    
    # Clear password environment variable
    unset PGPASSWORD
    
    # Check if query executed successfully
    if [ $exit_code -ne 0 ]; then
        echo "[]"
        return 1
    fi
    
    # Filter out empty lines
    result=$(echo "$result" | grep -v "^[[:space:]]*$")
    
    # Check if result is empty
    if [ -z "$result" ]; then
        echo "[]"
        return 0
    fi
    
    # Convert tab-separated values to JSON array
    local json_result
    json_result=$(echo "$result" | python3 -c '
import sys, json

queries = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    
    fields = line.split("\t")
    if len(fields) >= 10:
        try:
            queries.append({
                "host_name": fields[0],
                "login_name": fields[1],
                "status": fields[2],
                "cpu_time": int(float(fields[3])),
                "reads": int(fields[4]),
                "writes": int(fields[5]),
                "logical_reads": int(fields[6]),
                "start_time": fields[7],
                "command": fields[8],
                "query_text": fields[9]
            })
        except (ValueError, IndexError):
            continue

print(json.dumps(queries, ensure_ascii=False))
' 2>/dev/null)
    
    # Return result or empty array on error
    if [ -z "$json_result" ]; then
        echo "[]"
    else
        echo "$json_result"
    fi
    
    return 0
}

# Export function for use in other scripts
export -f collect_postgresql_dpa
