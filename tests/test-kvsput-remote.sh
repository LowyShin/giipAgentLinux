#!/bin/bash
# ============================================================================
# test-kvsput-remote.sh - Test kvsput.sh on a remote server
#
# Purpose:
#   Uploads the kvsput test script to a remote Linux server with scp, runs it
#   there over ssh, and on success prints how to check the kvstest KVS rows.
#
# Origin:
#   Converted from tests/test-kvsput-remote.ps1 (introduced in 77700c0,
#   2026-02-13) because giipAgentLinux must contain no Windows scripts
#   (giip 2951). Same parameters, same defaults, same steps.
#
# Usage:
#   bash tests/test-kvsput-remote.sh [--server 10.2.0.5] [--user root]
#   bash tests/test-kvsput-remote.sh --help
#
# Differences from the .ps1 (not reproduced exactly):
#   - Test script path: the .ps1 looked for "<tests>/giipscripts/test-kvsput.sh",
#     a path that has never existed in this repo (the file has been
#     scripts/test-kvsput.sh since 77700c0). This script tries the original
#     path first and falls back to "<repo>/scripts/test-kvsput.sh".
#   - DB check: the .ps1 ran "<repo>/../giipdb/check_autodiscover_kvs.ps1
#     -KFactor kvstest -Top 1" when that file existed. A PowerShell script
#     cannot be run from here, so this script only prints the command to run
#     on the Windows dev PC (the same hint the .ps1 printed when the file was
#     missing).
#   - Colors: PowerShell Write-Host colors are approximated with ANSI escape
#     codes, emitted only when stdout is a terminal.
#   - Errors: Write-Error output (PowerShell error record) becomes a plain
#     "ERROR: ..." line on stderr; exit codes are the same (1).
# ============================================================================

SERVER="10.2.0.5"
USER_NAME="root"

usage() {
    sed -n '2,/^# =====*$/p' "$0" | sed -n '/^# Usage:/,/^#   bash .*--help$/p' | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --server|-Server) SERVER="$2"; shift 2 ;;
        --user|-User) USER_NAME="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [ -t 1 ]; then
    CYAN='\033[0;36m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'; GRAY='\033[0;90m'; NC='\033[0m'
else
    CYAN=''; YELLOW=''; GREEN=''; RED=''; GRAY=''; NC=''
fi
say() { printf '%b%s%b\n' "$1" "$2" "$NC"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

say "$CYAN" "========================================"
say "$CYAN" "kvsput.sh Remote Test"
say "$CYAN" "Server: $SERVER"
say "$CYAN" "========================================"
echo ""

script_path="$SCRIPT_DIR/giipscripts/test-kvsput.sh"
if [ ! -f "$script_path" ]; then
    script_path="$REPO_ROOT/scripts/test-kvsput.sh"
fi

if [ ! -f "$script_path" ]; then
    echo "ERROR: Test script not found: $script_path" >&2
    exit 1
fi

# 1. Upload test script
say "$YELLOW" "1. Uploading test script..."
if ! scp "$script_path" "${USER_NAME}@${SERVER}:/tmp/test-kvsput.sh"; then
    echo "ERROR: Test execution failed: Failed to upload test script" >&2
    exit 1
fi
say "$GREEN" "   ✓ Uploaded"
echo ""

# 2. Execute test
say "$YELLOW" "2. Executing test on server..."
say "$GRAY" "========================================"
ssh "${USER_NAME}@${SERVER}" "chmod +x /tmp/test-kvsput.sh && bash /tmp/test-kvsput.sh"
exit_code=$?
say "$GRAY" "========================================"
echo ""

if [ "$exit_code" -eq 0 ]; then
    say "$GREEN" "✅ Test completed successfully!"
    echo ""
    say "$CYAN" "Checking database..."
    # The .ps1 invoked giipdb/check_autodiscover_kvs.ps1 here when present;
    # that is a PowerShell script, so only the command is shown.
    say "$YELLOW" "Run this to check (Windows dev PC, giipdb checkout):"
    say "$GRAY" "  cd c:\\Users\\lowys\\Downloads\\projects\\giipprj\\giipdb"
    say "$GRAY" "  .\\check_autodiscover_kvs.ps1 -KFactor kvstest"
else
    say "$RED" "❌ Test failed with exit code: $exit_code"
    echo ""
    say "$YELLOW" "Common Issues:"
    say "$GRAY" "1. Missing jq: sudo apt-get install jq"
    say "$GRAY" "2. Invalid config: Check giipAgent.cnf"
    say "$GRAY" "3. Network issue: Check firewall/connectivity"
fi

echo ""
say "$CYAN" "========================================"
say "$CYAN" "Test complete"
say "$CYAN" "========================================"
