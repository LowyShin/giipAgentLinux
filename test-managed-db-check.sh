#!/bin/bash
# Test script for check_managed_databases.sh
# Purpose: Manually test managed database health check functionality

# Initialize paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
CONFIG_FILE="$SCRIPT_DIR/../giipAgent.cnf"

# Load common.sh first (for load_config)
if [ ! -f "${LIB_DIR}/common.sh" ]; then
    echo "❌ Library not found: ${LIB_DIR}/common.sh"
    exit 1
fi

source "${LIB_DIR}/common.sh"

# Load configuration
load_config "../giipAgent.cnf"
if [ $? -ne 0 ]; then
    echo "❌ Failed to load configuration"
    exit 1
fi

# Load kvs.sh (for save_execution_log)
if [ ! -f "${LIB_DIR}/kvs.sh" ]; then
    echo "❌ Library not found: ${LIB_DIR}/kvs.sh"
    exit 1
fi

source "${LIB_DIR}/kvs.sh"

# Set LogFileName variable (required by check_managed_databases.sh)
export LogFileName="log/test-managed-db-check_$(date +%Y%m%d).log"
mkdir -p log

# Validate required variables
if [ -z "$lssn" ] || [ -z "$sk" ] || [ -z "$apiaddrv2" ] || [ -z "$apiaddrcode" ]; then
    echo "❌ Missing required config variables:"
    echo "   lssn: ${lssn:-NOT SET}"
    echo "   sk: ${sk:-NOT SET}"
    echo "   apiaddrv2: ${apiaddrv2:-NOT SET}"
    echo "   apiaddrcode: ${apiaddrcode:-NOT SET}"
    exit 1
fi

echo "========================================="
echo "🧪 Testing Managed Database Health Check"
echo "========================================="
echo "Config:"
echo "  LSSN: $lssn"
echo "  API: $apiaddrv2"
echo "  Script Dir: $SCRIPT_DIR"
echo "  Log File: $LogFileName"
echo "========================================="

# Load the check_managed_databases function
if [ ! -f "$SCRIPT_DIR/lib/check_managed_databases.sh" ]; then
    echo "❌ Module not found: $SCRIPT_DIR/lib/check_managed_databases.sh"
    exit 1
fi

source "$SCRIPT_DIR/lib/check_managed_databases.sh"

# Run the check
echo ""
echo "▶️  Running check_managed_databases()..."
echo ""

check_managed_databases

EXIT_CODE=$?

echo ""
echo "========================================="
echo "📊 Test Results Summary"
echo "========================================="

# Show log file contents
if [ -f "$LogFileName" ]; then
    echo ""
    echo "📄 Log File Contents:"
    echo "----------------------------------------"
    cat "$LogFileName"
    echo "----------------------------------------"
fi

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Test completed successfully"
else
    echo "❌ Test failed with exit code: $EXIT_CODE"
fi
echo "========================================="

exit $EXIT_CODE
