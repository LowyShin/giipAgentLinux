#!/bin/bash
#===============================================================================
# MS SQL Server DPA (Database Performance Analysis) Module
# 
# Description:
#   MS SQL Server의 느린 쿼리(CPU 50초 이상 실행)를 수집하여 JSON으로 반환
#
# Version: 1.0.0
# Date: 2025-11-13
#
# Usage:
#   source lib/dpa_mssql.sh
#   result=$(collect_mssql_dpa "host" "port" "user" "password" "database")
#
# Returns:
#   JSON array of slow queries or empty array []
#===============================================================================

# ============================================================================
# MS SQL Server DPA 데이터 수집 함수
# ============================================================================
# Parameters:
#   $1 - host (required)
#   $2 - port (required)
#   $3 - user (required)
#   $4 - password (required)
#   $5 - database (optional)
#   $6 - threshold_ms (optional, default: 50000 = 50 seconds)
#
# Returns:
#   JSON array of slow queries
# ============================================================================
collect_mssql_dpa() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local host="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    local database="${5:-master}"
    local threshold="${6:-50000}"  # milliseconds
    
    # Validate required parameters
    if [ -z "$host" ] || [ -z "$port" ] || [ -z "$user" ] || [ -z "$password" ]; then
        echo "[]"
        return 1
    fi
    
    # Check sqlcmd availability
    if ! command -v sqlcmd &>/dev/null; then
        echo "[]"
        return 1
    fi
    
    # Build query
    local query="
SET NOCOUNT ON;

SELECT 
    ISNULL(s.host_name, 'unknown') as host_name,
    ISNULL(s.login_name, 'unknown') as login_name,
    ISNULL(r.status, 'unknown') as status,
    ISNULL(r.cpu_time / 1000, 0) as cpu_time,
    ISNULL(r.reads, 0) as reads,
    ISNULL(r.writes, 0) as writes,
    ISNULL(r.logical_reads, 0) as logical_reads,
    CONVERT(varchar, r.start_time, 120) as start_time,
    ISNULL(r.command, 'unknown') as command,
    ISNULL(SUBSTRING(t.text, 1, 500), '') as query_text
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE s.is_user_process = 1
  AND r.cpu_time >= $threshold
ORDER BY r.cpu_time DESC;
"
    
    # Execute query and capture result
    local result
    result=$(sqlcmd -S "$host,$port" -U "$user" -P "$password" \
        -d "$database" \
        -h -1 -s $'\t' -W \
        -Q "$query" 2>&1)
    
    local exit_code=$?
    
    # Check if query executed successfully
    if [ $exit_code -ne 0 ]; then
        echo "[]"
        return 1
    fi
    
    # Filter out empty lines and headers
    result=$(echo "$result" | grep -v "^[[:space:]]*$" | tail -n +2)
    
    # Check if result is empty
    if [ -z "$result" ]; then
        echo "[]"
        return 0
    fi
    
    # Convert tab-separated values to JSON array
    local json_result
    # Parse result using external Python script
    json_result=$(echo "$result" | python3 "${SCRIPT_DIR}/parse_mssql_dpa.py" 2>/dev/null)
    
    # Return result or empty array on error
    if [ -z "$json_result" ]; then
        echo "[]"
    else
        echo "$json_result"
    fi
    
    return 0
}

# Export function for use in other scripts
export -f collect_mssql_dpa
