#!/bin/bash
#
# Test kvsput.sh functionality
# Creates sample JSON and uploads to KVS
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVSPUT="${SCRIPT_DIR}/kvsput.sh"

echo "=========================================="
echo "kvsput.sh Test Script"
echo "=========================================="
echo ""

# Check if kvsput.sh exists
if [ ! -f "$KVSPUT" ]; then
    echo "❌ ERROR: kvsput.sh not found at: $KVSPUT"
    exit 1
fi

echo "✓ Found kvsput.sh: $KVSPUT"
echo ""

# Check config file
CONFIG_FILE="${SCRIPT_DIR}/../../giipAgent.cnf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ ERROR: giipAgent.cnf not found at: $CONFIG_FILE"
    exit 1
fi

echo "✓ Found config: $CONFIG_FILE"
echo ""

# Check config values
echo "Configuration Check:"
echo "--------------------"
if grep -q "^apiaddrv2=" "$CONFIG_FILE"; then
    ENDPOINT=$(grep "^apiaddrv2=" "$CONFIG_FILE" | cut -d= -f2 | tr -d '"' | tr -d "'")
    echo "✓ apiaddrv2: $ENDPOINT"
else
    echo "⚠ WARNING: apiaddrv2 not found in config"
fi

if grep -q "^apiaddrcode=" "$CONFIG_FILE"; then
    CODE=$(grep "^apiaddrcode=" "$CONFIG_FILE" | cut -d= -f2 | tr -d '"' | tr -d "'")
    CODE_PREVIEW="${CODE:0:20}..."
    echo "✓ apiaddrcode: $CODE_PREVIEW"
else
    echo "⚠ WARNING: apiaddrcode not found in config"
fi

if grep -q "^sk=" "$CONFIG_FILE"; then
    SK=$(grep "^sk=" "$CONFIG_FILE" | cut -d= -f2 | tr -d '"' | tr -d "'")
    SK_PREVIEW="${SK:0:15}..."
    echo "✓ sk: $SK_PREVIEW"
else
    echo "⚠ WARNING: sk not found in config"
fi

echo ""

# Check required tools
echo "Required Tools Check:"
echo "--------------------"
if command -v jq &> /dev/null; then
    echo "✓ jq: $(command -v jq)"
else
    echo "❌ ERROR: jq is required but not installed"
    echo "   Install: sudo apt-get install jq  (Ubuntu/Debian)"
    echo "           sudo yum install jq      (CentOS/RHEL)"
    exit 1
fi

if command -v curl &> /dev/null; then
    echo "✓ curl: $(command -v curl)"
else
    echo "❌ ERROR: curl is required but not installed"
    exit 1
fi

echo ""
echo "=========================================="
echo "Creating Test JSON..."
echo "=========================================="

# Create test JSON
TEST_JSON="/tmp/kvsput-test-$$.json"
cat > "$TEST_JSON" <<EOF
{
  "test_id": "kvsput-test-$$",
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "test_purpose": "Verify kvsput.sh functionality",
  "network_test": {
    "interfaces": [
      {
        "name": "eth0",
        "ipv4": "10.2.0.5",
        "mac": "00:22:48:0e:a4:93"
      }
    ]
  },
  "system_info": {
    "os": "$(uname -s)",
    "kernel": "$(uname -r)",
    "arch": "$(uname -m)"
  }
}
EOF

echo "✓ Test JSON created: $TEST_JSON"
echo ""
echo "Preview:"
cat "$TEST_JSON" | jq .
echo ""

# Upload to KVS
echo "=========================================="
echo "Uploading to KVS..."
echo "=========================================="
echo "KFactor: kvstest"
echo "File: $TEST_JSON"
echo ""

if bash "$KVSPUT" "$TEST_JSON" kvstest; then
    echo ""
    echo "=========================================="
    echo "✅ SUCCESS: Upload completed!"
    echo "=========================================="
    echo ""
    echo "Next Steps:"
    echo "1. Check in Windows:"
    echo "   cd c:\\Users\\lowys\\Downloads\\projects\\giipprj\\giipdb"
    echo "   .\\check_autodiscover_kvs.ps1 -KFactor kvstest"
    echo ""
    echo "2. Or query database directly:"
    echo "   SELECT * FROM tKVS WHERE KFactor = 'kvstest' ORDER BY kRegdt DESC"
    echo ""
    rm -f "$TEST_JSON"
    exit 0
else
    echo ""
    echo "=========================================="
    echo "❌ ERROR: Upload failed!"
    echo "=========================================="
    echo ""
    echo "Troubleshooting:"
    echo "1. Check config file:"
    echo "   cat $CONFIG_FILE | grep -E 'apiaddrv2|apiaddrcode|sk'"
    echo ""
    echo "2. Test network connectivity:"
    echo "   curl -I https://giipfaw.azurewebsites.net"
    echo ""
    echo "3. Check kvsput.sh logs above for details"
    echo ""
    echo "Test JSON kept for debugging: $TEST_JSON"
    exit 1
fi
