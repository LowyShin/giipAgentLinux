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
    
    # Detect Python
    local python_cmd=""
    if command -v python3 >/dev/null 2>&1; then
        python_cmd="python3"
    elif command -v python >/dev/null 2>&1; then
        python_cmd="python"
    else
        log_message "ERROR" "[Net3D] Python not found. Cannot parse network data."
        return 1
    fi

    # 2. Collect Data
    local net_json="{}"
    local source_cmd=""
    
    # Try ss first (faster, modern), then netstat
    if command -v ss >/dev/null 2>&1; then
        source_cmd="ss"
        net_json=$(_collect_with_ss "$lssn" "$python_cmd")
    elif command -v netstat >/dev/null 2>&1; then
        source_cmd="netstat"
        net_json=$(_collect_with_netstat "$lssn" "$python_cmd")
    else
        log_message "WARN" "[Net3D] Neither 'ss' nor 'netstat' found. Skipping."
        return 1
    fi
    
    # 3. Validation & Count Logging
    local json_len=${#net_json}
    if [ "$json_len" -lt 10 ] || [[ "$net_json" == *"\"error\":"* ]]; then
        log_message "WARN" "[Net3D] Collected data is invalid or contains error: ${net_json:0:100}..."
        return 1
    fi
    
    # Extract connection count for logging (using grep/sed purely for counting)
    local conn_count=$(echo "$net_json" | grep -o "\"local_ip\"" | wc -l)
    log_message "INFO" "[Net3D] Collected ${conn_count} connections using ${source_cmd}"
    
    # 4. Upload to KVS
    # kFactor matches spec requirements: "netstat"
    # Data is stored as raw JSON in kValue
    # We include 'lssn' in the JSON body just in case the backend/frontend expects it inside
    if kvs_put "lssn" "${lssn}" "netstat" "$net_json"; then
        log_message "INFO" "[Net3D] Successfully uploaded netstat data (${json_len} bytes)"
        
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
        return 1
    fi
}

# ============================================================================
# Helper: Collect using 'ss' command
# ============================================================================
_collect_with_ss() {
    local lssn="$1"
    local python_cmd="$2"
    
    # -n: numeric
    # -t: tcp
    # -p: processes (requires sudo for full details, but we do best effort)
    # -a: all states (including listening)
    # 2>/dev/null to silence stderr errors
    
    ss -ntap 2>/dev/null | $python_cmd -c "
import sys, json, re

connections = []
try:
    lines = sys.stdin.readlines()
    for line in lines:
        parts = line.split()
        if len(parts) < 4: continue
        
        # Robust Header Skip: If first column is 'State', it's a header
        if parts[0].strip().lower() == 'state':
            continue
            
        state = parts[0]
        # Filter for relevant states
        if state not in ['ESTABLISHED', 'LISTEN', 'TIME_WAIT', 'CLOSE_WAIT', 'SYN_SENT', 'SYN_RECV']:
            continue
            
        # ss columns can vary, but usually: State Recv-Q Send-Q Local Peer ...
        # We look for IP:Port patterns
        local_part = parts[3]
        remote_part = parts[4]
        
        # Safe extraction of IP/Port
        def parse_addr(addr):
            if ']:' in addr: # IPv6 [::1]:22
                ip, port = addr.rsplit(':', 1)
                ip = ip.strip('[]')
                return ip, port
            elif ':' in addr: # IPv4 1.2.3.4:22
                ip, port = addr.rsplit(':', 1)
                return ip, port
            return None, None

        lip, lport = parse_addr(local_part)
        rip, rport = parse_addr(remote_part)
        
        if not lip or not rip: continue

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
        
    print(json.dumps({
        'connections': connections, 
        'source': 'ss', 
        'lssn': int('$lssn'),
        'timestamp': '$(date +%s)'
    }))
except Exception as e:
    print(json.dumps({'connections': [], 'error': str(e)}))
"
}

# ============================================================================
# Helper: Collect using 'netstat' command
# ============================================================================
_collect_with_netstat() {
    local lssn="$1"
    local python_cmd="$2"
    
    netstat -antp 2>/dev/null | $python_cmd -c "
import sys, json, re

connections = []
try:
    lines = sys.stdin.readlines()
    for line in lines:
        # Skip headers / non-tcp lines
        if not line.strip().startswith('tcp'): continue
        
        parts = line.split()
        # Typical netstat: Proto Recv-Q Send-Q Local Foreign State PID/Program
        if len(parts) < 6: continue
        
        proto = parts[0]
        local_part = parts[3]
        remote_part = parts[4]
        state = parts[5]
        
        # Netstat often uses 0.0.0.0:* for random ports in foreign address, but we parse what we see
        def parse_addr(addr):
            if ':' in addr:
                return addr.rsplit(':', 1)
            return None, None
            
        lip, lport = parse_addr(local_part) or (local_part, '')
        rip, rport = parse_addr(remote_part) or (remote_part, '')
        
        if not lip: continue
            
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

    print(json.dumps({
        'connections': connections, 
        'source': 'netstat', 
        'lssn': int('$lssn'),
        'timestamp': '$(date +%s)'
    }))
except Exception as e:
    print(json.dumps({'connections': [], 'error': str(e)}))
"
}
