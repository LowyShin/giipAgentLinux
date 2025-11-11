#!/bin/bash
# Test script for check_managed_databases.sh
# Purpose: Manually test managed database health check functionality

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../giipAgent.cnf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config file not found: $CONFIG_FILE"
    echo "Please create giipAgent.cnf in parent directory"
    exit 1
fi

# Load config variables
source "$CONFIG_FILE"

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
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Test completed successfully"
else
    echo "❌ Test failed with exit code: $EXIT_CODE"
fi
echo "========================================="

exit $EXIT_CODE
