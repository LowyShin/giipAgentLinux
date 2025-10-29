#!/bin/bash
#===============================================================================
# MS SQL Server Network Inventory Data Collection Script
# 
# Description:
#   MS SQL Server의 세션, 부하, 느린 쿼리 정보를 수집하여 KVS에 업로드
#   Windows의 dpa-put-mssql.ps1과 동일한 기능을 Linux에서 제공
#
# Version: 1.0.0
# Author: GIIP Team
# Last Updated: 2025-10-29
#
# Usage:
#   bash dpa-put-mssql.sh
#   bash dpa-put-mssql.sh -h sqlserver.example.com -u user -p password -d database
#
# Cron Example:
#   */5 * * * * /home/giip/giipAgentLinux/giipscripts/dpa-put-mssql.sh >> /var/log/giip/dpa_put_mssql.log 2>&1
#
# Requirements:
#   - sqlcmd (Microsoft SQL Server command-line tool)
#   - jq (for JSON processing)
#   - curl (for API calls)
#
# Install sqlcmd:
#   Ubuntu/Debian:
#     curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
#     curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list | sudo tee /etc/apt/sources.list.d/msprod.list
#     sudo apt-get update
#     sudo apt-get install mssql-tools unixodbc-dev
#     echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
#===============================================================================

set -e

# ============================================================
# 설정
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../giipAgent.cnf"
LOG_FILE="/var/log/giip/dpa_put_mssql_$(date +%Y%m%d).log"
HOSTNAME=$(hostname)

# 기본값
MSSQL_HOST=""
MSSQL_PORT="1433"
MSSQL_USER=""
MSSQL_PASSWORD=""
MSSQL_DATABASE=""
K_FACTOR="sqlnetinv"

# ============================================================
# 로그 함수
# ============================================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

# ============================================================
# 설정 파일 읽기
# ============================================================
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi
    
    log "Loading config from: $CONFIG_FILE"
    
    # giipAgent.cnf 파싱
    while IFS='=' read -r key value; do
        # 주석 및 빈 줄 제거
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '"' | tr -d "'")
        
        if [[ -z "$key" || "$key" =~ ^# ]]; then
            continue
        fi
        
        case "$key" in
            SqlConnectionString)
                # Connection String 파싱
                MSSQL_HOST=$(echo "$value" | grep -oP 'Server=\K[^;]+' || echo "")
                MSSQL_USER=$(echo "$value" | grep -oP 'User Id=\K[^;]+' || echo "")
                MSSQL_PASSWORD=$(echo "$value" | grep -oP 'Password=\K[^;]+' || echo "")
                MSSQL_DATABASE=$(echo "$value" | grep -oP 'Database=\K[^;]+' || echo "")
                ;;
            MSSQLHost) MSSQL_HOST="$value" ;;
            MSSQLPort) MSSQL_PORT="$value" ;;
            MSSQLUser) MSSQL_USER="$value" ;;
            MSSQLPassword) MSSQL_PASSWORD="$value" ;;
            MSSQLDatabase) MSSQL_DATABASE="$value" ;;
            Endpoint) KVS_ENDPOINT="$value" ;;
            FunctionCode) FUNCTION_CODE="$value" ;;
            UserToken) USER_TOKEN="$value" ;;
            KType) K_TYPE="$value" ;;
            KKey) K_KEY="$value" ;;
        esac
    done < "$CONFIG_FILE"
    
    log "Config loaded: Host=$MSSQL_HOST, Port=$MSSQL_PORT, Database=$MSSQL_DATABASE"
}

# ============================================================
# 파라미터 파싱
# ============================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--host)
            MSSQL_HOST="$2"
            shift 2
            ;;
        -P|--port)
            MSSQL_PORT="$2"
            shift 2
            ;;
        -u|--user)
            MSSQL_USER="$2"
            shift 2
            ;;
        -p|--password)
            MSSQL_PASSWORD="$2"
            shift 2
            ;;
        -d|--database)
            MSSQL_DATABASE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown parameter: $1"
            exit 1
            ;;
    esac
