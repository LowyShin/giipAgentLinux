#!/bin/bash
#
# SYNOPSIS:
#   Reads a JSON file and uploads its contents to KVS endpoint as per giipAgent.cfg
#
# USAGE:
#   ./kvsput.sh <json_file> <kfactor>
#
# DESCRIPTION:
#   - Reads giipAgent.cfg for KVS configuration
#   - Reads the specified JSON file
#   - Uploads the JSON data to the KVS endpoint using curl
#
# SPECIFICATIONS:
#   - API Rules: giipfaw/docs/giipapi_rules.md (text/jsondata 분리 규칙)
#   - API Pattern: giipfaw/docs/GIIPAPISK2_API_PATTERN.md
#   - KVS Spec: giipAgentLinux/docs/KVSPUT_API_SPECIFICATION.md ⭐⭐
#   - Architecture: giipdb/docs/KVSPUT_ARCHITECTURE.md
#   - CQE System: giipdb/docs/CQE_SYSTEM_ARCHITECTURE.md
#

set -e

# Detect config file location (support multiple locations)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Priority 1: Environment variable CONFIG_FILE
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  CFG_PATH="$CONFIG_FILE"
# Priority 2: Auto-detect from script location
elif [ -f "$SCRIPT_DIR/../giipAgent.cnf" ]; then
  CFG_PATH="$SCRIPT_DIR/../giipAgent.cnf"
elif [ -f "$SCRIPT_DIR/../../giipAgent.cnf" ]; then
  CFG_PATH="$SCRIPT_DIR/../../giipAgent.cnf"
elif [ -f "/opt/giipAgentLinux/giipAgent.cnf" ]; then
  CFG_PATH="/opt/giipAgentLinux/giipAgent.cnf"
elif [ -f "/home/giip/giipAgent.cnf" ]; then
  CFG_PATH="/home/giip/giipAgent.cnf"
elif [ -f "/root/giipAgent.cnf" ]; then
  CFG_PATH="/root/giipAgent.cnf"
else
  echo "[ERROR] giipAgent.cnf not found in expected locations:" >&2
  echo "  - \$CONFIG_FILE (env var)" >&2
  echo "  - $SCRIPT_DIR/../giipAgent.cnf" >&2
  echo "  - $SCRIPT_DIR/../../giipAgent.cnf" >&2
  echo "  - /opt/giipAgentLinux/giipAgent.cnf" >&2
  echo "  - /home/giip/giipAgent.cnf" >&2
  echo "  - /root/giipAgent.cnf" >&2
  exit 2
fi

echo "[INFO] Using config: $CFG_PATH" >&2

JSON_FILE="$1"
KFACTOR="$2"

if [[ -z "$JSON_FILE" || ! -f "$JSON_FILE" ]]; then
  echo "[ERROR] JSON file required as first argument." >&2
  exit 2
fi

# Verify config file exists
if [ ! -f "$CFG_PATH" ]; then
  echo "[ERROR] Config file does not exist: $CFG_PATH" >&2
  echo "[ERROR] Please check the file location or set CONFIG_FILE environment variable" >&2
  exit 2
fi

