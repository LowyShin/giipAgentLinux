#!/bin/bash
# HTTP Health Check Module for Managed Databases
# Purpose: Perform HTTP health checks for web services, APIs, Azure App Services
# Called by: check_managed_databases.sh

# Function: Perform HTTP health check
# Parameters:
#   $1 - http_url (full URL)
#   $2 - http_method (GET, POST, HEAD)
#   $3 - timeout (seconds)
#   $4 - expected_code (200, 204, etc)
# Returns: "status|response_time_ms|http_code|message"
check_http_health() {
    local http_url="$1"
    local http_method="${2:-GET}"
    local timeout="${3:-10}"
    local expected_code="${4:-200}"
    
    if [ -z "$http_url" ]; then
        echo "error|0|0|HTTP URL is empty"
        return 1
    fi
    
    # Start time (milliseconds)
    local start_time=$(date +%s%3N 2>/dev/null || echo $(($(date +%s) * 1000)))
    
    # Perform HTTP request with curl
    local response=$(curl -s -o /dev/null -w "%{http_code}|%{time_total}" \
        -X "$http_method" \
        --max-time "$timeout" \
        --connect-timeout "$timeout" \
        "$http_url" 2>&1)
    
    local curl_exit=$?
    
    # End time
    local end_time=$(date +%s%3N 2>/dev/null || echo $(($(date +%s) * 1000)))
    local response_time=$((end_time - start_time))
    
    # Parse response
    if [ $curl_exit -eq 0 ]; then
        local http_code=$(echo "$response" | cut -d'|' -f1)
        local curl_time=$(echo "$response" | cut -d'|' -f2)
        
        # Convert curl time (seconds) to milliseconds
        local curl_time_ms=$(echo "$curl_time * 1000" | bc 2>/dev/null || echo "$response_time")
        curl_time_ms=${curl_time_ms%.*}  # Remove decimal
        
        # Check if HTTP code matches expected
        if [ "$http_code" = "$expected_code" ]; then
            echo "success|${curl_time_ms}|${http_code}|HTTP ${http_code} OK"
            return 0
        else
            echo "warning|${curl_time_ms}|${http_code}|HTTP ${http_code} (expected ${expected_code})"
            return 0
        fi
    else
        # curl failed
        case $curl_exit in
            6)  # Couldn't resolve host
                echo "error|${response_time}|0|DNS resolution failed"
                ;;
            7)  # Failed to connect
                echo "error|${response_time}|0|Connection failed"
                ;;
            28) # Timeout
                echo "timeout|${response_time}|0|Connection timeout (${timeout}s)"
                ;;
            35) # SSL connect error
                echo "error|${response_time}|0|SSL handshake failed"
                ;;
            *)  # Other errors
                echo "error|${response_time}|0|curl error ${curl_exit}"
                ;;
        esac
        return 1
    fi
}

# Function: Check if HTTP check is enabled and perform check
# Parameters: JSON object from tManagedDatabase
# Returns: JSON result for health update
perform_http_check() {
    local mdb_id="$1"
    local db_name="$2"
    local http_check_enabled="$3"
    local http_check_url="$4"
    local http_check_method="$5"
    local http_check_timeout="$6"
    local http_check_expected_code="$7"
    
    # Skip if HTTP check not enabled
    if [ "$http_check_enabled" != "1" ] && [ "$http_check_enabled" != "true" ]; then
        return 1
    fi
    
    # Skip if URL is empty
    if [ -z "$http_check_url" ]; then
        return 1
    fi
    
    echo "[Gateway] 🌐 HTTP Health Check: $db_name ($http_check_url)" >&2
    
    # Perform check
    local result=$(check_http_health "$http_check_url" "$http_check_method" "$http_check_timeout" "$http_check_expected_code")
    
    # Parse result
    IFS='|' read -r status response_time http_code message <<< "$result"
    
    # Log result
    local logdt=$(date '+%Y%m%d%H%M%S')
    echo "[${logdt}] [HTTP-Check] $db_name | Status: $status | Time: ${response_time}ms | Code: $http_code | Msg: $message" >> $LogFileName
    
    # Generate JSON result
    cat << EOF
{
    "mdb_id": $mdb_id,
    "status": "$status",
    "message": "$message",
    "response_time_ms": $response_time,
    "performance_metrics": {
        "http_code": "$http_code",
        "response_time_ms": $response_time,
        "check_type": "http",
        "check_url": "$http_check_url",
        "check_method": "$http_check_method"
    }
}
EOF
}

# Export functions
export -f check_http_health
export -f perform_http_check
