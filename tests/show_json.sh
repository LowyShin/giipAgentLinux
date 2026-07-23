#!/bin/bash

# 최신 gateway_servers JSON 파일 찾기
json_file=$(ls -tr /tmp/gateway_servers_*.json 2>/dev/null | tail -1)

if [ -z "$json_file" ]; then
    echo "Error: No gateway_servers_*.json file found in /tmp"
    exit 1
fi

echo "=== JSON File: $json_file ==="
echo ""
echo "=== Raw Content ==="
cat "$json_file"
echo ""
echo ""
echo "=== Pretty Print with jq ==="
jq . "$json_file"
echo ""
echo ""
echo "=== Extract with jq '.data[]?' ==="
jq -c '.data[]?' "$json_file"
echo ""
echo ""
echo "=== Extract with jq '.[]?' ==="
jq -c '.[]?' "$json_file"
echo ""
echo ""
echo "=== Extract with jq '.' (entire content) ==="
jq -c '.' "$json_file"
