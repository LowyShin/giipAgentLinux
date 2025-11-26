#!/bin/bash
# Test CQE Queue retrieval with both old and new API

# Load configuration
. ./giipAgent.cnf

echo "=========================================="
echo "CQE Queue Test Script"
echo "=========================================="
echo "Testing Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo "Configuration:"
echo "  LSSN: $lssn"
echo "  SK: ${sk:0:10}..."
echo "  Hostname: $(hostname)"
echo "  Old API: $apiaddr"
echo "  New API: $apiaddrv2"
echo ""

# Get OS info
uname_result=$(uname -a | awk '{print $1}')
if [ "${uname_result}" = "Darwin" ]; then
    osname=$(sw_vers -productName)
    osver=$(sw_vers -productVersion)
    os="${osname} ${osver}"
    os=$(echo "$os" | sed 's/^ *\| *$//' | sed -e "s/ /%20/g")
else
    ostype=$(head -n 1 /etc/issue 2>/dev/null | awk '{print $1}')
    if [ "${ostype}" = "Ubuntu" ]; then
        os=$(lsb_release -d | sed 's/^ *\| *$//' | sed -e "s/Description\://g")
    else
        os=$(cat /etc/redhat-release 2>/dev/null)
    fi
fi

hn=$(hostname)
sv="2.00"

echo "=========================================="
echo "TEST 1: Old API (ASP Classic - apiaddr)"
echo "=========================================="
echo ""

# Old API test (GET request)
old_url="${apiaddr}/api/cqe/cqequeueget03.asp?sk=$sk&lssn=$lssn&hn=${hn}&os=$os&df=os&sv=${sv}"
old_url=$(echo "$old_url" | sed -e "s/ /%20/g")
old_output="/tmp/test_cqe_old_$$.txt"

echo "URL: $old_url"
echo ""
echo "Executing..."
wget -O "$old_output" "$old_url" --no-check-certificate -q 2>&1

if [ -s "$old_output" ]; then
    echo "✅ Response received (Old API)"
    echo ""
    echo "--- Response Preview (first 500 chars) ---"
    cat "$old_output" | head -c 500
    echo ""
    echo "--- End Preview ---"
    echo ""
    echo "Response size: $(wc -c < "$old_output") bytes"
    echo "Response lines: $(wc -l < "$old_output") lines"
    
    # Check for errors
    error_check=$(cat "$old_output" | grep -i "error\|404\|401\|500")
    if [ -n "$error_check" ]; then
        echo "⚠️  Warning: Possible error in response"
        echo "Error content: $error_check"
    fi
else
    echo "❌ No response (Old API)"
fi

rm -f "$old_output"

echo ""
echo ""
echo "=========================================="
echo "TEST 2: New API (PowerShell - apiaddrv2)"
echo "=========================================="
echo ""

# New API test (POST request)
new_url="${apiaddrv2}"
if [ -n "$apiaddrcode" ]; then
    new_url="${new_url}?code=${apiaddrcode}"
fi

new_output="/tmp/test_cqe_new_$$.txt"
new_text="CQEQueueGet ${lssn} ${hn} ${os} op"

echo "URL: $new_url"
echo "Command: $new_text"
echo ""
echo "Executing..."
wget -O "$new_output" \
    --post-data="text=${new_text}&token=${sk}" \
    --header="Content-Type: application/x-www-form-urlencoded" \
    "$new_url" \
    --no-check-certificate -q 2>&1

