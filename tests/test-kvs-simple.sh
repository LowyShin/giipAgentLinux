#!/bin/bash
# Simple KVS API test to isolate the issue

# Load configuration (tests 폴더에서 실행하므로 상위 폴더 참조)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/../giipAgent.cnf"

# Build simple test data
kvalue='{"test":"simple","number":123}'
jsondata="{\"kType\":\"lssn\",\"kKey\":\"71240\",\"kFactor\":\"giipagent\",\"kValue\":${kvalue}}"

echo "=== Test 1: Simple kValue ==="
echo "jsondata: $jsondata"

# URL-encode
encoded_jsondata=$(printf '%s' "$jsondata" | jq -sRr '@uri')
echo "encoded: $encoded_jsondata"

# Build POST data
text="KVSPut kType kKey kFactor"
post_data="text=${text}&token=${sk}&jsondata=${encoded_jsondata}"

# Save to file
echo "$post_data" > /tmp/test_kvs_post.txt

# Decode and validate
echo -e "\n=== Decoded JSON ==="
echo "$post_data" | grep -oP 'jsondata=\K.*' | python3 -c "import sys, json; from urllib.parse import unquote; data=unquote(sys.stdin.read()); print(json.dumps(json.loads(data), indent=2))"

# Try API call
echo -e "\n=== API Call ===" 
kvs_url="${apiaddrv2}?code=${apiaddrcode}"
wget -O /tmp/test_response.txt \
    --post-data="$post_data" \
    --header="Content-Type: application/x-www-form-urlencoded" \
    "$kvs_url" \
    --no-check-certificate \
    -v 2>&1 | grep -E "HTTP/|Content-Length"

echo -e "\n=== Response ==="
cat /tmp/test_response.txt

# Cleanup
rm -f /tmp/test_kvs_post.txt /tmp/test_response.txt