done

# ============================================================
# 시작
# ============================================================
log "=========================================="
log "MS SQL Server Data Collection Started"
log "Hostname: $HOSTNAME"
log "=========================================="

# 설정 로드
load_config

# 필수 파라미터 확인
if [ -z "$MSSQL_HOST" ] || [ -z "$MSSQL_USER" ] || [ -z "$MSSQL_PASSWORD" ]; then
    log_error "MS SQL Server connection parameters required (Host, User, Password)"
    log_error "Usage: $0 -h host -u user -p password [-d database]"
    exit 1
fi

# sqlcmd 확인
if ! command -v sqlcmd &> /dev/null; then
    log_error "sqlcmd not found. Install mssql-tools package"
    exit 1
fi

# jq 확인
if ! command -v jq &> /dev/null; then
    log_error "jq not found. Install: sudo apt-get install jq"
    exit 1
fi

# ============================================================
# MS SQL 쿼리 실행 함수
# ============================================================
execute_mssql_query() {
    local query="$1"
    sqlcmd -S "$MSSQL_HOST,$MSSQL_PORT" -U "$MSSQL_USER" -P "$MSSQL_PASSWORD" \
        ${MSSQL_DATABASE:+-d "$MSSQL_DATABASE"} \
        -h -1 -s $'\t' -W -Q "$query" 2>&1
}

# ============================================================
# MS SQL 연결 테스트
# ============================================================
log "Testing MS SQL Server connection..."
if ! execute_mssql_query "SELECT 1" > /dev/null 2>&1; then
    log_error "Failed to connect to MS SQL Server"
    exit 1
fi
log "✓ MS SQL Server connection successful"

# ============================================================
# 데이터 수집
# ============================================================
log "Collecting MS SQL Server performance data..."