if [ -s "$new_output" ]; then
    echo "✅ Response received (New API)"
    echo ""
    echo "--- Response Preview (first 500 chars) ---"
    cat "$new_output" | head -c 500
    echo ""
    echo "--- End Preview ---"
    echo ""
    echo "Response size: $(wc -c < "$new_output") bytes"
    echo "Response lines: $(wc -l < "$new_output") lines"
    
    # Check if JSON
    is_json=$(cat "$new_output" | grep -o '^{.*}$')
    if [ -n "$is_json" ]; then
        echo "📦 Response format: JSON"
        echo ""
        
        # Extract fields
        rstval=$(cat "$new_output" | grep -o '"RstVal":"[^"]*"' | sed 's/"RstVal":"//; s/"$//' | head -1)
        ms_body=$(cat "$new_output" | grep -o '"ms_body":"[^"]*"' | sed 's/"ms_body":"//; s/"$//')
        mssn=$(cat "$new_output" | grep -o '"mssn":[0-9]*' | sed 's/"mssn"://' | head -1)
        mslsn=$(cat "$new_output" | grep -o '"mslsn":[0-9]*' | sed 's/"mslsn"://' | head -1)
        script_type=$(cat "$new_output" | grep -o '"script_type":"[^"]*"' | sed 's/"script_type":"//; s/"$//')
        
        echo "RstVal: $rstval"
        echo "mslsn: $mslsn"
        echo "mssn: $mssn"
        echo "script_type: $script_type"
        echo ""
        
        if [ "$rstval" = "200" ]; then
            if [ -n "$ms_body" ] && [ "$ms_body" != "null" ]; then
                echo "✅ Script found in ms_body"
                echo "Script preview (first 200 chars):"
                echo "$ms_body" | head -c 200
                echo ""
            else
                echo "⚠️  ms_body is empty or null"
                
                if [ -n "$mssn" ] && [ "$mssn" != "null" ] && [ "$mssn" != "0" ]; then
                    echo "📝 mssn available: $mssn (can fetch from repository)"
                    echo ""
                    echo "--- Testing repository fetch ---"
                    
                    # Test CQERepoScript
                    repo_output="/tmp/test_cqe_repo_$$.txt"
                    repo_text="CQERepoScript ${mssn}"
                    
                    echo "Command: $repo_text"
                    wget -O "$repo_output" \
                        --post-data="text=${repo_text}&token=${sk}" \
                        --header="Content-Type: application/x-www-form-urlencoded" \
                        "$new_url" \
                        --no-check-certificate -q 2>&1
                    
                    if [ -s "$repo_output" ]; then
                        echo "✅ Repository fetch successful"
                        echo "Script size: $(wc -c < "$repo_output") bytes"
                        echo "Script preview (first 200 chars):"
                        cat "$repo_output" | head -c 200
                        echo ""
                    else
                        echo "❌ Repository fetch failed"
                    fi
                    
                    rm -f "$repo_output"
                else
                    echo "❌ No valid mssn available"
                fi
            fi
        elif [ "$rstval" = "404" ]; then
            echo "ℹ️  No queue available (404)"
            echo "This is normal if no scripts are scheduled"
        else
            echo "⚠️  Unexpected RstVal: $rstval"
        fi
    else
        echo "📄 Response format: Plain text"
        
        # Check for errors
        error_check=$(cat "$new_output" | grep -i "error\|404\|401\|500")
        if [ -n "$error_check" ]; then
            echo "⚠️  Warning: Possible error in response"
            echo "Error content: $error_check"
        fi
    fi
else
    echo "❌ No response (New API)"
fi

rm -f "$new_output"

echo ""
echo ""
echo "=========================================="
echo "TEST 3: Database Direct Query"
echo "=========================================="
echo ""

echo "Checking if there are any pending queues in tMgmtQue..."
echo "(This requires database access)"
echo ""
echo "SQL Query would be:"
echo "SELECT TOP 5 qsn, mslsn, lssn, send_flag, regdate"
echo "FROM tMgmtQue WITH(NOLOCK)"
echo "WHERE lssn = $lssn AND send_flag = 0"
echo "ORDER BY qsn DESC"
echo ""

echo "=========================================="
echo "TEST COMPLETE"
echo "=========================================="
echo ""
echo "Summary:"
echo "  - Old API (ASP Classic): Tested"
echo "  - New API (PowerShell): Tested"
echo "  - Check logs above for results"
echo ""
echo "Next Steps:"
echo "1. If Old API works but New API doesn't:"
echo "   → Check if pApiCQEQueueGetbySK exists in database"
echo "   → Verify giipApiSk2 can execute CQEQueueGet command"
echo ""
echo "2. If both APIs show no queue (404):"
echo "   → This is normal if no scripts are scheduled"
echo "   → Test by creating a test script in Web UI"
echo ""
echo "3. To create a test queue:"
echo "   → Go to GIIP Web UI → CQE Management"
echo "   → Create a simple script (e.g., 'echo test')"
echo "   → Assign it to LSSN $lssn"
echo "   → Set interval to 1 minute"
echo "   → Re-run this test script"
echo ""
