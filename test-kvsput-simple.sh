#!/bin/bash
#
# Simple KVSPut Test Script
# Tests KVSPut API with minimal test data
#
# Usage:
#   bash test-kvsput-simple.sh
#
# Requirements:
#   - giipAgent.cnf with apiaddrv2, apiaddrcode, sk, lssn configured
#   - jq command installed
#   - curl command installed
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "KVSPut Simple Test"
echo "=========================================="
echo ""

# Detect config file (DO NOT commit giipAgent.cnf to public repo!)
CONFIG_FILE="$SCRIPT_DIR/giipAgent.cnf"
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="$SCRIPT_DIR/../giipAgent.cnf"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ ERROR: giipAgent.cnf not found"
    echo ""
    echo "Searched locations:"
    echo "  - $SCRIPT_DIR/giipAgent.cnf"
    echo "  - $SCRIPT_DIR/../giipAgent.cnf"
    echo ""
    echo "Please create giipAgent.cnf with:"
    echo "  apiaddrv2=\"https://giipfaw.azurewebsites.net/api/giipApiSk2\""
    echo "  apiaddrcode=\"<your_function_code>\""
    echo "  sk=\"<your_secret_key>\""
    echo "  lssn=\"<your_server_id>\""
    exit 1
fi

echo "✓ Config: $CONFIG_FILE"
echo ""

# Read config (⚠️ NEVER hardcode these values in public repo!)
ENDPOINT=$(grep "^apiaddrv2=" "$CONFIG_FILE" | cut -d= -f2 | tr -d '"' | tr -d "'")
CODE=$(grep "^apiaddrcode=" "$CONFIG_FILE" | cut -d= -f2 | tr -d '"' | tr -d "'")
TOKEN=$(grep "^sk=" "$CONFIG_FILE" | cut -d= -f2 | tr -d '"' | tr -d "'")
KKEY=$(grep "^lssn=" "$CONFIG_FILE" | cut -d= -f2 | tr -d '"' | tr -d "'")

# Validate config
if [ -z "$ENDPOINT" ]; then
    echo "❌ ERROR: apiaddrv2 not found in $CONFIG_FILE"
    exit 1
fi

if [ -z "$TOKEN" ]; then
    echo "❌ ERROR: sk not found in $CONFIG_FILE"
    exit 1
fi

if [ -z "$KKEY" ]; then
    echo "❌ ERROR: lssn not found in $CONFIG_FILE"
    exit 1
fi

# Check required commands
if ! command -v jq >/dev/null 2>&1; then
    echo "❌ ERROR: jq command not found. Please install jq."
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "❌ ERROR: curl command not found. Please install curl."
    exit 1
fi

echo "Configuration loaded:"
echo "  Endpoint: $ENDPOINT"
echo "  Code: ${CODE:0:20}..."
echo "  Token: ${TOKEN:0:10}... (from sk in config)"
echo "  KKey: $KKEY (from lssn in config)"
echo ""

# Create minimal test JSON
TEST_JSON="/tmp/kvsput-test-$$.json"
cat > "$TEST_JSON" <<EOF
{
  "hostname": "test-$(date +%s)",
  "os": "Test OS",
  "cpu": "Test CPU",
  "cpu_cores": 1,
  "memory_gb": 1,
  "disk_gb": 10,
  "agent_version": "test",
  "ipv4_global": "127.0.0.1",
  "ipv4_local": "127.0.0.1",
  "network": [{"name": "eth0", "ipv4": "127.0.0.1", "mac": "00:00:00:00:00:00"}],
  "software": []
}
EOF

echo "✓ Test JSON: $TEST_JSON"
echo ""

# Compact JSON
JSON_COMPACT=$(jq -c . "$TEST_JSON")

# Build jsondata
JSON_PAYLOAD=$(jq -n \
  --arg kType "lssn" \
  --arg kKey "$KKEY" \
  --arg kFactor "simpletest" \
  --argjson kValue "$JSON_COMPACT" \
  '{kType: $kType, kKey: $kKey, kFactor: $kFactor, kValue: $kValue}')

