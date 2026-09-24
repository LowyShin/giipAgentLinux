#!/usr/bin/env python3
"""
Parse 'netstat' command output to JSON for Net3D visualization
Usage: netstat -antp 2>/dev/null | python3 parse_netstat.py <lssn>
"""
import sys
import json

def parse_addr(addr):
    """Extract IP and port from address string"""
    if ':' in addr:
        return addr.rsplit(':', 1)
    return None, None

def main():
    lssn = sys.argv[1] if len(sys.argv) > 1 else "0"
    
    connections = []
    try:
        lines = sys.stdin.readlines()
        for line in lines:
            # Skip headers / non-tcp lines
            if not line.strip().startswith('tcp'):
                continue
            
            parts = line.split()
            # Typical netstat: Proto Recv-Q Send-Q Local Foreign State PID/Program
            if len(parts) < 6:
                continue
            
            proto = parts[0]
            local_part = parts[3]
            remote_part = parts[4]
            state = parts[5]
            
            lip, lport = parse_addr(local_part) or (local_part, '')
            rip, rport = parse_addr(remote_part) or (remote_part, '')
            
            if not lip:
                continue
                
            process_info = ''
            if len(parts) > 6:
                raw_info = ' '.join(parts[6:])
                # Netstat format: 1234/program or -
                if '/' in raw_info:
                    try:
                        process_info = raw_info.split('/', 1)[1].strip()
                    except:
                        process_info = raw_info
                else:
                    process_info = raw_info
                
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
            'lssn': int(lssn),
            'timestamp': ''  # Will be filled by shell
        }))
    except Exception as e:
        print(json.dumps({'connections': [], 'error': str(e)}))
        sys.exit(1)

if __name__ == '__main__':
    main()
