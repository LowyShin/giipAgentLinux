#!/bin/bash
# lib/server_info.sh - Server IP Information Collection Module
# Version: 1.0
# Date: 2025-12-27
# Purpose: Collect server's own network interface IP addresses
# Usage: source lib/server_info.sh && collect_server_ips <lssn>

# UTF-8 환경 설정 (필수!)
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# giip #1551 (cctrank03/lssn 71174 실측): cron/CQE로 실행되는 giipAgent3.sh 프로세스의
# PATH에는 /usr/sbin, /sbin이 빠져있어(대화형 로그인 셸에만 포함되는 경우가 많음) `ip`/
# `ifconfig`가 command -v로 전혀 안 잡히고 collect_server_ips()가 매번
# "No network tools available" 에러로 조용히 실패했다(2026-08-08 수동 테스트 3건 이후
# 무한 스킵, tKVS server_ips factor 실측으로 확인). ip/ifconfig 바이너리가 있는 표준
# 경로를 PATH 앞에 추가해 방어한다.
export PATH="/usr/sbin:/sbin:/usr/local/sbin:${PATH}"

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

    # giip #3559: NAT 뒤의 호스트는 로컬 인터페이스 열거만으로는 공인 IP 를 알 수 없다.
    # 공인 IP 를 한 번만 조회해 아래 두 수집 경로의 결과 JSON 에 public_ip 필드로 실어 보낸다.
    local public_ip=$(collect_public_ip)

    # Try 'ip addr' first (modern, preferred)
    if command -v ip >/dev/null 2>&1; then
        _collect_ips_with_ip "$lssn" "$python_cmd" "$public_ip"
    elif command -v ifconfig >/dev/null 2>&1; then
        _collect_ips_with_ifconfig "$lssn" "$python_cmd" "$public_ip"
    else
        log_message "ERROR" "[ServerInfo] Neither 'ip' nor 'ifconfig' found"
        echo "{\"error\": \"No network tools available\"}"
        return 1
    fi
}

# ============================================================================
# Public IP Collection (giip #3559)
# ============================================================================
# NAT 뒤의 호스트는 로컬 인터페이스 열거만으로 공인 IP 를 알 수 없다. 공인 IP 는
# "외부에서 본 주소"이므로 외부 반사 서비스로 조회한다. 수집 우선순위:
#   1) GIIP_PUBLIC_IP 설정값 — 수동 지정(네트워크 의존 없음, 오프라인·프라이버시 환경·고정 IP).
#   2) 외부 반사 서비스 폴백 체인(각 5초 타임아웃). 첫 유효 IPv4 를 채택.
#   3) 전부 실패하면 빈 문자열을 반환한다 — 호출부가 public_ip 를 null 로 기록하고
#      조용히 넘어간다(공인 IP 미확인이 수집 전체를 중단시키지 않게 한다).
# Returns: 공인 IPv4 문자열(실패 시 빈 문자열). stdout 으로만 값을 낸다.
collect_public_ip() {
    # 1) 수동 지정값 우선 — 네트워크 호출 없이 바로 사용
    if [[ -n "${GIIP_PUBLIC_IP:-}" ]]; then
        echo "${GIIP_PUBLIC_IP}"
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
        log_message "WARN" "[ServerInfo] curl not found; public IP lookup skipped"
        echo ""
        return 0
    fi

    # 2) 외부 반사 서비스 폴백 체인
    local providers=("https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com")
    local url ip
    for url in "${providers[@]}"; do
        ip=$(curl -fsS --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]')
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log_message "INFO" "[ServerInfo] Public IP resolved via ${url}"
            echo "$ip"
            return 0
        fi
    done

    # 3) 전부 실패 — 조용히 null 처리
    log_message "WARN" "[ServerInfo] Public IP lookup failed on all providers"
    echo ""
    return 0
}

# ============================================================================
# Helper: Collect using 'ip addr' command
# ============================================================================
_collect_ips_with_ip() {
    local lssn="$1"
    local python_cmd="$2"
    local public_ip="$3"

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
    'public_ip': '$public_ip' or None,
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
    local public_ip="$3"

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
    'public_ip': '$public_ip' or None,
    'source': 'ifconfig'
}

print(json.dumps(result))
" 2>/dev/null || echo "{\"error\": \"Failed to parse ifconfig output\"}"
}

# Export function for external use
export -f collect_server_ips
export -f collect_public_ip
