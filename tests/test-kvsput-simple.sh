#!/bin/bash
#
# Simple KVSPut test script (based on kvsput.sh)
#

set -e

echo "=========================================="
echo "KVSPut Simple Test"
echo "=========================================="
echo ""

# Detect config file location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Only use the real config file (not the dummy template)
if [ -f "$SCRIPT_DIR/../giipAgent.cnf" ]; then
  CONFIG_FILE="$SCRIPT_DIR/../giipAgent.cnf"
elif [ -f "/home/giip/giipAgent.cnf" ]; then
  CONFIG_FILE="/home/giip/giipAgent.cnf"
else
  echo "❌ ERROR: giipAgent.cnf not found"
  echo "  Checked:"
  echo "    - $SCRIPT_DIR/../giipAgent.cnf"
  echo "    - /home/giip/giipAgent.cnf"
  exit 1
fi

echo "✓ Config: $CONFIG_FILE"
echo ""

# Read config (same method as kvsput.sh)
declare -A KVS_CONFIG
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  if [[ "$line" =~ ^([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"
    # trim quotes
    case "$val" in
      '"'*) val="${val#\"}" ; val="${val%\"}" ;;
      "'"*) val="${val#\'}" ; val="${val%\'}" ;;
    esac
    if [[ ${#val} -ge 2 ]]; then
      first=${val:0:1}
      last=${val: -1}
      if [[ ( "$first" == '"' && "$last" == '"' ) || ( "$first" == "'" && "$last" == "'" ) ]]; then
        val=${val:1:-1}
      fi
    fi
    KVS_CONFIG[$key]="$val"
  fi
done < "$CONFIG_FILE"

# Use development endpoint (apiaddrv2dev)
if [[ -n "${KVS_CONFIG[apiaddrv2dev]}" ]]; then
  ENDPOINT="${KVS_CONFIG[apiaddrv2dev]}"
else
  echo "❌ ERROR: apiaddrv2dev not found in config"
  exit 1
fi

# Add function code (apiaddrcodedev)
if [[ -n "${KVS_CONFIG[apiaddrcodedev]}" ]]; then
  ENDPOINT+="?code=${KVS_CONFIG[apiaddrcodedev]}"
else
  echo "❌ ERROR: apiaddrcodedev not found in config"
  exit 1
fi

# Get token (sk)
if [[ -n "${KVS_CONFIG[sk]}" ]]; then
  USER_TOKEN="${KVS_CONFIG[sk]}"
else
  echo "❌ ERROR: sk not found in config"
  exit 1
fi

# Get kKey (lssn)
if [[ -n "${KVS_CONFIG[lssn]}" ]]; then
  KKEY="${KVS_CONFIG[lssn]}"
else
  echo "❌ ERROR: lssn not found in config"
  exit 1
fi

# Check required commands
command -v jq >/dev/null 2>&1 || { echo "❌ ERROR: jq not found" >&2; exit 4; }
command -v curl >/dev/null 2>&1 || { echo "❌ ERROR: curl not found" >&2; exit 4; }

echo "Configuration loaded:"
echo "  Endpoint: $ENDPOINT" | sed "s/?code=.*/?code=${KVS_CONFIG[apiaddrcodedev]:0:20}.../"
echo "  Token: ${USER_TOKEN:0:10}... (from sk in config)"
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

# === EXACTLY THE SAME AS kvsput.sh from here ===

# Compact the JSON file (this will be kValue in jsondata)
JSON_FILE_COMPACT=$(jq -c . "$TEST_JSON")

# Build jsondata with proper structure: {kType, kKey, kFactor, kValue}
JSON_PAYLOAD=$(jq -n \
  --arg kType "lssn" \
  --arg kKey "$KKEY" \
  --arg kFactor "simpletest" \
  --argjson kValue "$JSON_FILE_COMPACT" \
  '{kType: $kType, kKey: $kKey, kFactor: $kFactor, kValue: $kValue}')

# KVSP text: procedure name + parameter NAMES only (as required by giipapi)
KVSP_TEXT="KVSPut kType kKey kFactor kValue"

# Build form parameters: text, token, jsondata
POST_DATA="text=$(printf "%s" "$KVSP_TEXT" | jq -sRr @uri)"
POST_DATA+="&token=$(printf "%s" "$USER_TOKEN" | jq -sRr @uri)"
POST_DATA+="&jsondata=$(printf "%s" "$JSON_PAYLOAD" | jq -sRr @uri)"

# Diagnostic output
echo "Sending request..."
echo "  KVSP text: $KVSP_TEXT"
echo "  Token: ${USER_TOKEN:0:10}..." 
echo ""

# Upload: avoid passing very large data on the command line (can hit ARG_MAX).
# Write the urlencoded form body to a temp file and let curl read it via @file.
TMP_POST=$(mktemp)
printf '%s' "$POST_DATA" > "$TMP_POST"
resp=$(curl -s -X POST "$ENDPOINT" -H 'Content-Type: application/x-www-form-urlencoded' -H 'Expect:' --data-binary "@$TMP_POST")
rc=$?

echo "=========================================="
echo "Response:"
echo "=========================================="

if [ $rc -ne 0 ]; then
  echo "❌ curl failed with exit code $rc"
  echo "$resp"
  rm -f "$TMP_POST" "$TEST_JSON"
  exit $rc
fi

# Show response
echo "$resp" | jq . 2>/dev/null || echo "$resp"
echo ""

# Check response
if echo "$resp" | jq -e '.data[0].RstVal == 200' >/dev/null 2>&1; then
  echo "✅ Success! (RstVal=200)"
  RESULT=0
elif echo "$resp" | jq -e '.data[0].RstVal == 411' >/dev/null 2>&1; then
  echo "❌ 411 Error: Server not found or wrong CGSn"
  RESULT=1
elif echo "$resp" | jq -e '.data[0].RstVal == 401' >/dev/null 2>&1; then
  echo "❌ 401 Error: Authentication failed"
  RESULT=1
elif echo "$resp" | jq -e '.error' >/dev/null 2>&1; then
  echo "❌ Error detected in response"
  RESULT=1
else
  echo "⚠ Unknown response format"
  RESULT=1
fi

# Cleanup
rm -f "$TMP_POST" "$TEST_JSON"

exit $RESULT
