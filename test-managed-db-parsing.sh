#!/bin/bash
# Test script: Parse managed database list and build health_results JSON
# Purpose: Isolate the JSON parsing logic to debug health_results empty issue

# Load configuration
source giipAgent.cnf
source lib/kvs.sh

echo "========================================="
echo "Test: Managed Database JSON Parsing"
echo "========================================="

# Get managed database list
echo ""
echo "Step 1: Fetching managed database list..."
temp_file=$(mktemp)
wget -O "$temp_file" --quiet \
    --post-data="text=GatewayManagedDatabaseList&token=${sk}" \
    "${apiaddrv2}?code=${apiaddrcode}" 2>/dev/null

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
