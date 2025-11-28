#!/bin/bash
################################################################################
# Test script for queue_get function
# Purpose: Simple test for CQE queue fetching
# Usage: ./test-queue-get.sh [lssn] [hostname] [os]
################################################################################

set -o pipefail

# Get absolute paths
# From tests/ → go up one level to giipAgentLinux/
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
LIB_DIR="${PARENT_DIR}/lib"

# Config file: Follow giipAgent3.sh pattern
# giipAgent3.sh is in giipAgentLinux/, uses ../giipAgent.cnf (sibling of giipAgent3.sh)
# test-queue-get.sh is in tests/, so it also needs ../giipAgent.cnf (same location)
CONFIG_FILE="${SCRIPT_DIR}/../giipAgent.cnf"

# Load config
if [ ! -f "$CONFIG_FILE" ]; then
	echo "❌ Config not found: $CONFIG_FILE"
	echo "   Expected location (same as giipAgent3.sh): $PARENT_DIR/"
	exit 1
fi
. "$CONFIG_FILE"

# ⚠️ DEBUG: Show which config file is being used and loaded values
echo "📋 Configuration loaded:"
echo "   File: $CONFIG_FILE"
echo "   sk: ${sk:-(not set)}"
echo "   apiaddrv2: ${apiaddrv2:-(not set)}"
echo "   apiaddrcode: ${apiaddrcode:-(not set)}"
echo "   lssn: ${lssn:-(not set)}"
echo ""

# Validate required variables
if [ -z "$sk" ] || [ "$sk" = "<your secret key>" ]; then
	echo "❌ ERROR: sk not configured in $CONFIG_FILE"
	echo "   Current value: $sk"
	echo "   You must set a real session key value"
	exit 1
fi

if [ -z "$apiaddrcode" ] || [ "$apiaddrcode" = "YOUR_AZURE_FUNCTION_KEY_HERE" ]; then
	echo "❌ ERROR: apiaddrcode not configured in $CONFIG_FILE"
	echo "   Current value: $apiaddrcode"
	echo "   You must set a real Azure function key"
	exit 1
fi
echo ""

# Test parameters
TEST_LSSN="${1:-${lssn:-12345}}"
TEST_HOSTNAME="${2:-test-server}"
TEST_OS="${3:-Linux}"
TEST_OUTPUT_FILE="/tmp/queue_output_$$.sh"

# Load cqe library
if [ ! -f "$LIB_DIR/cqe.sh" ]; then
	echo "❌ cqe.sh not found: $LIB_DIR/cqe.sh"
	exit 1
fi
. "$LIB_DIR/cqe.sh"

# Run queue_get
echo "Testing queue_get..."
echo "  LSSN: $TEST_LSSN"
echo "  Host: $TEST_HOSTNAME"
echo "  OS: $TEST_OS"
echo ""

queue_get "$TEST_LSSN" "$TEST_HOSTNAME" "$TEST_OS" "$TEST_OUTPUT_FILE"
exit_code=$?

# Show results
if [ $exit_code -eq 0 ]; then
	if [ -f "$TEST_OUTPUT_FILE" ] && [ -s "$TEST_OUTPUT_FILE" ]; then
		echo "✅ SUCCESS"
		echo ""
		echo "Output file: $TEST_OUTPUT_FILE"
		echo "Size: $(wc -c < "$TEST_OUTPUT_FILE") bytes"
		echo ""
		echo "Content:"
		cat "$TEST_OUTPUT_FILE"
		chmod 600 "$TEST_OUTPUT_FILE"
		exit 0
	else
		echo "❌ FAILED: Output file empty or not created"
		exit 1
	fi
else
	echo "❌ FAILED: queue_get returned $exit_code"
	exit 1
fi
