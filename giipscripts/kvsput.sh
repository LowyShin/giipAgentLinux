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

CFG_PATH="../../giipAgent.cnf"
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

# Required config
for k in Endpoint UserToken KType KKey Enabled; do
  if [[ -z "${KVS_CONFIG[$k]}" ]]; then
    echo "[ERROR] Missing config: $k" >&2
    exit 3
  fi
done

if [[ "${KVS_CONFIG[Enabled]}" != "true" ]]; then
  echo "[INFO] KVS upload disabled. Showing JSON:"
  cat "$JSON_FILE"
  exit 0
fi

ENDPOINT="${KVS_CONFIG[Endpoint]}"
if [[ -n "${KVS_CONFIG[FunctionCode]}" ]]; then
  ENDPOINT+="?code=${KVS_CONFIG[FunctionCode]}"
fi

# Ensure required tools
command -v jq >/dev/null 2>&1 || { echo "[ERROR] jq is required but not found" >&2; exit 4; }
command -v curl >/dev/null 2>&1 || { echo "[ERROR] curl is required but not found" >&2; exit 4; }

# Per giipapi rules: 'text' must contain only the procedure name and parameter NAMES (no values)
# Actual values must be passed inside jsondata.
# KVSP text (procedure name + param NAMES as required by giipapi)
KVSP_TEXT="KVSPut lssn ${KVS_CONFIG[KKey]} $KFACTOR"
# Compact the JSON file (this is the data you want in jsonData)
JSON_FILE_COMPACT=$(jq -c . "$JSON_FILE")
# (no wrapper) we will send the compacted JSON file content directly as jsondata

# Build form parameters to match PowerShell example: text, token, jsondata
POST_DATA="text=$(printf "%s" "$KVSP_TEXT" | jq -sRr @uri)"
POST_DATA+="&token=$(printf "%s" "${KVS_CONFIG[UserToken]}" | jq -sRr @uri)"
POST_DATA+="&jsondata=$(printf "%s" "$JSON_FILE_COMPACT" | jq -sRr @uri)"

# Diagnostic output
echo "[DIAG] Endpoint: $ENDPOINT"
echo "[DIAG] KVSP text: $KVSP_TEXT"
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
