#!/bin/bash
# giipAgent Auto-Discovery Integration
# Call this script periodically (every 5 minutes) from cron
# Example crontab: */5 * * * * /path/to/giip-auto-discover.sh

# Sync system time (once per hour to avoid excessive NTP queries)
LAST_SYNC_FILE="/tmp/giip-last-time-sync"
CURRENT_HOUR=$(date +%Y%m%d%H)
if [ ! -f "$LAST_SYNC_FILE" ] || [ "$(cat $LAST_SYNC_FILE 2>/dev/null)" != "$CURRENT_HOUR" ]; then
    if command -v chronyc &> /dev/null; then
        chronyc makestep &> /dev/null && echo "$CURRENT_HOUR" > "$LAST_SYNC_FILE"
    elif command -v timedatectl &> /dev/null; then
        timedatectl set-ntp true &> /dev/null && echo "$CURRENT_HOUR" > "$LAST_SYNC_FILE"
    fi
fi

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$(dirname "$SCRIPT_DIR")/giipAgent.cnf"
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="${SCRIPT_DIR}/giipAgent.cnf"
fi
. "$CONFIG_FILE"

# Variables
LOG_FILE="/var/log/giip-auto-discover.log"
DISCOVERY_SCRIPT="${SCRIPT_DIR}/giipscripts/auto-discover-linux.sh"
AGENT_VERSION="1.72"

# Check if auto-discovery script exists
if [ ! -f "$DISCOVERY_SCRIPT" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Discovery script not found: $DISCOVERY_SCRIPT" >> "$LOG_FILE"
    exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ========================================" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting auto-discovery..." >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Config: $CONFIG_FILE" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Discovery script: $DISCOVERY_SCRIPT" >> "$LOG_FILE"

# Make discovery script executable
chmod +x "$DISCOVERY_SCRIPT"

# Run discovery and capture JSON
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Collecting system information..." >> "$LOG_FILE"
DISCOVERY_JSON=$("$DISCOVERY_SCRIPT" 2>&1)

if [ $? -ne 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ ERROR: Discovery script failed" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Error details saved to: $TEMP_JSON" >> "$LOG_FILE"
    # Save error output to file instead of logging
    echo "$DISCOVERY_JSON" > "/tmp/giip-discovery-error-$$.txt"
    exit 1
fi

# Log statistics
SOFTWARE_COUNT=$(echo "$DISCOVERY_JSON" | grep -o '"name":' | wc -l | awk '{print $1}')
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Collected service-related packages: $SOFTWARE_COUNT" >> "$LOG_FILE"

# Add agent version to JSON (before last })
DISCOVERY_JSON=$(echo "$DISCOVERY_JSON" | sed "s/}$/, \"agent_version\": \"$AGENT_VERSION\" }/")

# Save to temp file for debugging (with PID)
TEMP_JSON="/tmp/giip-discovery-$$.json"
echo "$DISCOVERY_JSON" > "$TEMP_JSON"

# Also save to fixed location for easy access
LATEST_JSON="/var/log/giip-discovery-latest.json"
DISCOVERY_FILE="$LATEST_JSON"  # Set DISCOVERY_FILE for kvsput.sh
echo "$DISCOVERY_JSON" > "$LATEST_JSON"
chmod 644 "$LATEST_JSON"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Discovery files created:" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] - Temp: $TEMP_JSON ($(wc -c < "$TEMP_JSON") bytes)" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] - Latest: $LATEST_JSON ($(wc -c < "$LATEST_JSON") bytes)" >> "$LOG_FILE"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] JSON saved to:" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] - Latest: $LATEST_JSON" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] - Temp: $TEMP_JSON" >> "$LOG_FILE"

# Call API v2 (giipApiSk2 - SK authentication with advanced JSON handling)
# IMPORTANT: Use apiaddrv2 (giipApiSk2) NOT Endpoint (giipApi)
# Reason: giipApi=session-based(AK), giipApiSk2=SK-based with better JSON parsing

# Build API URL with Function Code if available
API_URL="${apiaddrv2}"
if [ -n "$apiaddrcode" ]; then
    API_URL="${API_URL}?code=${apiaddrcode}"
fi

