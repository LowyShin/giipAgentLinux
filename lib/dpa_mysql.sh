#!/bin/bash
#===============================================================================
# MySQL DPA (Database Performance Analysis) Module
# 
# Description:
#   MySQL 서버의 느린 쿼리(50초 이상 실행)를 수집하여 JSON으로 반환
#
# Version: 1.0.0
# Date: 2025-11-13
#
# Usage:
#   source lib/dpa_mysql.sh
#   result=$(collect_mysql_dpa "host" "port" "user" "password" "database")
#
# Returns:
#   JSON array of slow queries or empty array []
#===============================================================================

# ============================================================================
# MySQL DPA 데이터 수집 함수
# ============================================================================
# Parameters:
#   $1 - host (required)
#   $2 - port (required)
#   $3 - user (required)
#   $4 - password (required)
#   $5 - database (optional)
#   $6 - threshold_seconds (optional, default: 50)
#
# Returns:
#   JSON array of slow queries
# ============================================================================
collect_mysql_dpa() {
    local host="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    local database="${5:-}"
    local threshold="${6:-50}"
    
    # Validate required parameters
    if [ -z "$host" ] || [ -z "$port" ] || [ -z "$user" ] || [ -z "$password" ]; then
        echo "[]"
        return 1
    fi
    
    # Check mysql client availability
    if ! command -v mysql &>/dev/null; then
        echo "[]"
        return 1
    fi
    
    # Build query
    local query="
SELECT 
    COALESCE(pl.host, 'unknown') as host_name,
    COALESCE(pl.user, 'unknown') as login_name,
    COALESCE(pl.state, 'unknown') as status,
    COALESCE(pl.time, 0) as cpu_time,
    0 as reads,
    0 as writes,
    0 as logical_reads,
    DATE_FORMAT(NOW() - INTERVAL pl.time SECOND, '%Y-%m-%d %H:%i:%s') as start_time,
    COALESCE(pl.command, 'unknown') as command,
    COALESCE(SUBSTRING(pl.info, 1, 500), '') as query_text
FROM information_schema.processlist pl
WHERE pl.command != 'Sleep'
  AND pl.user NOT IN ('system user', 'event_scheduler')
  AND pl.time >= $threshold
ORDER BY pl.time DESC
LIMIT 100;
"
    
    # Execute query and capture result
    local result
    result=$(mysql -h"$host" -P"$port" -u"$user" -p"$password" \
        ${database:+-D"$database"} \
        -sN -e "$query" 2>&1 | grep -v "Warning")
    
    local exit_code=$?
    
    # Check if query executed successfully
    if [ $exit_code -ne 0 ]; then
        echo "[]"
        return 1
    fi
    
    # Check if result is empty
    if [ -z "$result" ] || [ "$(echo "$result" | wc -l)" -eq 0 ]; then
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
                "cpu_time": int(fields[3]),
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
export -f collect_mysql_dpa
