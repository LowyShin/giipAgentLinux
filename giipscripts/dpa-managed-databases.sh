#!/bin/bash
#===============================================================================
# Managed Database Performance & Health Monitoring Script
# 
# Description:
#   tManagedDatabase에서 DB 목록을 가져와 각 DB의:
#   1. Health Check (연결 상태, 응답 시간)
#   2. DPA 데이터 수집 (세션, 부하, 느린 쿼리)
#   3. KVS에 통합 업로드
#
# Version: 2.0.0
# Author: GIIP Team
# Last Updated: 2025-11-06
#
# Usage:
#   bash dpa-managed-databases.sh
#
# Cron Example:
#   */5 * * * * /path/to/dpa-managed-databases.sh >> /var/log/giip/dpa_managed_$(date +\%Y\%m\%d).log 2>&1
#
# Requirements:
#   - sqlcmd (for MSSQL)
#   - mysql (for MySQL/MariaDB)
#   - psql (for PostgreSQL)
#   - jq (for JSON processing)
#   - curl (for API calls)
#
# Security:
#   - DB 접속 정보는 giipdb의 tManagedDatabase에서 암호화되어 관리
#   - Gateway 서버만 복호화된 정보에 접근
#   - KVS에는 수집된 데이터만 전송 (접속 정보 제외)
#===============================================================================

set -e

# ============================================================
# 설정
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../giipAgent.cnf"
LOG_FILE="/var/log/giip/dpa_managed_$(date +%Y%m%d).log"
HOSTNAME=$(hostname)

# 기본값
KVS_ENDPOINT=""
USER_TOKEN=""  # SK (Secret Key)
FUNCTION_CODE=""
K_TYPE="lssn"
K_KEY=""
K_FACTOR="dbhealth"  # Health check + DPA data

# Health Check 타임아웃 (초)
HEALTH_CHECK_TIMEOUT=5

# ============================================================
# 로그 함수
# ============================================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $1" | tee -a "$LOG_FILE"
    fi
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
    
    while IFS='=' read -r key value; do
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '"' | tr -d "'")
        
        if [[ -z "$key" || "$key" =~ ^# ]]; then
            continue
        fi
        
        case "$key" in
            Endpoint|apiaddrv2) KVS_ENDPOINT="$value" ;;
            FunctionCode|apiaddrcode) FUNCTION_CODE="$value" ;;
            UserToken|sk) USER_TOKEN="$value" ;;
            lssn|KKey) K_KEY="$value" ;;
            KType) K_TYPE="$value" ;;
        esac
    done < "$CONFIG_FILE"
    
    if [ -z "$USER_TOKEN" ]; then
        log_error "USER_TOKEN (sk) not configured in $CONFIG_FILE"
        exit 1
    fi
    
    if [ -z "$KVS_ENDPOINT" ]; then
        log_error "KVS_ENDPOINT not configured in $CONFIG_FILE"
        exit 1
    fi
    
    log "✓ Config loaded: Endpoint=$KVS_ENDPOINT, K_TYPE=$K_TYPE, K_KEY=$K_KEY"
}

# ============================================================
# API 호출: DB 목록 조회
# ============================================================
fetch_managed_databases() {
    log "Fetching managed database list from API..."
    
    local endpoint_url="$KVS_ENDPOINT"
    if [ -n "$FUNCTION_CODE" ]; then
        endpoint_url="${endpoint_url}?code=${FUNCTION_CODE}"
    fi
    
    local post_data="text=$(printf '%s' 'ManagedDatabaseListForAgent' | jq -sRr @uri)"
    post_data+="&token=$(printf '%s' "$USER_TOKEN" | jq -sRr @uri)"
    
    local response
    response=$(curl -s -w "\n%{http_code}" -X POST "$endpoint_url" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "$post_data")
    
    local http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | head -n-1)
    
    log_debug "HTTP Status: $http_code"
    log_debug "Response preview: ${response_body:0:200}"
    
    if [ "$http_code" != "200" ]; then
        log_error "Failed to fetch database list (HTTP $http_code)"
        log_error "Response: $response_body"
        exit 1
    fi
    
    # JSON 파싱: RstVal 체크
    local rst_val=$(echo "$response_body" | jq -r '.[0].RstVal // empty')
    if [ "$rst_val" = "400" ]; then
        log_error "API returned error: $(echo "$response_body" | jq -r '.[0].Proc_MSG // "Unknown error"')"
        exit 1
    fi
    
    echo "$response_body"
}

