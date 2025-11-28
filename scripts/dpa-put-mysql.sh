#!/bin/bash
#===============================================================================
# MySQL Network Inventory Data Collection Script
# 
# Description:
#   MySQL 서버의 세션, 부하, 느린 쿼리 정보를 수집하여 KVS에 업로드
#   Windows의 dpa-put-mysql.ps1과 동일한 기능을 Linux에서 제공
#
# Version: 1.0.0
# Author: GIIP Team
# Last Updated: 2025-10-29
#
# Usage:
#   bash dpa-put-mysql.sh
#   bash dpa-put-mysql.sh -h mysql.example.com -u user -p password -d database
#
# Cron Example:
#   */5 * * * * /home/giip/giipAgentLinux/giipscripts/dpa-put-mysql.sh >> /var/log/giip/dpa_put_mysql.log 2>&1
#
# Requirements:
#   - mysql client
#   - jq (for JSON processing)
#   - curl (for API calls)
#===============================================================================

set -e

# ============================================================
# 설정
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../giipAgent.cnf"
LOG_FILE="/var/log/giip/dpa_put_mysql_$(date +%Y%m%d).log"
HOSTNAME=$(hostname)

# 기본값
MYSQL_HOST=""
MYSQL_PORT="3306"
MYSQL_USER=""
MYSQL_PASSWORD=""
MYSQL_DATABASE=""
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
            MySQLHost) MYSQL_HOST="$value" ;;
            MySQLPort) MYSQL_PORT="$value" ;;
            MySQLUser) MYSQL_USER="$value" ;;
            MySQLPassword) MYSQL_PASSWORD="$value" ;;
            MySQLDatabase) MYSQL_DATABASE="$value" ;;
            Endpoint) KVS_ENDPOINT="$value" ;;
            FunctionCode) FUNCTION_CODE="$value" ;;
            UserToken) USER_TOKEN="$value" ;;
            KType) K_TYPE="$value" ;;
            KKey) K_KEY="$value" ;;
        esac
    done < "$CONFIG_FILE"
    
    log "Config loaded: Host=$MYSQL_HOST, Port=$MYSQL_PORT, Database=$MYSQL_DATABASE"
}

# ============================================================
# 파라미터 파싱
# ============================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--host)
            MYSQL_HOST="$2"
            shift 2
            ;;
        -P|--port)
            MYSQL_PORT="$2"
            shift 2
            ;;
        -u|--user)
            MYSQL_USER="$2"
            shift 2
            ;;
        -p|--password)
            MYSQL_PASSWORD="$2"
            shift 2
            ;;
        -d|--database)
            MYSQL_DATABASE="$2"
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
log "MySQL Data Collection Started"
log "Hostname: $HOSTNAME"
log "=========================================="

# 설정 로드
load_config

# 필수 파라미터 확인
if [ -z "$MYSQL_HOST" ] || [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_PASSWORD" ]; then
    log_error "MySQL connection parameters required (Host, User, Password)"
    log_error "Usage: $0 -h host -u user -p password [-d database]"
    exit 1
fi

# mysql 클라이언트 확인
if ! command -v mysql &> /dev/null; then
    log_error "mysql client not found. Install: sudo apt-get install mysql-client"
    exit 1
fi

# jq 확인
if ! command -v jq &> /dev/null; then
    log_error "jq not found. Install: sudo apt-get install jq"
    exit 1
fi

# ============================================================
# MySQL 쿼리 실행 함수
# ============================================================
execute_mysql_query() {
    local query="$1"
    mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" \
        ${MYSQL_DATABASE:+-D"$MYSQL_DATABASE"} \
        -sN -e "$query" 2>&1
}

# ============================================================
# MySQL 연결 테스트
# ============================================================
log "Testing MySQL connection..."
if ! execute_mysql_query "SELECT 1" > /dev/null 2>&1; then
    log_error "Failed to connect to MySQL server"
    exit 1
fi
log "✓ MySQL connection successful"

# ============================================================
# 데이터 수집
# ============================================================
log "Collecting MySQL performance data..."

# 현재 실행중인 쿼리 수집
QUERY_DATA=$(execute_mysql_query "
SELECT 
    COALESCE(pl.host, 'unknown') as host_name,
    COALESCE(pl.user, 'unknown') as login_name,
    COALESCE(pl.state, 'unknown') as status,
    COALESCE(pl.time, 0) as cpu_time,
    0 as reads,
    0 as writes,
    0 as logical_reads,
    NOW() as start_time,
    COALESCE(pl.command, 'unknown') as command,
    COALESCE(pl.info, '') as query_text
FROM information_schema.processlist pl
WHERE pl.command != 'Sleep'
  AND pl.user != 'system user'
  AND pl.time > 50
ORDER BY pl.time DESC
LIMIT 100;
")

if [ $? -ne 0 ]; then
    log_error "Failed to collect MySQL query data"
    exit 1
fi

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
log "MySQL Data Collection Completed"
log "=========================================="

exit 0
