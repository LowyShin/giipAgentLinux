#!/bin/bash
################################################################################
# Test script for queue_get function
# Purpose: Simple test for CQE queue fetching
# Usage: ./test-queue-get.sh [lssn] [hostname] [os]
################################################################################

set -o pipefail

# Paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$( cd "${SCRIPT_DIR}/.." && pwd )"
LIB_DIR="${PARENT_DIR}/lib"
CONFIG_FILE="${PARENT_DIR}/giipAgent.cnf"

# Load config
if [ ! -f "$CONFIG_FILE" ]; then
	echo "❌ Config not found: $CONFIG_FILE"
	exit 1
fi
. "$CONFIG_FILE"

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
