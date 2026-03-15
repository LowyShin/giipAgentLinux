#!/bin/bash
# sync-full-query.sh
# Linux Agent - SQL Query Hash Full Text Sync
# Periodically uploads SQL text for hashes found in netstat

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_CMD="python3"

if ! command -v $PYTHON_CMD &> /dev/null; then
    PYTHON_CMD="python"
fi

if ! command -v $PYTHON_CMD &> /dev/null; then
    echo "ERROR: Python not found"
    exit 1
fi

$PYTHON_CMD "$SCRIPT_DIR/sync_full_query.py" "$@"
