#!/bin/bash
################################################################################
# Simplified SSH Test for Debugging
# Purpose: Test if for loop with array works correctly
################################################################################

# Test data (as would come from the JSON file)
declare -a server_list

# Create temp file to simulate actual flow
temp_servers="/tmp/test_servers_$$.jsonl"
cat > "$temp_servers" << 'EOF'
{"hostname":"p-cnsldb01m","ssh_host":"p-cnsldb01m","ssh_user":"istyle","ssh_port":22,"ssh_key_path":"","ssh_password":"pass1","lssn":71221}
{"hostname":"stagemy5701","ssh_host":"stagemy5701","ssh_user":"istyle","ssh_port":22,"ssh_key_path":"","ssh_password":"pass2","lssn":71242}
EOF

echo "=== PHASE 1: Reading servers from temp file ==="
echo ""

# Read servers into array (THIS IS THE CRITICAL SECTION)
while IFS= read -r server_json; do
    [ -z "$server_json" ] && continue
    server_list+=("$server_json")
    count=${#server_list[@]}
    echo "✓ Added server $count to array"
done < "$temp_servers"

rm -f "$temp_servers"

echo ""
echo "=== PHASE 2: Verify array contents ==="
echo "Array size: ${#server_list[@]}"
echo ""

if [ ${#server_list[@]} -eq 0 ]; then
    echo "ERROR: Array is empty!"
    exit 1
fi

echo "=== PHASE 3: Loop through array and test connection ==="
echo ""

test_count=0
for server_json in "${server_list[@]}"; do
    ((test_count++))
    echo ""
    echo "─────────────────────────────────────────"
    echo "Test $test_count: Processing server"
    echo "─────────────────────────────────────────"
    
    # Extract using jq if available
    if command -v jq &> /dev/null; then
        hostname=$(echo "$server_json" | jq -r '.hostname // "UNKNOWN"')
        ssh_host=$(echo "$server_json" | jq -r '.ssh_host // "UNKNOWN"')
        ssh_user=$(echo "$server_json" | jq -r '.ssh_user // "UNKNOWN"')
        lssn=$(echo "$server_json" | jq -r '.lssn // 0')
        
        echo "✓ Extracted: $hostname ($ssh_host)"
        echo "  User: $ssh_user, LSSN: $lssn"
        echo "✓ Would test SSH connection here"
    else
        echo "jq not available, showing raw JSON:"
        echo "$server_json"
    fi
done

echo ""
echo "=== PHASE 4: Summary ==="
echo "✓ Successfully processed $test_count servers"
echo "✓ Test completed successfully!"
