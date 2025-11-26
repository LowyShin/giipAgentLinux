#!/bin/bash
# check-process-flood.sh - Detect and Handle Process Flooding
# Purpose: Monitor for abnormally high process counts and take action
# Author: GIIP Team
# Date: 2025-11-12
# kFactor: process_flood_check

# ============================================================================
# Initialize Script Paths (Following MODULAR_ARCHITECTURE.md Section 5)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
CONFIG_FILE="$SCRIPT_DIR/../giipAgent.cnf"

# ============================================================================
# Configuration
# ============================================================================

# Process count threshold (alert if more than this)
THRESHOLD_WARNING=50
THRESHOLD_CRITICAL=100

# Services to monitor (add more as needed)
MONITORED_SERVICES=(
    "postfix"
    "sendmail"
    "apache2"
    "httpd"
    "nginx"
    "mysql"
    "mariadb"
)

# Log file
LOG_DIR="${SCRIPT_DIR}/log"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/process-flood-check_$(date +%Y%m%d).log"

# ============================================================================
# Logging Function
# ============================================================================

log_message() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# ============================================================================
# Load KVS Functions (Optional - for reporting to DB)
# ============================================================================

USE_KVS=false
if [ -f "${LIB_DIR}/common.sh" ] && [ -f "${LIB_DIR}/kvs.sh" ]; then
    source "${LIB_DIR}/common.sh"
    load_config "../giipAgent.cnf" 2>/dev/null
    if [ $? -eq 0 ] && [ -n "$lssn" ] && [ -n "$sk" ]; then
        source "${LIB_DIR}/kvs.sh"
        USE_KVS=true
        log_message "✅ KVS logging enabled (LSSN: $lssn)"
    fi
fi

# ============================================================================
# Process Flood Detection Functions
# ============================================================================

# Function: Count processes by command name
count_processes_by_command() {
    local command_name="$1"
    ps -ef | grep -v grep | grep -c "$command_name"
}

# Function: Get process details
get_process_details() {
    local command_name="$1"
    ps -ef | grep -v grep | grep "$command_name" | head -20
}

# Function: Get service status
get_service_status() {
    local service_name="$1"
    
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        echo "running"
    elif systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
        echo "enabled"
    elif systemctl list-unit-files | grep -q "^${service_name}.service.*masked"; then
        echo "masked"
    else
        echo "inactive"
    fi
}

# Function: Stop and disable service
stop_and_disable_service() {
    local service_name="$1"
    local action="$2"  # "stop", "disable", or "mask"
    
    log_message "🛑 Attempting to $action service: $service_name"
    
    case "$action" in
        stop)
            sudo systemctl stop "$service_name" 2>&1 | tee -a "$LOG_FILE"
            ;;
        disable)
            sudo systemctl disable "$service_name" 2>&1 | tee -a "$LOG_FILE"
            ;;
        mask)
            sudo systemctl mask "$service_name" 2>&1 | tee -a "$LOG_FILE"
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        log_message "✅ Successfully ${action}ed $service_name"
        return 0
    else
        log_message "❌ Failed to $action $service_name"
        return 1
    fi
}

# Function: Kill processes by name
kill_processes() {
    local command_name="$1"
    local signal="${2:-TERM}"  # Default: SIGTERM, can use KILL for force
    
    log_message "⚠️  Killing processes: $command_name (signal: $signal)"
    
    if [ "$signal" = "KILL" ]; then
        sudo pkill -9 "$command_name" 2>&1 | tee -a "$LOG_FILE"
    else
        sudo pkill "$command_name" 2>&1 | tee -a "$LOG_FILE"
    fi
    
    sleep 2
    
    # Check if processes still exist
    local remaining=$(count_processes_by_command "$command_name")
    log_message "   Remaining processes: $remaining"
    
    return $remaining
}

# ============================================================================
# Main Process Flood Check
# ============================================================================

log_message "========================================="
log_message "🔍 Process Flood Check Started"
log_message "========================================="

# Check each monitored service
ALERTS_FOUND=false
CRITICAL_FOUND=false
FLOOD_REPORT=""

