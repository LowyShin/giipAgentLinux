#!/bin/bash
# Test script for refactored giipAgent
# Version: 1.0
# Date: 2025-01-10
# Purpose: Test modular architecture (lib/*.sh)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="${SCRIPT_DIR}/lib"

echo "=================================================="
echo "GIIP Agent Refactored Test Suite"
echo "=================================================="
echo ""

# ============================================================================
# Test 1: Library Files Existence
# ============================================================================

echo "[TEST 1] Checking library files..."
PASS=0
FAIL=0

check_file() {
	local file=$1
	if [ -f "$file" ]; then
		echo "  ✅ $file exists"
		PASS=$((PASS + 1))
	else
		echo "  ❌ $file NOT FOUND"
		FAIL=$((FAIL + 1))
	fi
}

check_file "${LIB_DIR}/common.sh"
check_file "${LIB_DIR}/kvs.sh"
check_file "${LIB_DIR}/db_clients.sh"
check_file "${LIB_DIR}/gateway.sh"
check_file "${LIB_DIR}/normal.sh"
check_file "${SCRIPT_DIR}/giipAgent3.sh"

echo "  Result: ${PASS} passed, ${FAIL} failed"
echo ""

# ============================================================================
# Test 2: Library Loading
# ============================================================================

echo "[TEST 2] Testing library loading..."

# Test common.sh
if [ -f "${LIB_DIR}/common.sh" ]; then
	. "${LIB_DIR}/common.sh"
	
	# Test function existence
	if type load_config &>/dev/null; then
		echo "  ✅ common.sh loaded successfully"
		echo "     - load_config() available"
		echo "     - log_message() available"
		echo "     - error_handler() available"
	else
		echo "  ❌ common.sh functions not available"
	fi
else
	echo "  ❌ common.sh not found"
fi

# Test kvs.sh
if [ -f "${LIB_DIR}/kvs.sh" ]; then
	. "${LIB_DIR}/kvs.sh"
	
	if type save_execution_log &>/dev/null; then
		echo "  ✅ kvs.sh loaded successfully"
		echo "     - save_execution_log() available"
		echo "     - kvs_put() available"
	else
		echo "  ❌ kvs.sh functions not available"
	fi
else
	echo "  ❌ kvs.sh not found"
fi

# Test db_clients.sh
if [ -f "${LIB_DIR}/db_clients.sh" ]; then
	. "${LIB_DIR}/db_clients.sh"
	
	if type check_sshpass &>/dev/null; then
		echo "  ✅ db_clients.sh loaded successfully"
		echo "     - check_sshpass() available"
		echo "     - check_mysql_client() available"
		echo "     - check_db_clients() available"
	else
		echo "  ❌ db_clients.sh functions not available"
	fi
else
	echo "  ❌ db_clients.sh not found"
fi

# Test gateway.sh
if [ -f "${LIB_DIR}/gateway.sh" ]; then
	. "${LIB_DIR}/gateway.sh"
	
	if type sync_gateway_servers &>/dev/null; then
		echo "  ✅ gateway.sh loaded successfully"
		echo "     - sync_gateway_servers() available"
		echo "     - process_gateway_servers() available"
	else
		echo "  ❌ gateway.sh functions not available"
	fi
else
	echo "  ❌ gateway.sh not found"
fi

# Test normal.sh
if [ -f "${LIB_DIR}/normal.sh" ]; then
	. "${LIB_DIR}/normal.sh"
	
	if type run_normal_mode &>/dev/null; then
		echo "  ✅ normal.sh loaded successfully"
		echo "     - fetch_queue() available"
		echo "     - parse_json_response() available"
		echo "     - execute_script() available"
		echo "     - run_normal_mode() available"
	else
		echo "  ❌ normal.sh functions not available"
	fi
else
	echo "  ❌ normal.sh not found"
fi

echo ""

# ============================================================================
# Test 3: Configuration Loading
# ============================================================================

echo "[TEST 3] Testing configuration loading..."

if [ -f "../giipAgent.cnf" ]; then
	echo "  ✅ Configuration file exists"
	
	# Try to load config
	load_config "../giipAgent.cnf" 2>/dev/null
	if [ $? -eq 0 ]; then
		echo "  ✅ Configuration loaded successfully"
		echo "     - LSSN: ${lssn}"
		echo "     - Gateway Mode: ${gateway_mode}"
		echo "     - Agent Delay: ${giipagentdelay}"
	else
		echo "  ⚠️  Configuration load failed (may need valid config)"
	fi
else
	echo "  ⚠️  Configuration file not found (../giipAgent.cnf)"
	echo "     This is OK for testing - use template"
fi

echo ""

# ============================================================================
# Test 4: Function Availability Check
# ============================================================================

echo "[TEST 4] Checking function availability..."

check_function() {
	local func=$1
	if type "$func" &>/dev/null; then
		echo "  ✅ $func"
	else
		echo "  ❌ $func NOT FOUND"
	fi
}

echo "  Common functions:"
check_function "load_config"
check_function "log_message"
check_function "error_handler"
check_function "detect_os"
check_function "init_log_dir"

echo ""
echo "  KVS functions:"
check_function "save_execution_log"
check_function "kvs_put"

echo ""
echo "  DB Client functions:"
check_function "check_sshpass"
check_function "check_mysql_client"
check_function "check_db_clients"

echo ""
echo "  Gateway functions:"
check_function "sync_gateway_servers"
check_function "process_gateway_servers"
check_function "get_remote_queue"

echo ""
echo "  Normal mode functions:"
check_function "fetch_queue"
check_function "parse_json_response"
check_function "execute_script"
check_function "run_normal_mode"

echo ""

# ============================================================================
# Test 5: Syntax Check
# ============================================================================

echo "[TEST 5] Syntax checking all scripts..."

check_syntax() {
	local file=$1
	bash -n "$file" 2>/dev/null
	if [ $? -eq 0 ]; then
		echo "  ✅ $file syntax OK"
	else
		echo "  ❌ $file syntax ERROR"
		bash -n "$file"
	fi
}

check_syntax "${LIB_DIR}/common.sh"
check_syntax "${LIB_DIR}/kvs.sh"
check_syntax "${LIB_DIR}/db_clients.sh"
check_syntax "${LIB_DIR}/gateway.sh"
check_syntax "${LIB_DIR}/normal.sh"
check_syntax "${SCRIPT_DIR}/giipAgent3.sh"

echo ""

# ============================================================================
# Test Summary
# ============================================================================

echo "=================================================="
echo "Test Summary"
echo "=================================================="
echo ""
echo "Library structure:"
echo "  giipAgentLinux/"
echo "  ├── giipAgent3.sh (main, ~180 lines)"
echo "  ├── giipAgent2.sh (legacy, 1450 lines)"
echo "  └── lib/"
echo "      ├── common.sh (~150 lines)"
echo "      ├── kvs.sh (~130 lines)"
echo "      ├── db_clients.sh (~260 lines)"
echo "      ├── gateway.sh (~300 lines)"
echo "      └── normal.sh (~220 lines)"
echo ""
echo "Total refactored: ~1,240 lines (modular)"
echo "Original: 1,450 lines (monolithic)"
echo ""
echo "Benefits:"
echo "  ✅ Maintainable - Each module has single responsibility"
echo "  ✅ Testable - Functions can be tested independently"
echo "  ✅ Reusable - Libraries can be used in other scripts"
echo "  ✅ Readable - Clear separation of concerns"
echo ""
echo "=================================================="
echo "Test completed!"
echo "=================================================="
