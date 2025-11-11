#!/bin/bash
# Test script: Parse managed database list and build health_results JSON
# Purpose: Isolate the JSON parsing logic to debug health_results empty issue

# ============================================================================
# Initialize Script Paths (same as giipAgent3.sh)
# ============================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="${SCRIPT_DIR}/lib"

# Load common functions (to get load_config)
if [ -f "${LIB_DIR}/common.sh" ]; then
	. "${LIB_DIR}/common.sh"
else
	echo "❌ Error: common.sh not found in ${LIB_DIR}"
	exit 1
fi

# Load configuration (same path as giipAgent3.sh)
load_config "../giipAgent.cnf"
if [ $? -ne 0 ]; then
	echo "❌ Failed to load configuration"
	exit 1
fi

echo "========================================="
echo "Test: Managed Database JSON Parsing"
echo "========================================="

# Get managed database list
echo ""
echo "Step 1: Fetching managed database list..."
echo "Using lssn: $lssn"
temp_file=$(mktemp)

# Use correct API format with jsondata
text="GatewayManagedDatabaseList lssn"
jsondata="{\"lssn\":${lssn}}"

wget -O "$temp_file" --quiet \
    --post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
    --header="Content-Type: application/x-www-form-urlencoded" \
    "${apiaddrv2}?code=${apiaddrcode}" \
    --no-check-certificate 2>&1

if [ ! -f "$temp_file" ]; then
    echo "❌ Failed to fetch DB list"
    exit 1
fi

echo "✅ API Response saved to: $temp_file"
echo ""
echo "Step 2: Raw API Response:"
echo "----------------------------------------"
cat "$temp_file"
echo ""
echo "----------------------------------------"

# Parse JSON
echo ""
echo "Step 3: Parsing JSON objects..."
db_list=$(cat "$temp_file" | grep -E -o '\{[^}]*\}')
echo "Parsed JSON objects:"
echo "$db_list"
echo ""

# Count databases
db_count=$(echo "$db_list" | grep -c '"mdb_id"')
echo "Database count: $db_count"
echo ""

# Build health_results
echo "Step 4: Building health_results JSON..."
health_results_file=$(mktemp)

echo "$db_list" | while IFS= read -r db_json; do
    [[ -z "$db_json" ]] && continue
    
    mdb_id=$(echo "$db_json" | grep -E -o '"mdb_id"[[:space:]]*:[[:space:]]*[0-9]+' | grep -E -o '[0-9]+')
    db_name=$(echo "$db_json" | grep -E -o '"db_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
    
    echo "  Processing: mdb_id=$mdb_id, db_name=$db_name"
    
    if [[ -n $mdb_id ]]; then
        echo "{\"mdb_id\":${mdb_id},\"status\":\"success\",\"message\":\"Test\",\"response_time_ms\":0}" >> "$health_results_file"
    fi
done

echo ""
echo "Step 5: Temp file contents:"
echo "----------------------------------------"
cat "$health_results_file"
echo ""
echo "----------------------------------------"

echo ""
echo "Step 6: Building JSON array with awk..."
health_results=$(awk 'BEGIN{printf "["} NR>1{printf ","} {printf "%s", $0} END{printf "]"}' "$health_results_file")

echo "Final health_results:"
echo "$health_results"
echo ""

# Check if empty
if [ "$health_results" = "[]" ]; then
    echo "❌ PROBLEM: health_results is empty!"
else
    echo "✅ SUCCESS: health_results has data"
    echo "Length: ${#health_results} characters"
fi

# Cleanup
rm -f "$temp_file" "$health_results_file"

echo ""
echo "========================================="
echo "Test Complete"
echo "========================================="
