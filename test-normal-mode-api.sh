#!/bin/bash
################################################################################
# Normal Mode API Check Script
# Purpose: Test if normal mode API calls are working correctly
# Date: 2025-12-31
################################################################################

# UTF-8 환경 설정
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

set -e

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="${SCRIPT_DIR}/lib"
CONFIG_FILE="${SCRIPT_DIR}/../giipAgent.cnf"

echo "========================================="
echo "Normal Mode API Check"
echo "========================================="
echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "LIB_DIR: $LIB_DIR"
echo "CONFIG_FILE: $CONFIG_FILE"
echo ""

# Load common functions
if [ -f "${LIB_DIR}/common.sh" ]; then
	. "${LIB_DIR}/common.sh"
else
	echo "❌ Error: common.sh not found in ${LIB_DIR}"
	exit 1
fi

# Load config
load_config "$CONFIG_FILE"
if [ $? -ne 0 ]; then
	echo "❌ Failed to load configuration from: $CONFIG_FILE"
	exit 1
fi

echo "✓ Configuration loaded successfully"
echo "  lssn: $lssn"
echo "  apiaddrv2: $apiaddrv2"
echo "  sk: ${sk:0:10}..." # Only show first 10 chars for security
echo ""

# Get system info
hn=$(hostname)
if [ -f "${LIB_DIR}/common.sh" ]; then
	os=$(detect_os)
else
	os=$(uname -s)
fi

echo "✓ System information"
echo "  hostname: $hn"
echo "  os: $os"
echo ""

# Build API URL
api_url="${apiaddrv2}"
[ -n "$apiaddrcode" ] && api_url="${api_url}?code=${apiaddrcode}"

echo "========================================="
echo "Test 1: CQEQueueGet API Call"
echo "========================================="

# ✅ Follow giipapi_rules.md: text contains parameter names only!
text="CQEQueueGet lssn hostname os op"
jsondata="{\"lssn\":${lssn},\"hostname\":\"${hn}\",\"os\":\"${os}\",\"op\":\"op\"}"

echo "API URL: $api_url"
echo "text: $text"
echo "jsondata: $jsondata"
echo ""

# Create temp file for response
temp_response="/tmp/test_queue_response_$$.json"
rm -f "$temp_response"

echo "Calling API..."
curl -v -X POST "$api_url" \
	-d "text=${text}&token=${sk}&jsondata=${jsondata}" \
	-H "Content-Type: application/x-www-form-urlencoded" \
	--insecure -o "$temp_response" 2>&1 | tee /tmp/test_curl_output.log

echo ""
echo "========================================="
echo "API Response:"
echo "========================================="

if [ -f "$temp_response" ]; then
	cat "$temp_response" | jq . 2>/dev/null || cat "$temp_response"
	echo ""
	
	# Parse response
	echo ""
	echo "========================================="
	echo "Response Analysis:"
	echo "========================================="
	
	rst_val=$(jq -r '.data[0].RstVal // .RstVal // "unknown"' "$temp_response" 2>/dev/null)
	echo "RstVal: $rst_val"
	
	if [ "$rst_val" = "200" ]; then
		echo "✅ API call successful (RstVal=200)"
		
		# Try to extract script
		script=$(jq -r '.data[0].ms_body // .ms_body // empty' "$temp_response" 2>/dev/null)
		if [ -n "$script" ] && [ "$script" != "null" ]; then
			echo "✅ Script extracted successfully"
			echo "Script content (first 200 chars):"
			echo "$script" | head -c 200
			echo ""
		else
			echo "⚠️  No script found in response (this is normal if no queue is available)"
		fi
	elif [ "$rst_val" = "404" ] || [ "$rst_val" = "0" ]; then
		echo "✅ No queue available (this is normal)"
	else
		proc_name=$(jq -r '.data[0].ProcName // .ProcName // "unknown"' "$temp_response" 2>/dev/null)
		echo "❌ API returned error: $rst_val - $proc_name"
	fi
	
	rm -f "$temp_response"
else
	echo "❌ No response file created"
	echo "Check /tmp/test_curl_output.log for details"
fi

echo ""
echo "========================================="
echo "Test 2: Check save_execution_log (startup)"
echo "========================================="

# Load KVS functions
if [ -f "${LIB_DIR}/kvs.sh" ]; then
	. "${LIB_DIR}/kvs.sh"
	echo "✓ kvs.sh loaded"
else
	echo "❌ Error: kvs.sh not found in ${LIB_DIR}"
	exit 1
fi

# Test save_execution_log
sv="3.00"
GIT_COMMIT="test"
FILE_MODIFIED=$(date "+%Y-%m-%d %H:%M:%S")

startup_details="{\"pid\":$$,\"config_file\":\"giipAgent.cnf\",\"api_endpoint\":\"${apiaddrv2}\",\"is_gateway\":0,\"mode\":\"normal_test\",\"git_commit\":\"${GIT_COMMIT}\",\"file_modified\":\"${FILE_MODIFIED}\",\"script_path\":\"${BASH_SOURCE[0]}\"}"

echo "Testing save_execution_log..."
echo "startup_details: $startup_details"
echo ""

save_execution_log "startup" "$startup_details"
exit_code=$?

if [ $exit_code -eq 0 ]; then
	echo "✅ save_execution_log successful"
else
	echo "❌ save_execution_log failed with exit code: $exit_code"
fi

echo ""
echo "========================================="
echo "Test Complete"
echo "========================================="
echo ""
echo "Summary:"
echo "  - Check if CQEQueueGet API returned proper response"
echo "  - Check if save_execution_log (KVSPut) worked correctly"
echo "  - Review /tmp/test_curl_output.log for detailed curl output"
echo ""

# Cleanup
rm -f /tmp/test_curl_output.log

exit 0