# Build POST data
KVSP_TEXT="KVSPut kType kKey kFactor kValue"
POST_DATA="text=$(printf "%s" "$KVSP_TEXT" | jq -sRr @uri)"
POST_DATA+="&token=$(printf "%s" "$TOKEN" | jq -sRr @uri)"
POST_DATA+="&jsondata=$(printf "%s" "$JSON_PAYLOAD" | jq -sRr @uri)"

# Save to temp file
TMP_POST="/tmp/kvsput-post-$$.txt"
echo "$POST_DATA" > "$TMP_POST"

echo "Sending request..."
echo "  text: $KVSP_TEXT"
echo "  token: ${TOKEN:0:10}..."
echo ""

# Send request
RESPONSE=$(curl -s -X POST "${ENDPOINT}?code=${CODE}" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-binary "@$TMP_POST")

echo "=========================================="
echo "Response:"
echo "=========================================="

# Save raw response for debugging
echo "$RESPONSE" > /tmp/kvsput-response-$$.txt
echo "[DEBUG] Raw response saved to: /tmp/kvsput-response-$$.txt"
echo "[DEBUG] Response length: ${#RESPONSE} bytes"
echo ""

# Show raw response first
echo "--- Raw Response ---"
echo "$RESPONSE"
echo "--- End Raw Response ---"
echo ""

# Try to parse as JSON
if [ -n "$RESPONSE" ] && echo "$RESPONSE" | jq . >/dev/null 2>&1; then
    echo "--- Parsed JSON ---"
    echo "$RESPONSE" | jq .
    
    # Check debug info
    if echo "$RESPONSE" | jq -e '.debug' >/dev/null 2>&1; then
        echo ""
        echo "Debug Info:"
        echo "$RESPONSE" | jq '.debug'
    fi
else
    echo "⚠ Response is empty or not valid JSON"
fi

echo ""

# Check for errors
if [ -z "$RESPONSE" ]; then
    echo "❌ Empty response from server"
    echo ""
    echo "Possible causes:"
    echo "  1. Network issue"
    echo "  2. Azure Function not responding"
    echo "  3. Wrong endpoint URL"
    RESULT=1
elif echo "$RESPONSE" | grep -qi '"error"'; then
    echo "❌ ERROR detected in response"
    RESULT=1
elif echo "$RESPONSE" | grep -qi 'RstVal.*411\|"RstVal":411'; then
    echo "❌ 411 Error: Server not found in tLSvr or wrong CGSn"
    echo ""
    echo "Possible causes:"
    echo "  1. SK token invalid or not in tSecretKey"
    echo "  2. Server (lssn=$KKEY) not in tLSvr table"
    echo "  3. Server CGSn doesn't match SK's CGSn"
    RESULT=1
elif echo "$RESPONSE" | grep -qi 'RstVal.*401\|"RstVal":401'; then
    echo "❌ 401 Error: Authentication failed"
    RESULT=1
elif echo "$RESPONSE" | grep -qi 'RstVal.*200\|"RstVal":200'; then
    echo "✅ Success! (RstVal=200)"
    RESULT=0
else
    echo "⚠ Unknown response format (check raw response above)"
    RESULT=1
fi

# Cleanup
rm -f "$TEST_JSON" "$TMP_POST"

echo ""
if [ $RESULT -eq 0 ]; then
    echo "Cleaned up: $TEST_JSON, $TMP_POST"
    echo "Response saved: /tmp/kvsput-response-$$.txt"
else
    echo "Debug files kept for troubleshooting:"
    echo "  - Response: /tmp/kvsput-response-$$.txt"
    echo "  - POST data: $TMP_POST (deleted)"
    echo "  - Test JSON: $TEST_JSON (deleted)"
fi

exit $RESULT
