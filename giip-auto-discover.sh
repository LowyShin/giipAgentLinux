#!/bin/bash
# giipAgent Auto-Discovery Integration
# Call this script periodically (every 5 minutes) from cron
# Example crontab: */5 * * * * /path/to/giip-auto-discover.sh

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

# Make discovery script executable
chmod +x "$DISCOVERY_SCRIPT"

# Run discovery and capture JSON
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting auto-discovery..." >> "$LOG_FILE"
DISCOVERY_JSON=$("$DISCOVERY_SCRIPT" 2>&1)

if [ $? -ne 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Discovery script failed" >> "$LOG_FILE"
    echo "$DISCOVERY_JSON" >> "$LOG_FILE"
    exit 1
fi

# Log statistics
SOFTWARE_COUNT=$(echo "$DISCOVERY_JSON" | grep -o '"name":' | wc -l | awk '{print $1}')
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Collected service-related packages: $SOFTWARE_COUNT" >> "$LOG_FILE"

# Add agent version to JSON (before last })
DISCOVERY_JSON=$(echo "$DISCOVERY_JSON" | sed "s/}$/, \"agent_version\": \"$AGENT_VERSION\" }/")

# Save to temp file for debugging
TEMP_JSON="/tmp/giip-discovery-$$.json"
echo "$DISCOVERY_JSON" > "$TEMP_JSON"

# Call API v2 (giipApiSk2 - SK authentication with advanced JSON handling)
# IMPORTANT: Use apiaddrv2 (giipApiSk2) NOT Endpoint (giipApi)
# Reason: giipApi=session-based(AK), giipApiSk2=SK-based with better JSON parsing
API_URL="${apiaddrv2}"

# Extract hostname from JSON for API call
HOSTNAME=$(echo "$DISCOVERY_JSON" | grep -o '"hostname":\s*"[^"]*"' | sed 's/"hostname":\s*"//' | sed 's/"$//')
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sending data to API v2 (giipApiSk2) for host: $HOSTNAME..." >> "$LOG_FILE"

# Use form-urlencoded format with SK authentication
# Note: text parameter includes actual hostname from discovery data
RESPONSE=$(curl -s -X POST "$API_URL" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "text=AgentAutoRegister $HOSTNAME jsondata" \
    --data-urlencode "jsondata=$DISCOVERY_JSON" \
    --data-urlencode "sk=$sk" 2>&1)

HTTP_CODE=$?

if [ $HTTP_CODE -eq 0 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $RESPONSE" >> "$LOG_FILE"
    
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
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: API call failed with code $HTTP_CODE" >> "$LOG_FILE"
    echo "$RESPONSE" >> "$LOG_FILE"
fi

# Cleanup
rm -f "$TEMP_JSON"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Auto-discovery completed" >> "$LOG_FILE"