# Extract hostname from JSON for logging
HOSTNAME=$(echo "$DISCOVERY_JSON" | grep -o '"hostname":\s*"[^"]*"' | sed 's/"hostname":\s*"//' | sed 's/"$//')

# Extract network count for logging
NETWORK_COUNT=$(echo "$DISCOVERY_JSON" | grep -o '"network":\s*\[' | wc -l)
if [ "$NETWORK_COUNT" -gt 0 ]; then
    NETWORK_ITEMS=$(echo "$DISCOVERY_JSON" | grep -oP '"name"\s*:\s*"\K[^"]+' | wc -l)
else
    NETWORK_ITEMS=0
fi

# Extract software and service counts
SOFTWARE_COUNT=$(echo "$DISCOVERY_JSON" | grep -oP '"software"\s*:\s*\[\s*\{' | wc -l)
if [ "$SOFTWARE_COUNT" -eq 0 ]; then
    SOFTWARE_COUNT=$(echo "$DISCOVERY_JSON" | grep -c '"software"' | grep -v '^\s*\[\s*\]')
fi

SERVICE_COUNT=$(echo "$DISCOVERY_JSON" | grep -oP '"services"\s*:\s*\[\s*\{' | wc -l)
if [ "$SERVICE_COUNT" -eq 0 ]; then
    SERVICE_COUNT=$(echo "$DISCOVERY_JSON" | grep -c '"services"' | grep -v '^\s*\[\s*\]')
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sending data to API v2 (giipApiSk2) for host: $HOSTNAME..." >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Data summary: Network interfaces=$NETWORK_ITEMS, Software=$SOFTWARE_COUNT, Services=$SERVICE_COUNT" >> "$LOG_FILE"

# Save network data to tmp/network.log (relative to script directory)
NETWORK_LOG="${SCRIPT_DIR}/tmp/network.log"
mkdir -p "${SCRIPT_DIR}/tmp"
echo "========================================" > "$NETWORK_LOG"
echo "Network Discovery Log" >> "$NETWORK_LOG"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')" >> "$NETWORK_LOG"
echo "Hostname: $HOSTNAME" >> "$NETWORK_LOG"
echo "========================================" >> "$NETWORK_LOG"
echo "" >> "$NETWORK_LOG"

