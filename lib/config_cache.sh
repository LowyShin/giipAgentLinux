#!/bin/bash
# giipAgentLinux: Config Cache with TTL
# Reduces redundant LSvrGetConfig API calls by caching the response.
# TTL defaults to 60 seconds (one cron cycle). Set GIIP_CONFIG_CACHE_TTL env var to override.
#
# Usage:
#   source lib/config_cache.sh
#   config_cache_init "$config_tmpfile"   # Call AFTER config fetch, saves to cache
#   config_cache_load                     # Call BEFORE config fetch, loads from cache if fresh
#
# Cache file: /tmp/giip_config_cache_${lssn}.json
# Format: { "fetched_at": <unix_timestamp>, "is_gateway": <0|1>, "response": <raw_api_response> }

CONFIG_CACHE_FILE=""
CONFIG_CACHE_TTL="${GIIP_CONFIG_CACHE_TTL:-60}"

# Initialize cache file path from lssn
config_cache_init_path() {
    local lssn_val="${1:-${lssn:-0}}"
    CONFIG_CACHE_FILE="/tmp/giip_config_cache_${lssn_val}.json"
}

# Save fetched config to cache (call after successful API fetch)
# Args: path to raw API response file
config_cache_save() {
    local response_file="$1"
    [ -z "$CONFIG_CACHE_FILE" ] && config_cache_init_path

    if [ ! -f "$response_file" ] || [ ! -s "$response_file" ]; then
        return 1
    fi

    local raw_response
    raw_response=$(cat "$response_file" 2>/dev/null)
    [ -z "$raw_response" ] && return 1

    # Extract is_gateway from the response (same logic as giipAgent3.sh)
    local is_gw=""
    if command -v jq >/dev/null 2>&1; then
        is_gw=$(jq -r '.data[0].is_gateway // .is_gateway // empty' "$response_file" 2>/dev/null)
    fi
    if [ -z "$is_gw" ]; then
        local normalized
        normalized=$(tr -d '\n\r' < "$response_file")
        is_gw=$(echo "$normalized" | sed -n 's/.*"is_gateway"\s*:\s*\([^,}]*\).*/\1/p' | head -1 | tr -d ' ')
    fi
    [ "$is_gw" = "true" ] && is_gw="1"
    [ "$is_gw" = "false" ] && is_gw="0"
    [ -z "$is_gw" ] && is_gw=""

    local now
    now=$(date +%s)

    # Write cache file: timestamp + is_gateway + raw response
    if command -v jq >/dev/null 2>&1; then
        jq -n \
            --argjson fetched_at "$now" \
            --argjson is_gateway "$is_gw" \
            --arg raw_response "$raw_response" \
            '{ fetched_at: $fetched_at, is_gateway: $is_gateway, response: $raw_response }' \
            > "$CONFIG_CACHE_FILE" 2>/dev/null
    else
        echo "{\"fetched_at\":$now,\"is_gateway\":\"$is_gw\",\"response\":$raw_response}" \
            > "$CONFIG_CACHE_FILE"
    fi

    return 0
}

# Load config from cache if fresh (within TTL)
# Returns: 0 if cache loaded and is_gateway set, 1 if cache miss/expired
# On success, echoes the raw API response equivalent and sets global is_gateway_from_cache
config_cache_load() {
    [ -z "$CONFIG_CACHE_FILE" ] && config_cache_init_path

    if [ ! -f "$CONFIG_CACHE_FILE" ]; then
        return 1
    fi

    local cached_at is_gw raw_resp now
    now=$(date +%s)

    if command -v jq >/dev/null 2>&1; then
        cached_at=$(jq -r '.fetched_at // empty' "$CONFIG_CACHE_FILE" 2>/dev/null)
        is_gw=$(jq -r '.is_gateway // empty' "$CONFIG_CACHE_FILE" 2>/dev/null)
        raw_resp=$(jq -r '.response // empty' "$CONFIG_CACHE_FILE" 2>/dev/null)
    else
        cached_at=$(sed -n 's/.*"fetched_at":\s*\([0-9]*\).*/\1/p' "$CONFIG_CACHE_FILE" | head -1)
        is_gw=$(sed -n 's/.*"is_gateway":\s*"\?\([0-9]*\)\"\?.*/\1/p' "$CONFIG_CACHE_FILE" | head -1)
        raw_resp=$(sed -n 's/.*"response":\s*\(.*\)/\1/p' "$CONFIG_CACHE_FILE" | head -1)
    fi

    [ -z "$cached_at" ] && return 1

    local age=$((now - cached_at))
    if [ "$age" -gt "$CONFIG_CACHE_TTL" ]; then
        # Cache expired
        return 1
    fi

    # Valid cache hit — set global so caller can use it
    is_gateway_from_cache="$is_gw"
    raw_response_from_cache="$raw_resp"
    return 0
}

# Check if cache exists and is fresh (TTL check only, no load)
# Returns: 0 if fresh cache exists, 1 otherwise
config_cache_exists() {
    [ -z "$CONFIG_CACHE_FILE" ] && config_cache_init_path
    [ ! -f "$CONFIG_CACHE_FILE" ] && return 1

    local cached_at now
    now=$(date +%s)
    if command -v jq >/dev/null 2>&1; then
        cached_at=$(jq -r '.fetched_at // 0' "$CONFIG_CACHE_FILE" 2>/dev/null)
    else
        cached_at=$(sed -n 's/.*"fetched_at":\s*\([0-9]*\)/\1/p' "$CONFIG_CACHE_FILE" | head -1)
    fi

    [ -z "$cached_at" ] && return 1
    local age=$((now - cached_at))
    [ "$age" -gt "$CONFIG_CACHE_TTL" ] && return 1
    return 0
}

export -f config_cache_init_path
export -f config_cache_save
export -f config_cache_load
export -f config_cache_exists