# ============================================================
# MSSQL Health Check
# ============================================================
check_mssql_health() {
    local host="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    local database="$5"
    
    local start_time=$(date +%s%3N)
    
    if ! command -v sqlcmd &> /dev/null; then
        echo '{"status":"error","message":"sqlcmd not installed","response_time_ms":0}'
        return
    fi
    
    local result
    result=$(timeout $HEALTH_CHECK_TIMEOUT sqlcmd -S "$host,$port" -U "$user" -P "$password" \
        ${database:+-d "$database"} \
        -h -1 -Q "SELECT 1 AS alive" 2>&1)
    
    local exit_code=$?
    local end_time=$(date +%s%3N)
    local response_time=$((end_time - start_time))
    
    if [ $exit_code -eq 0 ]; then
        echo "{\"status\":\"success\",\"message\":\"Connected\",\"response_time_ms\":$response_time}"
    elif [ $exit_code -eq 124 ]; then
        echo "{\"status\":\"timeout\",\"message\":\"Connection timeout\",\"response_time_ms\":$((HEALTH_CHECK_TIMEOUT * 1000))}"
    else
        local error_msg=$(echo "$result" | tr '\n' ' ' | sed 's/"/\\"/g')
        echo "{\"status\":\"failed\",\"message\":\"$error_msg\",\"response_time_ms\":$response_time}"
    fi
}

# ============================================================
# MSSQL DPA 데이터 수집
# ============================================================
collect_mssql_dpa() {
    local host="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    local database="$5"
    
    log_debug "Collecting MSSQL DPA data from $host:$port..."
    
    local query="
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
    ORDER BY r.cpu_time DESC
    FOR JSON PATH
    "
    
    local result
    result=$(sqlcmd -S "$host,$port" -U "$user" -P "$password" \
        ${database:+-d "$database"} \
        -h -1 -Q "$query" 2>&1)
    
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        echo "$result"
    else
        echo "[]"
    fi
}

# ============================================================
# MySQL Health Check
# ============================================================
check_mysql_health() {
    local host="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    local database="$5"
    
    local start_time=$(date +%s%3N)
    
    if ! command -v mysql &> /dev/null; then
        echo '{"status":"error","message":"mysql not installed","response_time_ms":0}'
        return
    fi
    
    local result
    result=$(timeout $HEALTH_CHECK_TIMEOUT mysql -h"$host" -P"$port" -u"$user" -p"$password" \
        ${database:+-D "$database"} \
        -e "SELECT 1" 2>&1)
    
    local exit_code=$?
    local end_time=$(date +%s%3N)
    local response_time=$((end_time - start_time))
    
    if [ $exit_code -eq 0 ]; then
        echo "{\"status\":\"success\",\"message\":\"Connected\",\"response_time_ms\":$response_time}"
    elif [ $exit_code -eq 124 ]; then
        echo "{\"status\":\"timeout\",\"message\":\"Connection timeout\",\"response_time_ms\":$((HEALTH_CHECK_TIMEOUT * 1000))}"
    else
        local error_msg=$(echo "$result" | tr '\n' ' ' | sed 's/"/\\"/g')
        echo "{\"status\":\"failed\",\"message\":\"$error_msg\",\"response_time_ms\":$response_time}"
    fi
}