# 현재 실행중인 쿼리 수집
QUERY_DATA=$(execute_mssql_query "
SELECT 
    ISNULL(s.host_name, 'unknown') as host_name,
    ISNULL(s.login_name, 'unknown') as login_name,
    ISNULL(r.status, 'unknown') as status,
    ISNULL(r.cpu_time, 0) as cpu_time,
    ISNULL(r.reads, 0) as reads,
    ISNULL(r.writes, 0) as writes,
    ISNULL(r.logical_reads, 0) as logical_reads,
    CONVERT(varchar, r.start_time, 120) as start_time,
    ISNULL(r.command, 'unknown') as command,
    ISNULL(t.text, '') as query_text
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE s.is_user_process = 1
  AND r.cpu_time > 50000
ORDER BY r.cpu_time DESC;
")

if [ $? -ne 0 ]; then
    log_error "Failed to collect MS SQL Server query data"
    exit 1
fi

# 빈 줄 제거
QUERY_DATA=$(echo "$QUERY_DATA" | sed '/^$/d')

# 데이터 행 수 확인
ROW_COUNT=$(echo "$QUERY_DATA" | wc -l)
log "[DIAG] Query rows fetched: $ROW_COUNT"

if [ $ROW_COUNT -eq 0 ]; then
    log "No slow queries detected (>50 seconds)"
    exit 0
fi

# ============================================================
# JSON 생성
# ============================================================
log "Building JSON data..."

# 수집 시간
COLLECTED_AT=$(date -u '+%Y-%m-%dT%H:%M:%S')

# 호스트별 그룹화 및 JSON 생성
JSON_HOSTS="[]"

while IFS=$'\t' read -r host_name login_name status cpu_time reads writes logical_reads start_time command query_text; do
    # 빈 값 필터링
    if [ -z "$host_name" ]; then
        continue
    fi
    
    # Query 객체 생성
    QUERY_OBJ=$(jq -n \
        --arg login_name "$login_name" \
        --arg status "$status" \
        --argjson cpu_time "$cpu_time" \
        --argjson reads "$reads" \
        --argjson writes "$writes" \
        --argjson logical_reads "$logical_reads" \
        --arg start_time "$start_time" \
        --arg command "$command" \
        --arg query_text "$query_text" \
        '{
            login_name: $login_name,
            status: $status,
            cpu_time: $cpu_time,
            reads: $reads,
            writes: $writes,
            logical_reads: $logical_reads,
            start_time: $start_time,
            command: $command,
            query_text: $query_text
        }')
    
    # 호스트 찾기 또는 추가
    HOST_EXISTS=$(echo "$JSON_HOSTS" | jq --arg host "$host_name" 'any(.[]; .host_name == $host)')
    
    if [ "$HOST_EXISTS" = "true" ]; then
        # 기존 호스트에 쿼리 추가
        JSON_HOSTS=$(echo "$JSON_HOSTS" | jq --arg host "$host_name" --argjson query "$QUERY_OBJ" \
            'map(if .host_name == $host then .queries += [$query] | .sessions += 1 else . end)')
    else
        # 새 호스트 추가
        NEW_HOST=$(jq -n \
            --arg host_name "$host_name" \
            --argjson query "$QUERY_OBJ" \
            '{
                host_name: $host_name,
                sessions: 1,
                queries: [$query]
            }')
        JSON_HOSTS=$(echo "$JSON_HOSTS" | jq --argjson new_host "$NEW_HOST" '. += [$new_host]')
    fi
done <<< "$QUERY_DATA"

# 최종 JSON 생성
SUMMARY_JSON=$(jq -n \
    --arg collected_at "$COLLECTED_AT" \
    --arg collector_host "$HOSTNAME" \
    --arg sql_server "$KVS_ENDPOINT" \
    --argjson hosts "$JSON_HOSTS" \
    '{
        collected_at: $collected_at,
        collector_host: $collector_host,
        sql_server: $sql_server,
        hosts: $hosts
    }')

# JSON 크기 확인
JSON_SIZE=${#SUMMARY_JSON}
log "[DIAG] JSON size (bytes): $JSON_SIZE"
log "[DIAG] JSON preview: ${SUMMARY_JSON:0:400}..."

# ============================================================
# KVS 업로드
# ============================================================
if [ -z "$KVS_ENDPOINT" ] || [ -z "$USER_TOKEN" ]; then
    log "KVS upload disabled (missing endpoint or token)"
    log "Collected JSON:"
    echo "$SUMMARY_JSON" | jq '.'
    exit 0
fi

log "Uploading to KVS..."

# apirule.md 규격에 맞춰 요청 생성
KVSP_TEXT="KVSPut $K_TYPE $K_KEY $K_FACTOR"
KVSP_JSON=$(echo "$SUMMARY_JSON" | jq -c '.')

log "[DIAG] KVS Endpoint: $KVS_ENDPOINT"
log "[DIAG] KVS text: $KVSP_TEXT"
log "[DIAG] KVS jsondata size: ${#KVSP_JSON} bytes"

# URL 인코딩된 POST 데이터 생성
POST_DATA="text=$(printf '%s' "$KVSP_TEXT" | jq -sRr @uri)"
POST_DATA+="&token=$(printf '%s' "$USER_TOKEN" | jq -sRr @uri)"
POST_DATA+="&jsondata=$(printf '%s' "$KVSP_JSON" | jq -sRr @uri)"

# API 호출
ENDPOINT_URL="$KVS_ENDPOINT"
if [ -n "$FUNCTION_CODE" ]; then
    ENDPOINT_URL="${ENDPOINT_URL}?code=${FUNCTION_CODE}"
fi

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$ENDPOINT_URL" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "$POST_DATA")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$RESPONSE" | head -n-1)

log "[INFO] HTTP Status: $HTTP_CODE"
log "[INFO] Response: $RESPONSE_BODY"

if [ "$HTTP_CODE" = "200" ]; then
    log "✓ KVS upload successful"
else
    log_error "KVS upload failed (HTTP $HTTP_CODE)"
    log_error "Response: $RESPONSE_BODY"
    exit 1
fi

# ============================================================
# 완료
# ============================================================
log "=========================================="
log "MS SQL Server Data Collection Completed"
log "=========================================="

exit 0
