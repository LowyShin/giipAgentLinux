#!/bin/bash
# Test script to verify CPU/Memory collection helpers
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LIB_DIR="${SCRIPT_DIR}/../lib"

if [ -f "${LIB_DIR}/common.sh" ]; then
    . "${LIB_DIR}/common.sh"
    
    cpu=$(get_cpu_usage)
    mem=$(get_mem_usage)
    
    echo "CPU Usage: ${cpu}%"
    echo "Memory Usage: ${mem}%"
    
    if [[ "$cpu" =~ ^[0-9]+$ ]] && [[ "$mem" =~ ^[0-9]+$ ]]; then
        echo "✅ SUCCESS: Metrics are numeric."
    else
        echo "❌ FAILURE: Metrics are not numeric."
    fi
else
    echo "❌ Error: common.sh not found"
fi