# ============================================================
# PostgreSQL Health Check
# ============================================================
check_postgresql_health() {
    local host="$1"
    local port="$2"
    local user="$3"
    local password="$4"
    local database="$5"
    
    local start_time=$(date +%s%3N)
    
    if ! command -v psql &> /dev/null; then
        echo '{"status":"error","message":"psql not installed","response_time_ms":0}'
        return
    fi
    
    export PGPASSWORD="$password"
    local result
    result=$(timeout $HEALTH_CHECK_TIMEOUT psql -h "$host" -p "$port" -U "$user" \
        ${database:+-d "$database"} \
        -t -c "SELECT 1" 2>&1)
    unset PGPASSWORD
    
    local exit_code=$?
    local end_time=$(date +%s%3N)
    local response_time=$((end_time - start_time))
    
    if [ $exit_code -eq 0 ]; then
        echo "{\"status\":\"success\",\"message\":\"Connected\",\"response_time_ms\":$response_time}"
    elif [ $exit_code -eq 124 ]; then
        echo "{\"status\":\"timeout\",\"message\":\"Connection timeout\",\"response_time_ms\":$((HEALTH_CHECK_TIMEOUT * 1000))}"
    else
        local error_msg=$(echo "$result" | tr '\n' ' ' | sed 's/"/\\"/g')
        echo "{\"status\":\"failed\",\"message\":\"$error_msg\",\"response_time_ms\":$response_time}"
    fi
}

# ============================================================
# Health Check Dispatcher
# ============================================================
check_database_health() {
    local db_type="$1"
    local host="$2"
    local port="$3"
    local user="$4"
    local password="$5"
    local database="$6"
    
    case "${db_type^^}" in
        MSSQL)
            check_mssql_health "$host" "$port" "$user" "$password" "$database"
            ;;
        MYSQL|MARIADB)
            check_mysql_health "$host" "$port" "$user" "$password" "$database"
            ;;
        POSTGRESQL)
            check_postgresql_health "$host" "$port" "$user" "$password" "$database"
            ;;
        *)
            echo "{\"status\":\"unsupported\",\"message\":\"DB type $db_type not supported yet\",\"response_time_ms\":0}"
            ;;
    esac
}

