#!/bin/bash
# ============================================================================
# test-network-collection.sh - Test network collection on a remote server
#
# Purpose:
#   Uploads the network debug script to a remote Linux server with scp and
#   runs it there over ssh.
#
# Origin:
#   Converted from tests/test-network-collection.ps1 (introduced in 77700c0,
#   2026-02-13) because giipAgentLinux must contain no Windows scripts
#   (giip 2951). Same parameters, same defaults, same steps. Like the .ps1,
#   a failing scp/ssh does not stop the script.
#
# Usage:
#   bash tests/test-network-collection.sh [--server 10.2.0.5] [--user root]
#   bash tests/test-network-collection.sh --help
#
# Differences from the .ps1 (not reproduced exactly):
#   - Debug script path: the .ps1 used "giipscripts/debug-network.sh" relative
#     to the current directory, a path that has never existed in this repo
#     (the file has been scripts/debug-network.sh since 77700c0). This script
#     uses ./giipscripts/debug-network.sh if it exists, otherwise
#     "<repo>/scripts/debug-network.sh".
#   - Colors: PowerShell Write-Host colors are approximated with ANSI escape
#     codes, emitted only when stdout is a terminal.
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
    CYAN='\033[0;36m'; GREEN='\033[0;32m'; NC='\033[0m'
else
    CYAN=''; GREEN=''; NC=''
fi
say() { printf '%b%s%b\n' "$1" "$2" "$NC"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

debug_script="giipscripts/debug-network.sh"
if [ ! -f "$debug_script" ]; then
    debug_script="$REPO_ROOT/scripts/debug-network.sh"
fi

say "$CYAN" "Uploading debug script to $SERVER..."
scp "$debug_script" "${USER_NAME}@${SERVER}:/tmp/"

echo ""
say "$CYAN" "Executing debug script on server..."
ssh "${USER_NAME}@${SERVER}" "chmod +x /tmp/debug-network.sh && bash /tmp/debug-network.sh"

echo ""
say "$GREEN" "========================================"
say "$GREEN" "Debug complete!"
say "$GREEN" "========================================"
