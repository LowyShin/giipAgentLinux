#!/bin/bash
# Test ManagedDatabaseHealthUpdate API Call

# Load config (tests 폴더에서 실행하므로 상위 폴더 참조)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/../giipAgent.cnf"

echo "===== Testing ManagedDatabaseHealthUpdate API ====="
echo ""
echo "📂 Config: /home/giip/giipAgent.cnf"
echo "🔑 SK: ${sk}"
echo "🔗 API: ${apiaddrv2}"
echo ""

# Test data
health_data='[{"mdb_id":3,"status":"success","message":"Test from script","response_time_ms":100}]'

echo "📤 Sending health check data:"
echo "$health_data"
echo ""

temp_file=$(mktemp)

wget -O "$temp_file" \
    --post-data="text=ManagedDatabaseHealthUpdate jsondata&token=${sk}&jsondata=${health_data}" \
    "${apiaddrv2}"

echo ""
echo "✅ API Response:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat "$temp_file"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

rm -f "$temp_file"