# ============================================================
# 메인 로직
# ============================================================
main() {
    log "=========================================="
    log "Managed Database Monitoring Started"
    log "Hostname: $HOSTNAME"
    log "=========================================="
    
    # 설정 로드
    load_config
    
    # jq 확인
    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Install: sudo apt-get install jq"
        exit 1
    fi
    
    # DB 목록 조회
    local db_list
    db_list=$(fetch_managed_databases)
    
    local db_count=$(echo "$db_list" | jq '. | length')
    log "✓ Fetched $db_count database(s)"
    
    if [ "$db_count" = "0" ]; then
        log "No active databases to monitor"
        exit 0
    fi
    
    # Health Check 결과 배열
    local health_results="[]"
    local dpa_data_all="{}"
    
    # 각 DB 처리
    local index=0
    while [ $index -lt $db_count ]; do
        local db=$(echo "$db_list" | jq ".[$index]")
        
        local mdb_id=$(echo "$db" | jq -r '.mdb_id')
        local db_name=$(echo "$db" | jq -r '.db_name')
        local db_type=$(echo "$db" | jq -r '.db_type')
        local db_host=$(echo "$db" | jq -r '.db_host')
        local db_port=$(echo "$db" | jq -r '.db_port')
        local db_user=$(echo "$db" | jq -r '.db_user')
        local db_password=$(echo "$db" | jq -r '.db_password')
        local db_database=$(echo "$db" | jq -r '.db_database // empty')
        
        log "Processing [$((index + 1))/$db_count]: $db_name ($db_type) @ $db_host:$db_port"
        
        # Health Check
        local health_result
        health_result=$(check_database_health "$db_type" "$db_host" "$db_port" "$db_user" "$db_password" "$db_database")
        
        local status=$(echo "$health_result" | jq -r '.status')
        local message=$(echo "$health_result" | jq -r '.message')
        local response_time=$(echo "$health_result" | jq -r '.response_time_ms')
        
        log "  Health: $status ($response_time ms) - $message"
        
        # Health 결과 저장
        health_results=$(echo "$health_results" | jq --argjson mdb_id "$mdb_id" \
            --arg status "$status" \
            --arg message "$message" \
            --argjson response_time "$response_time" \
            '. += [{"mdb_id":$mdb_id,"status":$status,"message":$message,"response_time_ms":$response_time}]')
        
        # DPA 데이터 수집 (연결 성공 시만)
        if [ "$status" = "success" ] && [ "$db_type" = "MSSQL" ]; then
            log "  Collecting DPA data..."
            local dpa_data
            dpa_data=$(collect_mssql_dpa "$db_host" "$db_port" "$db_user" "$db_password" "$db_database")
            
            if [ "$dpa_data" != "[]" ] && [ -n "$dpa_data" ]; then
                dpa_data_all=$(echo "$dpa_data_all" | jq --arg key "$db_name" --argjson data "$dpa_data" \
                    '. + {($key): $data}')
                log "  ✓ DPA data collected"
            else
                log "  No slow queries detected"
            fi
        fi
        
        index=$((index + 1))
    done
    
    # Health Check 결과 업데이트
    log "Updating health check results..."
    local health_update_data=$(echo "$health_results" | jq -c '.')
    
    local endpoint_url="$KVS_ENDPOINT"
    if [ -n "$FUNCTION_CODE" ]; then
        endpoint_url="${endpoint_url}?code=${FUNCTION_CODE}"
    fi
    
    local post_data="text=$(printf '%s' 'ManagedDatabaseHealthUpdate jsondata' | jq -sRr @uri)"
    post_data+="&token=$(printf '%s' "$USER_TOKEN" | jq -sRr @uri)"
    post_data+="&jsondata=$(printf '%s' "$health_update_data" | jq -sRr @uri)"
    
    local response
    response=$(curl -s -w "\n%{http_code}" -X POST "$endpoint_url" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "$post_data")
    
    local http_code=$(echo "$response" | tail -n1)
    
    if [ "$http_code" = "200" ]; then
        log "✓ Health check results updated"
    else
        log_error "Failed to update health check results (HTTP $http_code)"
    fi
    
    # DPA 데이터 KVS 업로드
    if [ "$(echo "$dpa_data_all" | jq '. | length')" -gt 0 ]; then
        log "Uploading DPA data to KVS..."
        
        local collected_at=$(date -u '+%Y-%m-%dT%H:%M:%S')
        local summary_json=$(jq -n \
            --arg collected_at "$collected_at" \
            --arg collector_host "$HOSTNAME" \
            --arg k_key "$K_KEY" \
            --argjson dpa_data "$dpa_data_all" \
            '{
                collected_at: $collected_at,
                collector_host: $collector_host,
                k_key: $k_key,
                databases: $dpa_data
            }')
        
        local kvsp_text="KVSPut $K_TYPE $K_KEY $K_FACTOR"
        local kvsp_json=$(echo "$summary_json" | jq -c '.')
        
        local post_data="text=$(printf '%s' "$kvsp_text" | jq -sRr @uri)"
        post_data+="&token=$(printf '%s' "$USER_TOKEN" | jq -sRr @uri)"
        post_data+="&jsondata=$(printf '%s' "$kvsp_json" | jq -sRr @uri)"
        
        local response
        response=$(curl -s -w "\n%{http_code}" -X POST "$endpoint_url" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "$post_data")
        
        local http_code=$(echo "$response" | tail -n1)
        
        if [ "$http_code" = "200" ]; then
            log "✓ DPA data uploaded to KVS"
        else
            log_error "Failed to upload DPA data (HTTP $http_code)"
        fi
    fi
    
    log "=========================================="
    log "Managed Database Monitoring Completed"
    log "=========================================="
}

# 실행
main

exit 0
