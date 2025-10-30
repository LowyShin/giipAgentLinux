#!/bin/bash
#
# SYNOPSIS:
#   Reads a JSON file and uploads its contents to KVS endpoint as per giipAgent.cfg
#
# USAGE:
#   ./kvs-upload-json.sh <json_file> [<kfactor>]
#
# DESCRIPTION:
#   - Reads giipAgent.cfg for KVS configuration
#   - Reads the specified JSON file
#   - Uploads the JSON data to the KVS endpoint using curl
#

set -e

# Detect config file location (support multiple locations)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../giipAgent.cnf" ]; then
  CFG_PATH="$SCRIPT_DIR/../giipAgent.cnf"
elif [ -f "$SCRIPT_DIR/../../giipAgent.cnf" ]; then
  CFG_PATH="$SCRIPT_DIR/../../giipAgent.cnf"
elif [ -f "/opt/giipAgentLinux/giipAgent.cnf" ]; then
  CFG_PATH="/opt/giipAgentLinux/giipAgent.cnf"
else
  echo "[ERROR] giipAgent.cnf not found in expected locations:" >&2
  echo "  - $SCRIPT_DIR/../giipAgent.cnf" >&2
  echo "  - $SCRIPT_DIR/../../giipAgent.cnf" >&2
  echo "  - /opt/giipAgentLinux/giipAgent.cnf" >&2
  exit 2
fi

JSON_FILE="$1"
KFACTOR="$2"

if [[ -z "$JSON_FILE" || ! -f "$JSON_FILE" ]]; then
  echo "[ERROR] JSON file required as first argument." >&2
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
# Priority: Endpoint > apiaddrv2
if [[ -n "${KVS_CONFIG[Endpoint]}" ]]; then
  ENDPOINT="${KVS_CONFIG[Endpoint]}"
elif [[ -n "${KVS_CONFIG[apiaddrv2]}" ]]; then
  ENDPOINT="${KVS_CONFIG[apiaddrv2]}"
else
  echo "[ERROR] Missing config: Endpoint or apiaddrv2" >&2
  exit 3
fi

# Add function code if available (FunctionCode > apiaddrcode)
if [[ -n "${KVS_CONFIG[FunctionCode]}" ]]; then
  ENDPOINT+="?code=${KVS_CONFIG[FunctionCode]}"
elif [[ -n "${KVS_CONFIG[apiaddrcode]}" ]]; then
  ENDPOINT+="?code=${KVS_CONFIG[apiaddrcode]}"
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
KVSP_TEXT="KVSPut kType kKey kFactor kValue"

# Build form parameters: text, token, jsondata
POST_DATA="text=$(printf "%s" "$KVSP_TEXT" | jq -sRr @uri)"
POST_DATA+="&token=$(printf "%s" "$USER_TOKEN" | jq -sRr @uri)"
POST_DATA+="&jsondata=$(printf "%s" "$JSON_PAYLOAD" | jq -sRr @uri)"

# Diagnostic output
echo "[DIAG] Endpoint: $ENDPOINT"
echo "[DIAG] KVSP text: $KVSP_TEXT"
echo "[DIAG] Token: ${USER_TOKEN:0:10}..." 
echo "[DIAG] jsondata (file) preview: ${JSON_FILE_COMPACT:0:400}"

# Upload: avoid passing very large data on the command line (can hit ARG_MAX).
# Write the urlencoded form body to a temp file and let curl read it via @file.
TMP_POST=$(mktemp)
printf '%s' "$POST_DATA" > "$TMP_POST"
resp=$(curl -s -X POST "$ENDPOINT" -H 'Content-Type: application/x-www-form-urlencoded' --data-binary "@$TMP_POST")
rc=$?
rm -f "$TMP_POST"
if [ $rc -ne 0 ]; then
  echo "[ERROR] curl failed with exit code $rc" >&2
  echo "[INFO] KVS upload result (partial): $resp" >&2
  exit $rc
fi
echo "[INFO] KVS upload result: $resp"
