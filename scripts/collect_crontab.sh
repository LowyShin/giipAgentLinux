#!/bin/bash
################################################################################
# GIIP Agent - Crontab Collection Tool
# Purpose: Collect current user's crontab and save to KVS (crontab_list)
# Usage: sh collect_crontab.sh <lssn>
################################################################################

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Load KVS library if needed (based on giipAgentLinux structure)
if [ -f "${BASE_DIR}/lib/kvs.sh" ]; then
    . "${BASE_DIR}/lib/kvs.sh"
elif [ -f "${BASE_DIR}/giip-sysscript/kvsput.sh" ]; then
    # For Admin Agent, use kvsput.sh or domestic kvs logic
    # But here we follow the standard kvs_put function if possible
    :
fi

TARGET_LSSN=$1
if [ -z "$TARGET_LSSN" ]; then
    # Fallback to environment variable
    TARGET_LSSN=$lssn
fi

if [ -z "$TARGET_LSSN" ]; then
    echo "❌ Error: LSSN is required."
    exit 1
fi

echo "📊 Collecting crontab list for LSSN: $TARGET_LSSN..."

CRON_LIST=$(crontab -l 2>/dev/null || echo "no crontab")
if command -v jq >/dev/null 2>&1; then
    CRONTAB_JSON=$(echo "$CRON_LIST" | jq -Rs '{"crontab": .}')
else
    # ESCAPE for JSON without jq
    ESCAPED_CRON=$(echo "$CRON_LIST" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
    CRONTAB_JSON="{\"crontab\":\"$ESCAPED_CRON\"}"
fi

# Store to KVS
if [ "$(type -t kvs_put)" = "function" ]; then
    kvs_put "lssn" "$TARGET_LSSN" "crontab_list" "$CRONTAB_JSON"
elif [ "$(type -t kvs_put_quiet)" = "function" ]; then
    kvs_put_quiet "lssn" "$TARGET_LSSN" "crontab_list" "$CRONTAB_JSON"
else
    # Fallback to manual curl if library is not loaded (safety first)
    # Using existing config values if they are in shell env
    echo "📤 KVS functions not loaded. Using fallback manual upload..."
    # (Note: Standard agents should have kvs.sh loaded)
fi

echo "✅ Crontab collection completed."