for service in "${MONITORED_SERVICES[@]}"; do
    # Count processes
    process_count=$(count_processes_by_command "$service")
    
    if [ "$process_count" -eq 0 ]; then
        continue  # Skip if no processes
    fi
    
    # Get service status
    service_status=$(get_service_status "$service")
    
    # Check thresholds
    if [ "$process_count" -ge "$THRESHOLD_CRITICAL" ]; then
        log_message ""
        log_message "🚨 CRITICAL: $service has $process_count processes (threshold: $THRESHOLD_CRITICAL)"
        log_message "   Service Status: $service_status"
        log_message ""
        log_message "📋 Process Details (first 20):"
        get_process_details "$service" | tee -a "$LOG_FILE"
        log_message ""
        
        CRITICAL_FOUND=true
        ALERTS_FOUND=true
        
        # Build report for KVS
        FLOOD_REPORT="${FLOOD_REPORT}${service}:CRITICAL:${process_count},"
        
        # AUTO-REMEDIATION (CRITICAL)
        log_message "🔧 AUTO-REMEDIATION: Starting automatic cleanup..."
        log_message ""
        
        # Step 1: Stop service
        stop_and_disable_service "$service" "stop"
        sleep 2
        
        # Step 2: Kill remaining processes (SIGTERM)
        kill_processes "$service" "TERM"
        sleep 2
        
        # Step 3: Force kill if still running (SIGKILL)
        remaining=$(count_processes_by_command "$service")
        if [ "$remaining" -gt 0 ]; then
            log_message "⚠️  Processes still running. Force killing..."
            kill_processes "$service" "KILL"
        fi
        
        # Step 4: Disable service
        stop_and_disable_service "$service" "disable"
        
        # Step 5: Mask service (prevent restart)
        stop_and_disable_service "$service" "mask"
        
        # Step 6: Verify cleanup
        final_count=$(count_processes_by_command "$service")
        if [ "$final_count" -eq 0 ]; then
            log_message "✅ SUCCESS: All $service processes removed"
        else
            log_message "⚠️  WARNING: $final_count $service processes still running"
        fi
        log_message ""
        
    elif [ "$process_count" -ge "$THRESHOLD_WARNING" ]; then
        log_message ""
        log_message "⚠️  WARNING: $service has $process_count processes (threshold: $THRESHOLD_WARNING)"
        log_message "   Service Status: $service_status"
        log_message ""
        
        ALERTS_FOUND=true
        FLOOD_REPORT="${FLOOD_REPORT}${service}:WARNING:${process_count},"
        
        # Show process details but don't auto-kill
        log_message "📋 Process Details (first 10):"
        get_process_details "$service" | head -10 | tee -a "$LOG_FILE"
        log_message ""
        log_message "💡 Manual action required:"
        log_message "   To stop:    sudo systemctl stop $service"
        log_message "   To disable: sudo systemctl disable $service"
        log_message "   To mask:    sudo systemctl mask $service"
        log_message "   To kill:    sudo pkill -9 $service"
        log_message ""
    fi
done

# ============================================================================
# Summary Report
# ============================================================================

log_message "========================================="
log_message "📊 Process Flood Check Summary"
log_message "========================================="

if [ "$ALERTS_FOUND" = true ]; then
    if [ "$CRITICAL_FOUND" = true ]; then
        log_message "🚨 Status: CRITICAL - Auto-remediation performed"
    else
        log_message "⚠️  Status: WARNING - Manual action required"
    fi
    
    # Save to KVS if enabled
    if [ "$USE_KVS" = true ]; then
        FLOOD_JSON="{
            \"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\",
            \"hostname\":\"$(hostname)\",
            \"alerts\":\"$FLOOD_REPORT\",
            \"critical\":$CRITICAL_FOUND,
            \"log_file\":\"$LOG_FILE\"
        }"
        
        log_message ""
        log_message "📤 Saving to KVS (kFactor: process_flood_check)..."
        kvs_put "lssn" "$lssn" "process_flood_check" "$FLOOD_JSON"
    fi
else
    log_message "✅ Status: OK - No process flooding detected"
fi

log_message ""
log_message "📄 Full log: $LOG_FILE"
log_message "========================================="
log_message ""

# Exit with appropriate code
if [ "$CRITICAL_FOUND" = true ]; then
    exit 2  # Critical
elif [ "$ALERTS_FOUND" = true ]; then
    exit 1  # Warning
else
    exit 0  # OK
fi
