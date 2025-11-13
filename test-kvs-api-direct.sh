#!/bin/bash
# Test KVS API with exact same parameters as giipAgent

# Load config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../giipAgent.cnf"

echo "=== KVS API Test ===" 
echo "API: $apiaddrv2"
echo "Code: ${apiaddrcode:0:20}..."
echo "SK: ${sk:0:20}..."
echo "LSSN: $lssn"
echo ""

# Simple test data
kvalue='{"test":"simple","number":123}'
jsondata="{\"kType\":\"lssn\",\"kKey\":\"${lssn}\",\"kFactor\":\"test\",\"kValue\":${kvalue}}"

echo "JSON Data: $jsondata"
echo ""

# URL-encode
encoded_text=$(printf '%s' "KVSPut kType kKey kFactor" | jq -sRr '@uri')
encoded_token=$(printf '%s' "$sk" | jq -sRr '@uri')
encoded_jsondata=$(printf '%s' "$jsondata" | jq -sRr '@uri')

# Build URL
url="${apiaddrv2}?code=${apiaddrcode}"

echo "=== Sending Request ===" 
curl -v -X POST "$url" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "text=${encoded_text}&token=${encoded_token}&jsondata=${encoded_jsondata}" \
  2>&1 | tee /tmp/kvs_test_output.txt

echo ""
echo ""
echo "=== Response saved to /tmp/kvs_test_output.txt ==="