# Log network details for debugging
if [ "$NETWORK_ITEMS" -gt 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Network interfaces found:" >> "$LOG_FILE"
    echo "Network Interfaces Found: $NETWORK_ITEMS" >> "$NETWORK_LOG"
    echo "" >> "$NETWORK_LOG"
    
    echo "$DISCOVERY_JSON" | grep -oP '"network"\s*:\s*\[\K[^\]]+' | grep -oP '\{[^}]+\}' | while read -r iface; do
        iface_name=$(echo "$iface" | grep -oP '"name"\s*:\s*"\K[^"]+')
        iface_ipv4=$(echo "$iface" | grep -oP '"ipv4"\s*:\s*"\K[^"]+')
        iface_ipv6=$(echo "$iface" | grep -oP '"ipv6"\s*:\s*"\K[^"]+')
        iface_mac=$(echo "$iface" | grep -oP '"mac"\s*:\s*"\K[^"]+')
        
        echo "[$(date '+%Y-%m-%d %H:%M:%S')]   - $iface_name: IPv4=$iface_ipv4, MAC=$iface_mac" >> "$LOG_FILE"
        
        # Write to network.log
        echo "Interface: $iface_name" >> "$NETWORK_LOG"
        echo "  IPv4: ${iface_ipv4:-<empty>}" >> "$NETWORK_LOG"
        echo "  IPv6: ${iface_ipv6:-<empty>}" >> "$NETWORK_LOG"
        echo "  MAC:  ${iface_mac:-<empty>}" >> "$NETWORK_LOG"
        echo "" >> "$NETWORK_LOG"
    done
    
    # Also save raw network JSON
    echo "========================================" >> "$NETWORK_LOG"
    echo "Raw JSON Network Data:" >> "$NETWORK_LOG"
    echo "========================================" >> "$NETWORK_LOG"
    echo "$DISCOVERY_JSON" | grep -oP '"network"\s*:\s*\[[^\]]+\]' >> "$NETWORK_LOG"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Network data saved to: $NETWORK_LOG" >> "$LOG_FILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ WARNING: No network interfaces collected!" >> "$LOG_FILE"
    echo "No network interfaces found!" >> "$NETWORK_LOG"
fi

# Upload network diagnostic data to KVS for debugging
KVSPUT_SCRIPT="${SCRIPT_DIR}/giipscripts/kvsput.sh"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checking KVS upload conditions:" >> "$LOG_FILE"
if [ ! -f "$KVSPUT_SCRIPT" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] - KVSPUT_SCRIPT not found: $KVSPUT_SCRIPT" >> "$LOG_FILE"
fi
if [ ! -f "$DISCOVERY_FILE" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] - DISCOVERY_FILE not found: $DISCOVERY_FILE" >> "$LOG_FILE"
fi

# ====================================================================
# API 호출 전: 수집된 원본 JSON을 KVS에 저장 (진단용)
# ====================================================================
if [ -f "$KVSPUT_SCRIPT" ] && [ -f "$DISCOVERY_FILE" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Uploading RAW discovery JSON to KVS (before API call)..." >> "$LOG_FILE"
    
    # Pass CONFIG_FILE to kvsput.sh (redirect stderr to log, not full response)
    if CONFIG_FILE="$CONFIG_FILE" bash "$KVSPUT_SCRIPT" "$DISCOVERY_FILE" autodiscover_raw 2>> "$LOG_FILE"; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ KVS upload successful (autodiscover_raw)" >> "$LOG_FILE"
    else
        KVS_EXIT_CODE=$?
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ KVS upload failed (exit code: $KVS_EXIT_CODE, non-critical)" >> "$LOG_FILE"
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ Skipping raw JSON KVS upload - prerequisites missing" >> "$LOG_FILE"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Uploading discovery data to KVS (kfactor: autodiscover)..." >> "$LOG_FILE"

if [ -f "$KVSPUT_SCRIPT" ] && [ -f "$DISCOVERY_FILE" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Uploading discovery data to KVS (kfactor: autodiscover)..." >> "$LOG_FILE"
    
    # Pass CONFIG_FILE to kvsput.sh (redirect stderr to log, not full response)
    if CONFIG_FILE="$CONFIG_FILE" bash "$KVSPUT_SCRIPT" "$DISCOVERY_FILE" autodiscover 2>> "$LOG_FILE"; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ KVS upload successful" >> "$LOG_FILE"
    else
        KVS_EXIT_CODE=$?
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ KVS upload failed (exit code: $KVS_EXIT_CODE, non-critical)" >> "$LOG_FILE"
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ Skipping discovery data KVS upload - prerequisites missing" >> "$LOG_FILE"
fi

# giipApiSk2 pattern (same as kvsput.sh):
# - text: command name + parameter names (NO sk, NO values)
# - token: SK authentication (separate parameter, auto-merged by giipfaw)
# - jsondata: actual parameter values in JSON format
RESPONSE=$(curl -s -X POST "$API_URL" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "text=AgentAutoRegister hostname jsondata" \
    --data-urlencode "token=$sk" \
    --data-urlencode "jsondata=$DISCOVERY_JSON" 2>&1)

HTTP_CODE=$?

if [ $HTTP_CODE -eq 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] API Response: $RESPONSE" >> "$LOG_FILE"
    
    # Check if response indicates success
    RSTVAL=$(echo "$RESPONSE" | grep -oP '"RstVal"\s*:\s*\K\d+')
    ACTION=$(echo "$RESPONSE" | grep -oP '"action"\s*:\s*"\K[^"]+')
    
    if [ "$RSTVAL" = "200" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ SUCCESS: Action=$ACTION, Network data sent to DB" >> "$LOG_FILE"
        
        # ====================================================================
        # API 성공 후: API 응답도 KVS에 저장 (성공 기록)
        # ====================================================================
        if [ -f "$KVSPUT_SCRIPT" ]; then
            API_RESPONSE_JSON="${TEMP_JSON%.json}-api-response.json"
            cat > "$API_RESPONSE_JSON" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "status": "success",
  "api_response": $(echo "$RESPONSE" | jq -Rs . 2>/dev/null || echo "\"$RESPONSE\""),
  "action": "$ACTION"
}
EOF
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Uploading API success response to KVS..." >> "$LOG_FILE"
            bash "$KVSPUT_SCRIPT" "$API_RESPONSE_JSON" autodiscover_api_response >> "$LOG_FILE" 2>&1 || true
            rm -f "$API_RESPONSE_JSON"
        fi
    elif [ "$RSTVAL" = "401" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ ERROR: Authentication failed - Invalid SK" >> "$LOG_FILE"
        
        # ====================================================================
        # API 인증 실패: 에러를 KVS에 저장
        # ====================================================================
        if [ -f "$KVSPUT_SCRIPT" ]; then
            ERROR_JSON="${TEMP_JSON%.json}-api-auth-error.json"
            cat > "$ERROR_JSON" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "status": "error",
  "error_type": "authentication_failed",
  "rstval": "$RSTVAL",
  "api_response": $(echo "$RESPONSE" | jq -Rs . 2>/dev/null || echo "\"$RESPONSE\"")
}
EOF
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Uploading API auth error to KVS..." >> "$LOG_FILE"
            bash "$KVSPUT_SCRIPT" "$ERROR_JSON" autodiscover_api_error >> "$LOG_FILE" 2>&1 || true
            rm -f "$ERROR_JSON"
        fi
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ WARNING: Unexpected response code: $RSTVAL" >> "$LOG_FILE"
        
        # ====================================================================
        # API 예상 외 응답: 경고를 KVS에 저장
        # ====================================================================
        if [ -f "$KVSPUT_SCRIPT" ]; then
            WARN_JSON="${TEMP_JSON%.json}-api-warn.json"
            cat > "$WARN_JSON" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "status": "warning",
  "error_type": "unexpected_response_code",
  "rstval": "$RSTVAL",
  "action": "$ACTION",
  "api_response": $(echo "$RESPONSE" | jq -Rs . 2>/dev/null || echo "\"$RESPONSE\"")
}
EOF
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Uploading API unexpected response to KVS..." >> "$LOG_FILE"
            bash "$KVSPUT_SCRIPT" "$WARN_JSON" autodiscover_api_warn >> "$LOG_FILE" 2>&1 || true
            rm -f "$WARN_JSON"
        fi
    fi
    
    # Extract lssn from response if this is first registration
    if [ "$lssn" = "0" ]; then
        NEW_LSSN=$(echo "$RESPONSE" | grep -oP '"lssn":\s*\K\d+')
        if [ -n "$NEW_LSSN" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Received LSSN: $NEW_LSSN" >> "$LOG_FILE"
            # Update config file
            sed -i "s/lssn=\"0\"/lssn=\"$NEW_LSSN\"/" "$CONFIG_FILE"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Updated giipAgent.cnf with LSSN: $NEW_LSSN" >> "$LOG_FILE"
        fi
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ ERROR: API call failed with HTTP code $HTTP_CODE" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Response: $RESPONSE" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Check network connectivity and API endpoint" >> "$LOG_FILE"
    
    # ====================================================================
    # API 호출 실패: 에러 정보를 KVS에 저장
    # ====================================================================
    # Upload error diagnostic to KVS
    if [ -f "$KVSPUT_SCRIPT" ]; then
        ERROR_JSON="${TEMP_JSON%.json}-api-call-error.json"
        cat > "$ERROR_JSON" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "status": "error",
  "error_type": "api_call_failed",
  "http_code": $HTTP_CODE,
  "api_url": "$API_URL",
  "response": $(echo "$RESPONSE" | jq -Rs . 2>/dev/null || echo "\"$RESPONSE\"")
}
EOF
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Uploading API call error diagnostic to KVS..." >> "$LOG_FILE"
        bash "$KVSPUT_SCRIPT" "$ERROR_JSON" autodiscover_api_call_error >> "$LOG_FILE" 2>&1 || true
        rm -f "$ERROR_JSON"
    fi
fi

# Cleanup temp file (keep for debugging if error occurred)
if [ "$RSTVAL" = "200" ]; then
    rm -f "$TEMP_JSON"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Temp JSON file cleaned up" >> "$LOG_FILE"
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠ Temp JSON file kept for debugging: $TEMP_JSON" >> "$LOG_FILE"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ========================================" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Auto-discovery completed" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"