# Read config
declare -A KVS_CONFIG
while IFS= read -r line; do
  # skip empty lines and lines starting with '#'
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  # match key = value (allow spaces around =)
  if [[ "$line" =~ ^([A-Za-z0-9_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"
    # trim surrounding double or single quotes if present (safe, avoids nested-quote issues)
    case "$val" in
      '"'*) val="${val#\"}" ; val="${val%\"}" ;;
      "'"*) val="${val#\'}" ; val="${val%\'}" ;;
    esac
    # Another robust approach: if still surrounded by matching quotes, strip them
    if [[ ${#val} -ge 2 ]]; then
      first=${val:0:1}
      last=${val: -1}
      if [[ ( "$first" == '"' && "$last" == '"' ) || ( "$first" == "'" && "$last" == "'" ) ]]; then
        val=${val:1:-1}
      fi
    fi
    KVS_CONFIG[$key]="$val"
  fi
done < "$CFG_PATH"

# Required config (use apiaddrv2 for giipApiSk2 endpoint)
# Priority: apiaddrv2 > Endpoint (prefer v2 API for KVS)
if [[ -n "${KVS_CONFIG[apiaddrv2]}" ]]; then
  ENDPOINT="${KVS_CONFIG[apiaddrv2]}"
elif [[ -n "${KVS_CONFIG[Endpoint]}" ]]; then
  ENDPOINT="${KVS_CONFIG[Endpoint]}"
else
  echo "[ERROR] Missing config: apiaddrv2 or Endpoint" >&2
  exit 3
fi

# Add function code if available (apiaddrcode > FunctionCode, prefer v2)
if [[ -n "${KVS_CONFIG[apiaddrcode]}" ]]; then
  ENDPOINT+="?code=${KVS_CONFIG[apiaddrcode]}"
elif [[ -n "${KVS_CONFIG[FunctionCode]}" ]]; then
  ENDPOINT+="?code=${KVS_CONFIG[FunctionCode]}"
fi

# UserToken (sk for SK-based auth)
if [[ -z "${KVS_CONFIG[UserToken]}" && -z "${KVS_CONFIG[sk]}" ]]; then
  echo "[ERROR] Missing config: UserToken or sk" >&2
  exit 3
fi
USER_TOKEN="${KVS_CONFIG[UserToken]:-${KVS_CONFIG[sk]}}"

# KKey (hostname, fallback to lssn if needed)
if [[ -z "${KVS_CONFIG[KKey]}" ]]; then
  if [[ -n "${KVS_CONFIG[lssn]}" ]]; then
    KVS_CONFIG[KKey]="${KVS_CONFIG[lssn]}"
  else
    KVS_CONFIG[KKey]="$(hostname)"
  fi
fi

# Optional: Check if upload is disabled
if [[ "${KVS_CONFIG[Enabled]}" == "false" ]]; then
  echo "[INFO] KVS upload disabled. Showing JSON:"
  cat "$JSON_FILE"
  exit 0
fi

# Ensure required tools
command -v jq >/dev/null 2>&1 || { echo "[ERROR] jq is required but not found" >&2; exit 4; }
command -v curl >/dev/null 2>&1 || { echo "[ERROR] curl is required but not found" >&2; exit 4; }

# Per giipapi rules (giipfaw/docs/giipapi_rules.md):
# [필수] 모든 변수값(파라미터)은 반드시 jsondata 필드에 JSON 문자열로 만들어 전달해야 하며,
# text 필드에는 프로시저명과 파라미터 이름만 포함해야 합니다.

# Compact the JSON file (this will be kValue in jsondata)
JSON_FILE_COMPACT=$(jq -c . "$JSON_FILE")

# Build jsondata with proper structure: {kType, kKey, kFactor, kValue}
JSON_PAYLOAD=$(jq -n \
  --arg kType "lssn" \
  --arg kKey "${KVS_CONFIG[KKey]}" \
  --arg kFactor "$KFACTOR" \
  --argjson kValue "$JSON_FILE_COMPACT" \
  '{kType: $kType, kKey: $kKey, kFactor: $kFactor, kValue: $kValue}')

# KVSP text: procedure name + parameter NAMES only (as required by giipapi)
# NOTE: kValue는 text에 포함하지 않음 (jsondata 전체로 전달됨)
KVSP_TEXT="KVSPut kType kKey kFactor"

# Build form parameters: text, token, jsondata
POST_DATA="text=$(printf "%s" "$KVSP_TEXT" | jq -sRr @uri)"
POST_DATA+="&token=$(printf "%s" "$USER_TOKEN" | jq -sRr @uri)"
POST_DATA+="&jsondata=$(printf "%s" "$JSON_PAYLOAD" | jq -sRr @uri)"

# Simplified diagnostic output (no raw JSON data)
echo "[INFO] Uploading to KVS: kFactor=$KFACTOR, kKey=$(echo "$JSON_PAYLOAD" | jq -r '.kKey')" >&2

# Get JSON size for diagnostics
JSON_SIZE=$(echo "$JSON_PAYLOAD" | wc -c)
echo "[INFO] Payload size: $JSON_SIZE bytes" >&2

# Warning for large payloads
if [ "$JSON_SIZE" -gt 1000000 ]; then
  echo "[WARN] Large payload detected (>1MB). This may cause timeout issues." >&2
  echo "[WARN] Consider splitting data into smaller batches if upload fails." >&2
fi

# Set timeout (default 60s, can be overridden via environment)
CURL_TIMEOUT="${CURL_TIMEOUT:-60}"

# Upload: avoid passing very large data on the command line (can hit ARG_MAX).
# Write the urlencoded form body to a temp file and let curl read it via @file.
TMP_POST=$(mktemp)
printf '%s' "$POST_DATA" > "$TMP_POST"

echo "[INFO] Sending request to: ${ENDPOINT%%\?*}" >&2
echo "[INFO] Timeout: ${CURL_TIMEOUT}s" >&2

resp=$(curl -s -X POST "$ENDPOINT" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Expect:' \
  --max-time "$CURL_TIMEOUT" \
  --connect-timeout 10 \
  --data-binary "@$TMP_POST" 2>&1)
rc=$?
rm -f "$TMP_POST"

if [ $rc -ne 0 ]; then
  echo "[ERROR] curl failed with exit code $rc" >&2
  case $rc in
    6) echo "[ERROR] Could not resolve host. Check network/DNS." >&2 ;;
    7) echo "[ERROR] Failed to connect to host. Check endpoint URL and firewall." >&2 ;;
    28) echo "[ERROR] Operation timeout after ${CURL_TIMEOUT}s. Data may be too large." >&2 
        echo "[ERROR] Try reducing data size or increasing CURL_TIMEOUT." >&2 ;;
    35) echo "[ERROR] SSL connection error. Check TLS/SSL configuration." >&2 ;;
    52) echo "[ERROR] Empty response from server." >&2 ;;
    *) echo "[ERROR] Curl error code: $rc (see https://curl.se/docs/manpage.html)" >&2 ;;
  esac
  exit $rc
fi

# Check response status (simplified)
if echo "$resp" | jq -e '.data[0].RstVal == 200' >/dev/null 2>&1; then
  echo "[SUCCESS] KVS uploaded successfully" >&2
elif echo "$resp" | jq -e '.data[0].RstVal' >/dev/null 2>&1; then
  RSTVAL=$(echo "$resp" | jq -r '.data[0].RstVal')
  RSTMSG=$(echo "$resp" | jq -r '.data[0].RstMsg')
  echo "[ERROR] KVS upload failed: RstVal=$RSTVAL, Msg=$RSTMSG" >&2
  exit 1
else
  echo "[ERROR] Unexpected response format" >&2
  echo "$resp" >&2
  exit 1
fi
