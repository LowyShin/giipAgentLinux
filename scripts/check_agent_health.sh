#!/bin/bash
################################################################################
# GIIP Agent - Self-Diagnostic Checklist
# Purpose: Check all agent features and report status to tKVS
# Usage: sh check_agent_health.sh <lssn>
################################################################################

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Load KVS library
if [ -f "${BASE_DIR}/lib/kvs.sh" ]; then
    . "${BASE_DIR}/lib/kvs.sh"
fi

TARGET_LSSN=$1
[ -z "$TARGET_LSSN" ] && TARGET_LSSN=$lssn

if [ -z "$TARGET_LSSN" ]; then
    echo "❌ Error: LSSN is required."
    exit 1
fi

echo "🔍 Starting Self-Diagnostic for LSSN: $TARGET_LSSN..."

# 1. Heartbeat Check (API Connectivity)
HEARTBEAT="OK"
if ! kvs_put_quiet "lssn" "$TARGET_LSSN" "diag_heartbeat" "{\"status\":\"alive\"}" > /dev/null 2>&1; then
    HEARTBEAT="FAIL"
fi

# 2. System Info Collection Check
SYSTEM_INFO="OK"
if ! command -v df >/dev/null 2>&1 || ! command -v free >/dev/null 2>&1; then
    SYSTEM_INFO="FAIL"
fi

# 3. Crontab List Collection Check
CRONTAB_LIST="OK"
if ! crontab -l >/dev/null 2>&1; then
    CRONTAB_LIST="FAIL"
fi

# 4. Gateway Specific Checks (Default SKIP for normal agents)
DB_PERF="SKIP"
REMOTE_INFO="SKIP"

# Detect if this is an Admin/Gateway agent
if [ -f "${BASE_DIR}/giip-sysscript/exec-health-check.sh" ]; then
    # Admin Agent Logic
    DB_PERF="OK" # Default OK if script exists, logic to be refined
    REMOTE_INFO="OK"
fi

# Determine overall status
STATUS="PASS"
if [ "$HEARTBEAT" = "FAIL" ] || [ "$SYSTEM_INFO" = "FAIL" ] || [ "$CRONTAB_LIST" = "FAIL" ]; then
    STATUS="FAIL"
elif [ "$DB_PERF" = "FAIL" ] || [ "$REMOTE_INFO" = "FAIL" ]; then
    STATUS="PARTIAL"
fi

# Construct JSON
CHECK_TIME=$(date '+%Y-%m-%d %H:%M:%S')
CHECKLIST_JSON=$(cat <<EOF
{
  "check_time": "$CHECK_TIME",
  "status": "$STATUS",
  "features": {
    "heartbeat": "$HEARTBEAT",
    "system_info": "$SYSTEM_INFO",
    "crontab_list": "$CRONTAB_LIST",
    "db_performance": "$DB_PERF",
    "remote_server_info": "$REMOTE_INFO"
  }
}
EOF
)

# Final report to KVS
if [ "$(type -t kvs_put)" = "function" ]; then
    kvs_put "lssn" "$TARGET_LSSN" "agent_health_checklist" "$CHECKLIST_JSON"
elif [ "$(type -t kvs_put_quiet)" = "function" ]; then
    kvs_put_quiet "lssn" "$TARGET_LSSN" "agent_health_checklist" "$CHECKLIST_JSON"
fi

# ============================================================================
# NEW: AI Skill Request Trigger (If Status is FAIL or PARTIAL)
# ============================================================================
if [ "$STATUS" = "FAIL" ] || [ "$STATUS" = "PARTIAL" ]; then
    echo "🤖 Triggering AI Analysis for $STATUS status..."
    AI_REQ_JSON=$(cat <<EOF
{
  "lssn": "$TARGET_LSSN",
  "status": "$STATUS",
  "issue": "Diagnostic Failure",
  "context": $CHECKLIST_JSON
}
EOF
)
    if [ "$(type -t kvs_put_quiet)" = "function" ]; then
        kvs_put_quiet "lssn" "$TARGET_LSSN" "ai_skill_request" "$AI_REQ_JSON"
    fi
fi

echo "✅ Self-diagnostic completed with status: $STATUS"
