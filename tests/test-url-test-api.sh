#!/bin/bash
# ============================================================================
# test-url-test-api.sh - GIIP AI URL Test API verification
#
# Purpose:
#   Calls <server>/api/giip-proxy twice with a session token:
#     TEST 1  URLTestPut csn url depth context  (creates a URL test request
#             for https://www.google.com, depth SHALLOW)
#     TEST 2  URLTestGet csn                    (lists URL test requests)
#   and prints the HTTP status and response body of each.
#
# Origin:
#   Converted from tests/test-url-test-api.ps1 (introduced in 77700c0,
#   2026-02-13) because giipAgentLinux must contain no Windows scripts
#   (giip 2951). Same parameters, same defaults, same requests.
#
# Usage:
#   bash tests/test-url-test-api.sh --token 'YOUR_TOKEN' \
#        [--server http://localhost:3000] [--csn 47]
#   bash tests/test-url-test-api.sh --help
#   Without --token it prints a hint and exits 0 (as the .ps1 did).
#
# Differences from the .ps1 (not reproduced exactly):
#   - jsondata formatting: ConvertTo-Json produced indented JSON with
#     hashtable (unspecified) key order; this script sends compact JSON with
#     keys in the order csn, url, depth, context. The values are the same.
#   - Form encoding: WebUtility.UrlEncode encodes spaces as "+", curl
#     --data-urlencode uses "%20". Both decode to the same form values; the
#     field order of the form body may also differ.
#   - Failure detection: Invoke-WebRequest threw on connection errors and on
#     HTTP 4xx/5xx. This script treats a curl failure or a status >= 400 as
#     failure. On TEST 1 failure the error body is printed (as in the .ps1);
#     on TEST 2 failure only the message is printed (as in the .ps1).
#   - TEST 2 output: the .ps1 re-serialized the JSON (ConvertFrom-Json |
#     ConvertTo-Json -Depth 5). This script pretty-prints with jq when it is
#     installed, otherwise prints the raw body.
#   - Colors: PowerShell Write-Host colors are approximated with ANSI escape
#     codes, emitted only when stdout is a terminal.
# ============================================================================

SERVER="http://localhost:3000"
TOKEN=""
CSN="47"

usage() {
    sed -n '2,/^# =====*$/p' "$0" | sed -n '/^# Usage:/,/^#   Without --token/p' | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --server|-Server) SERVER="$2"; shift 2 ;;
        --token|-Token) TOKEN="$2"; shift 2 ;;
        --csn|-Csn) CSN="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [ -t 1 ]; then
    CYAN='\033[0;36m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
else
    CYAN=''; YELLOW=''; GREEN=''; RED=''; NC=''
fi
say() { printf '%b%s%b\n' "$1" "$2" "$NC"; }

say "$CYAN" "🧪 GIIP AI URL Test API Verification"

# 1. Token check
if [ -z "$TOKEN" ]; then
    say "$YELLOW" "🔑 Please provide a session token to run this test."
    echo "   Example: bash test-url-test-api.sh --token 'YOUR_TOKEN'"
    exit 0
fi

# The .ps1 cast csn with [int]; reject non-integers the same way.
if ! [[ "$CSN" =~ ^-?[0-9]+$ ]]; then
    echo "ERROR: --csn must be an integer: $CSN" >&2
    exit 1
fi
CSN_INT=$((10#${CSN#-}))
[ "${CSN:0:1}" = "-" ] && CSN_INT=$((-CSN_INT))

# post_proxy <text> <jsondata> <body_file> -> prints HTTP status, returns curl rc
post_proxy() {
    curl -sS -o "$3" -w '%{http_code}' -X POST "$SERVER/api/giip-proxy" \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        --data-urlencode "text=$1" \
        --data-urlencode "jsondata=$2" \
        --data-urlencode "token=$TOKEN" \
        --data-urlencode "usertoken=$TOKEN"
}

tmp_body="$(mktemp)"
trap 'rm -f "$tmp_body"' EXIT

# 2. Test: URLTestPut (Create Request)
echo ""
say "$YELLOW" "[TEST 1] Creating new URL Test Request..."
put_json="{\"csn\":$CSN_INT,\"url\":\"https://www.google.com\",\"depth\":\"SHALLOW\",\"context\":\"API Test Attempt\"}"
status="$(post_proxy "URLTestPut csn url depth context" "$put_json" "$tmp_body" 2>"$tmp_body.err")"
rc=$?
if [ $rc -eq 0 ] && [ "${status:-0}" -lt 400 ]; then
    say "$GREEN" "✅ PUT Response Status: $status"
    echo "Content: $(cat "$tmp_body")"
else
    if [ $rc -ne 0 ]; then
        say "$RED" "❌ PUT Failed: $(cat "$tmp_body.err")"
    else
        say "$RED" "❌ PUT Failed: HTTP $status"
        say "$RED" "Error Body: $(cat "$tmp_body")"
    fi
fi
rm -f "$tmp_body.err"

# 3. Test: URLTestGet (List Requests)
echo ""
say "$YELLOW" "[TEST 2] Fetching URL Test Requests..."
get_json="{\"csn\":$CSN_INT}"
status="$(post_proxy "URLTestGet csn" "$get_json" "$tmp_body" 2>"$tmp_body.err")"
rc=$?
if [ $rc -eq 0 ] && [ "${status:-0}" -lt 400 ]; then
    say "$GREEN" "✅ GET Response Status: $status"
    if command -v jq >/dev/null 2>&1 && jq . "$tmp_body" >/dev/null 2>&1; then
        jq . "$tmp_body"
    else
        cat "$tmp_body"; echo ""
    fi
else
    if [ $rc -ne 0 ]; then
        say "$RED" "❌ GET Failed: $(cat "$tmp_body.err")"
    else
        say "$RED" "❌ GET Failed: HTTP $status"
    fi
fi
rm -f "$tmp_body.err"
