#!/bin/bash
# lib/server_info.sh - Server IP Information Collection Module
# Version: 1.0
# Date: 2025-12-27
# Purpose: Collect server's own network interface IP addresses
# Usage: source lib/server_info.sh && collect_server_ips <lssn>

# UTF-8 환경 설정 (필수!)
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# ============================================================================
# Dependencies Check
# ============================================================================
if ! declare -f log_message >/dev/null 2>&1; then
    echo "❌ Error: log_message not found. common.sh must be loaded first" >&2
    exit 1
fi

# ============================================================================
# Main Function: Collect Server IPs
# ============================================================================
# Arguments:
#   $1: lssn (Server Serial Number)
# Returns:
#   JSON string with interface information
# ============================================================================
collect_server_ips() {
    local lssn="${1:-}"
    
    if [[ -z "$lssn" ]]; then
        log_message "ERROR" "[ServerInfo] Missing lssn parameter"
        echo "{\"error\": \"Missing lssn\"}"
        return 1
    fi
    
    # Detect Python
    local python_cmd=""
    if command -v python3 >/dev/null 2>&1; then
        python_cmd="python3"
    elif command -v python >/dev/null 2>&1; then
        python_cmd="python"
    else
        log_message "ERROR" "[ServerInfo] Python not found"
        echo "{\"error\": \"Python not found\"}"
        return 1
    fi
    
    log_message "INFO" "[ServerInfo] Collecting IP information for LSSN=$lssn"
    
    # Try 'ip addr' first (modern, preferred)
    if command -v ip >/dev/null 2>&1; then
        _collect_ips_with_ip "$lssn" "$python_cmd"
    elif command -v ifconfig >/dev/null 2>&1; then
        _collect_ips_with_ifconfig "$lssn" "$python_cmd"
    else
        log_message "ERROR" "[ServerInfo] Neither 'ip' nor 'ifconfig' found"
        echo "{\"error\": \"No network tools available\"}"
        return 1
    fi
}

# ============================================================================
# Helper: Collect using 'ip addr' command
# ============================================================================
_collect_ips_with_ip() {
    local lssn="$1"
    local python_cmd="$2"
    
    LC_ALL=en_US.UTF-8 ip addr show 2>/dev/null | $python_cmd -c "
import sys, json, re

interfaces = []
current_iface = None

for line in sys.stdin:
    line = line.strip()
    
    # Interface line: '2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...'
    if re.match(r'^\d+:', line):
        parts = line.split(':', 2)
        if len(parts) >= 2:
            iface_name = parts[1].strip()
            # Skip loopback
            if iface_name == 'lo':
                current_iface = None
                continue
            
            # Detect status (UP/DOWN)
            status = 'UP' if 'UP' in line else 'DOWN'
            
            current_iface = {
                'name': iface_name,
                'status': status,
                'ipv4': None,
                'ipv6': None,
                'mac': None
            }
            interfaces.append(current_iface)
    
    # IPv4: 'inet 192.168.1.100/24 ...'
    elif current_iface and line.startswith('inet '):
        match = re.search(r'inet\s+([0-9.]+)', line)
        if match:
            current_iface['ipv4'] = match.group(1)
    
    # IPv6: 'inet6 fe80::1/64 ...'
    elif current_iface and line.startswith('inet6 '):
        match = re.search(r'inet6\s+([0-9a-fA-F:]+)', line)
        if match:
            ipv6_addr = match.group(1)
            # Skip link-local if already has global IPv6
            if not current_iface['ipv6'] or not ipv6_addr.startswith('fe80'):
                current_iface['ipv6'] = ipv6_addr
    
    # MAC: 'link/ether 00:0c:29:xx:xx:xx ...'
    elif current_iface and 'link/ether' in line:
        match = re.search(r'link/ether\s+([0-9a-fA-F:]+)', line)
        if match:
            current_iface['mac'] = match.group(1)

# Build result
result = {
    'lssn': int('$lssn'),
    'hostname': '$(hostname)',
    'timestamp': '$(date +%s)',
    'interfaces': interfaces,
    'source': 'ip'
}

print(json.dumps(result))
" 2>/dev/null || echo "{\"error\": \"Failed to parse ip output\"}"
}

# ============================================================================
# Helper: Collect using 'ifconfig' command
# ============================================================================
_collect_ips_with_ifconfig() {
    local lssn="$1"
    local python_cmd="$2"
    
    LC_ALL=en_US.UTF-8 ifconfig 2>/dev/null | $python_cmd -c "
import sys, json, re

interfaces = []
current_iface = None

for line in sys.stdin:
    line = line.rstrip()
    
    # Interface line: 'eth0: flags=...' or 'eth0     Link encap:...'
    if not line.startswith(' ') and not line.startswith('\t'):
        parts = line.split(':')[0].split()
        if parts:
            iface_name = parts[0]
            # Skip loopback
            if iface_name == 'lo':
                current_iface = None
                continue
            
            # Detect status
            status = 'UP' if 'UP' in line or 'RUNNING' in line else 'DOWN'
            
            current_iface = {
                'name': iface_name,
                'status': status,
                'ipv4': None,
                'ipv6': None,
                'mac': None
            }
            interfaces.append(current_iface)
    
    # IPv4: 'inet addr:192.168.1.100' or 'inet 192.168.1.100'
    elif current_iface:
        # RHEL/CentOS format
        match = re.search(r'inet addr:([0-9.]+)', line)
        if not match:
            # Debian/Ubuntu format
            match = re.search(r'inet\s+([0-9.]+)', line)
        if match:
            current_iface['ipv4'] = match.group(1)
        
        # IPv6: 'inet6 addr: fe80::1/64' or 'inet6 fe80::1'
        match = re.search(r'inet6\s+(?:addr:)?\s*([0-9a-fA-F:]+)', line)
        if match:
            ipv6_addr = match.group(1)
            if not current_iface['ipv6'] or not ipv6_addr.startswith('fe80'):
                current_iface['ipv6'] = ipv6_addr
        
        # MAC: 'HWaddr 00:0c:29:xx:xx:xx' or 'ether 00:0c:29:xx:xx:xx'
        match = re.search(r'(?:HWaddr|ether)\s+([0-9a-fA-F:]+)', line)
        if match:
            current_iface['mac'] = match.group(1)

# Build result
result = {
    'lssn': int('$lssn'),
    'hostname': '$(hostname)',
    'timestamp': '$(date +%s)',
    'interfaces': interfaces,
    'source': 'ifconfig'
}

print(json.dumps(result))
" 2>/dev/null || echo "{\"error\": \"Failed to parse ifconfig output\"}"
}

# Export function for external use
export -f collect_server_ips
