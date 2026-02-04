#!/bin/bash
set -euo pipefail

# Path to kvsput.sh
KVSPUT_SCRIPT="$(dirname "$0")/kvsput.sh"

# Define kFactor
KFACTOR="ps_ef_snapshot"

# Create a temporary file for JSON output
TMP_JSON_FILE=$(mktemp /tmp/ps_ef_XXXXXX.json)

# Capture ps -ef output, format it, and convert to JSON
# Using 'ps -eo' to get specific columns in a more predictable format
# and then manually structuring the JSON.
# Columns: user,pid,ppid,pcpu,start,tty,time,args

ps -eo user,pid,ppid,pcpu,start,tty,time,args --no-headers | 
awk '{
    user=$1; pid=$2; ppid=$3; pcpu=$4; start=$5; tty=$6; time=$7;
    # Reconstruct args, handle spaces
    cmd_start_index = index($0, $8);
    cmd = substr($0, cmd_start_index);

    gsub(/"/, """, user);
    gsub(/"/, """, pid);
    gsub(/"/, """, ppid);
    gsub(/"/, """, pcpu);
    gsub(/"/, """, start);
    gsub(/"/, """, tty);
    gsub(/"/, """, time);
    gsub(/"/, """, cmd);

    print "{ "user": "" user "", "pid": "" pid "", "ppid": "" ppid "", "pcpu": "" pcpu "", "start": "" start "", "tty": "" tty "", "time": "" time "", "cmd": "" cmd "" }"
}' | 
jq -s '.' > "$TMP_JSON_FILE"

# Check if JSON file was created and is not empty
if [[ ! -s "$TMP_JSON_FILE" ]]; then
    echo "ERROR: Failed to create JSON output or file is empty: $TMP_JSON_FILE" >&2
    rm -f "$TMP_JSON_FILE"
    exit 1
fi

echo "Captured ps -ef output and saved to $TMP_JSON_FILE" >&2

# Upload to KVS
"$KVSPUT_SCRIPT" "$TMP_JSON_FILE" "$KFACTOR"

# Clean up temporary file
rm -f "$TMP_JSON_FILE"

echo "ps -ef data pushed to KVS with kFactor: $KFACTOR" >&2
