#!/bin/bash
# lib/net3d.sh - Net3D Network Topology Data Collection Module
# Version: 1.0
# Date: 2025-12-16
# Purpose: Collects netstat/ss data for Net3D visualization (every 5 minutes)
# Usage: source lib/net3d.sh && collect_net3d_data <lssn>

# ============================================================================
# Required Dependencies
# ============================================================================
# - common.sh (for log_message)
# - kvs.sh (for kvs_put)

if ! declare -f log_message >/dev/null 2>&1; then
	echo "❌ Error: log_message not found. common.sh must be loaded first" >&2
	exit 1
fi

if ! declare -f kvs_put >/dev/null 2>&1; then
	echo "❌ Error: kvs_put not found. kvs.sh must be loaded first" >&2
	exit 1
fi

# Configuration
NET3D_INTERVAL=300  # 5 minutes
NET3D_STATE_FILE="${NET3D_STATE_FILE:-/tmp/giip_net3d_state}"

# ============================================================================
# Main Function: Collect and Upload Net3D Data
# ============================================================================
collect_net3d_data() {
    local lssn="$1"
    
    # 1. Check interval
    if ! should_run_net3d "$lssn"; then
        return 0
    fi
    
    log_message "INFO" "[Net3D] Starting network topology data collection for LSSN=$lssn"
    
    # 2. Collect Data
    local net_json="{}"
    
    # Try ss first (faster, modern), then netstat
    if command -v ss >/dev/null 2>&1; then
        net_json=$(_collect_with_ss)
    elif command -v netstat >/dev/null 2>&1; then
        net_json=$(_collect_with_netstat)
    else
        log_message "WARN" "[Net3D] Neither 'ss' nor 'netstat' found. Skipping."
        return 1
    fi
    
    # 3. Validation
    local json_len=${#net_json}
    if [ "$json_len" -lt 10 ]; then
        log_message "WARN" "[Net3D] Collected data is too short or empty. Skipping upload."
        return 1
    fi
    
    # 4. Upload to KVS
    # kFactor matches spec requirements: "netstat"
    # Data is stored as raw JSON in kValue
    if kvs_put "lssn" "${lssn}" "netstat" "$net_json"; then
        log_message "INFO" "[Net3D] Successfully uploaded netstat data"
        
        # Update state file only on success
        echo "$(date +%s)" > "${NET3D_STATE_FILE}_${lssn}"
        return 0
    else
        log_message "ERROR" "[Net3D] Failed to upload netstat data"
        return 1
    fi
}

# ============================================================================
# Helper: Check if it's time to run
# ============================================================================
should_run_net3d() {
    local lssn="$1"
    local state_file="${NET3D_STATE_FILE}_${lssn}"
    
    if [ ! -f "$state_file" ]; then
        return 0 # Run if first time
    fi
    
    local last_run=$(cat "$state_file")
    local current_time=$(date +%s)
    local elapsed=$((current_time - last_run))
    
    if (( elapsed >= NET3D_INTERVAL )); then
        return 0
    else
        # Debug log for skipped run (can be commented out to reduce noise)
        # echo "[Net3D] Skipping run (Effective interval: $elapsed / $NET3D_INTERVAL)" >&2
        return 1
    fi
}

# ============================================================================
# Helper: Collect using 'ss' command
# ============================================================================
_collect_with_ss() {
    # -n: numeric
    # -t: tcp
    # -p: processes (requires sudo for full details, but we do best effort)
    # -a: all states (including listening)
    
    # Python script to parse ss output and convert to JSON
    # Input format: State Recv-Q Send-Q Local Address:Port Peer Address:Port Process
    ss -ntap 2>/dev/null | python3 -c "
import sys, json, re

connections = []
try:
    # Skip header
    lines = sys.stdin.readlines()
    for line in lines[1:]:
        parts = line.split()
        if len(parts) < 4: continue
        
        state = parts[0]
        # Skip if not interesting states (optional filtering)
        if state not in ['ESTABLISHED', 'LISTEN', 'TIME_WAIT', 'CLOSE_WAIT', 'SYN_SENT', 'SYN_RECV']:
            continue
            
        local_part = parts[3]
        remote_part = parts[4]
        
        # Parse Local IP:Port
        if ']:' in local_part: # IPv6
            lip, lport = local_part.rsplit(':', 1)
            lip = lip.strip('[]')
        elif ':' in local_part:
            lip, lport = local_part.rsplit(':', 1)
        else:
            continue
            
        # Parse Remote IP:Port
        if ']:' in remote_part: # IPv6
            rip, rport = remote_part.rsplit(':', 1)
            rip = rip.strip('[]')
        elif ':' in remote_part:
            rip, rport = remote_part.rsplit(':', 1)
        else:
            continue

        process_info = ''
        if len(parts) > 5:
            process_info = ' '.join(parts[5:])
            
        connections.append({
            'proto': 'tcp',
            'state': state,
            'local_ip': lip,
            'local_port': lport,
            'remote_ip': rip,
            'remote_port': rport,
            'process': process_info
        })
        
    print(json.dumps({'connections': connections, 'source': 'ss', 'timestamp': '$(date +%s)'}))
except Exception as e:
    # Fallback empty JSON or error
    print(json.dumps({'connections': [], 'error': str(e)}))
"
}

# ============================================================================
# Helper: Collect using 'netstat' command
# ============================================================================
_collect_with_netstat() {
    # -n: numeric
    # -t: tcp
    # -p: processes (requires sudo)
    # -a: all
    # Warning: output format varies by version
    
    netstat -antp 2>/dev/null | python3 -c "
import sys, json, re

connections = []
try:
    lines = sys.stdin.readlines()
    for line in lines:
        if not line.startswith('tcp'): continue
        
        parts = line.split()
        # Typical netstat Output:
        # Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
        # tcp        0      0 0.0.0.0:22              0.0.0.0:*               LISTEN      -
        
        if len(parts) < 6: continue
        
        proto = parts[0]
        local_part = parts[3]
        remote_part = parts[4]
        state = parts[5]
        
        # Parse Local
        if ':' in local_part:
            lip, lport = local_part.rsplit(':', 1)
        else:
            continue

        # Parse Remote
        if ':' in remote_part:
            rip, rport = remote_part.rsplit(':', 1)
        else:
            continue
            
        process_info = ''
        if len(parts) > 6:
            process_info = ' '.join(parts[6:])
            
        connections.append({
            'proto': proto,
            'state': state,
            'local_ip': lip,
            'local_port': lport,
            'remote_ip': rip,
            'remote_port': rport,
            'process': process_info
        })

    print(json.dumps({'connections': connections, 'source': 'netstat', 'timestamp': '$(date +%s)'}))
except Exception as e:
    print(json.dumps({'connections': [], 'error': str(e)}))
"
}
