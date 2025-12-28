#!/usr/bin/env python3
"""
Parse 'ss' command output to JSON for Net3D visualization
Usage: ss -ntap 2>/dev/null | python3 parse_ss.py <lssn>
"""
import sys
import json
import re

def parse_addr(addr):
    """Extract IP and port from address string"""
    if ']:' in addr:  # IPv6 [::1]:22
        ip, port = addr.rsplit(':', 1)
        ip = ip.strip('[]')
        return ip, port
    elif ':' in addr:  # IPv4 1.2.3.4:22
        ip, port = addr.rsplit(':', 1)
        return ip, port
    return None, None

def main():
    lssn = sys.argv[1] if len(sys.argv) > 1 else "0"
    
    connections = []
    try:
        lines = sys.stdin.readlines()
        for line in lines:
            parts = line.split()
            if len(parts) < 4:
                continue
            
            # Skip header
            if parts[0].strip().lower() == 'state':
                continue
                
            state = parts[0]
            # Filter for relevant states
            if state not in ['ESTABLISHED', 'ESTAB', 'LISTEN', 'TIME_WAIT', 'CLOSE_WAIT', 'SYN_SENT', 'SYN_RECV']:
                continue
                
            # ss columns: State Recv-Q Send-Q Local Peer ...
            local_part = parts[3]
            remote_part = parts[4]
            
            lip, lport = parse_addr(local_part)
            rip, rport = parse_addr(remote_part)
            
            if not lip or not rip:
                continue

            process_info = ''
            if len(parts) > 5:
                raw_info = ' '.join(parts[5:])
                # Extract process name from: users:(("python",pid=123,fd=4))
                m = re.search(r'"([^"]+)"', raw_info)
                if m:
                    process_info = m.group(1)
                else:
                    process_info = raw_info
                
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
            'lssn': int(lssn),
            'timestamp': ''  # Will be filled by shell
        }))
    except Exception as e:
        print(json.dumps({'connections': [], 'error': str(e)}))
        sys.exit(1)

if __name__ == '__main__':
    main()
