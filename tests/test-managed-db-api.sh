#!/bin/bash
# Test GatewayManagedDatabaseList API

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Load config
CNF_FILE="${SCRIPT_DIR}/../giipAgent.cnf"
if [ ! -f "$CNF_FILE" ]; then
    CNF_FILE="${SCRIPT_DIR}/giipAgent.cnf"
fi

if [ ! -f "$CNF_FILE" ]; then
    echo "❌ Config file not found"
    exit 1
fi

source "$CNF_FILE"

echo "===== Testing GatewayManagedDatabaseList API ====="
echo ""
echo "📂 Config: $CNF_FILE"
echo "🔑 LSSN: $lssn"
echo "🔗 API: $apiaddrv2"
echo ""

# Test API call
temp_file="/tmp/test_managed_db_$$.json"

wget -O "$temp_file" \
    --post-data="text=GatewayManagedDatabaseList lssn&token=${sk}&jsondata={\"lssn\":${lssn}}" \
    --header="Content-Type: application/x-www-form-urlencoded" \
    "${apiaddrv2}" \
    --no-check-certificate -q 2>&1

if [ -f "$temp_file" ]; then
    echo "✅ API Response:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    cat "$temp_file"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Count databases
    db_count=$(cat "$temp_file" | grep -o '"mdb_id"' | wc -l)
    echo "📊 Database count: $db_count"
    
    rm -f "$temp_file"
else
    echo "❌ No response"
fi
