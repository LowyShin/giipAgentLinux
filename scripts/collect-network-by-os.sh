#!/bin/bash
#
# collect-network-by-os.sh
# OS distribution별 네트워크 정보 수집 및 KVS 업로드
#
# Usage: ./collect-network-by-os.sh
# Output: 
#   - /tmp/network-info.json (collected data)
#   - Uploads to KVS with kfactor 'netdiag'
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVSPUT="$SCRIPT_DIR/kvsput.sh"
OUTPUT_JSON="/tmp/network-info.json"

# OS 감지
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
        OS_NAME="$PRETTY_NAME"
    elif [ -f /etc/redhat-release ]; then
        OS_NAME=$(cat /etc/redhat-release)
        OS_ID="rhel"
        OS_VERSION=$(echo "$OS_NAME" | grep -oE '[0-9]+\.[0-9]+' | head -1)
    elif [ -f /etc/debian_version ]; then
        OS_ID="debian"
        OS_VERSION=$(cat /etc/debian_version)
        OS_NAME="Debian $OS_VERSION"
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
        OS_NAME="Unknown Linux"
    fi
    
    echo "[INFO] Detected OS: $OS_NAME (ID: $OS_ID, Version: $OS_VERSION)"
}

# Ubuntu/Debian 계열 (ip 명령 사용)
collect_network_debian() {
    echo "[INFO] Using Debian/Ubuntu network collection method"
    
    local interfaces=()
    
    # ip 명령 사용 (modern)
    if command -v ip &> /dev/null; then
        while IFS= read -r iface; do
            # 인터페이스 이름 추출
            name=$(echo "$iface" | awk '{print $2}' | tr -d ':')
            
            # IPv4 주소
            ipv4=$(ip -4 addr show "$name" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
            
            # IPv6 주소 (link-local 제외)
            ipv6=$(ip -6 addr show "$name" 2>/dev/null | grep "inet6" | grep -v "scope link" | awk '{print $2}' | cut -d/ -f1 | head -1)
            
            # MAC 주소
            mac=$(ip link show "$name" 2>/dev/null | grep "link/ether" | awk '{print $2}')
            
            # 상태
            state=$(ip link show "$name" 2>/dev/null | grep -oP '(?<=state )\w+')
            
            # MTU
            mtu=$(ip link show "$name" 2>/dev/null | grep -oP '(?<=mtu )\d+')
            
            # JSON 객체 생성
            if [ -n "$ipv4" ] || [ -n "$ipv6" ]; then
                interfaces+=("{\"name\":\"$name\",\"ipv4\":\"${ipv4:-null}\",\"ipv6\":\"${ipv6:-null}\",\"mac\":\"${mac:-null}\",\"state\":\"${state:-unknown}\",\"mtu\":${mtu:-1500}}")
            fi
        done < <(ip -o link show | grep -v "lo:")
    fi
    
    # JSON 배열 출력
    local IFS=,
    echo "[${interfaces[*]}]"
}

# CentOS/RHEL 계열 (ifconfig 또는 ip)
collect_network_redhat() {
    echo "[INFO] Using RedHat/CentOS network collection method"
    
    local interfaces=()
    
    # RHEL 7+ : ip 명령 우선
    if command -v ip &> /dev/null; then
        # Debian과 동일한 로직 (ip 명령 표준)
        while IFS= read -r iface; do
            name=$(echo "$iface" | awk '{print $2}' | tr -d ':')
            ipv4=$(ip -4 addr show "$name" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
            ipv6=$(ip -6 addr show "$name" 2>/dev/null | grep "inet6" | grep -v "scope link" | awk '{print $2}' | cut -d/ -f1 | head -1)
            mac=$(ip link show "$name" 2>/dev/null | grep "link/ether" | awk '{print $2}')
            state=$(ip link show "$name" 2>/dev/null | grep -oP '(?<=state )\w+')
            mtu=$(ip link show "$name" 2>/dev/null | grep -oP '(?<=mtu )\d+')
            
            if [ -n "$ipv4" ] || [ -n "$ipv6" ]; then
                interfaces+=("{\"name\":\"$name\",\"ipv4\":\"${ipv4:-null}\",\"ipv6\":\"${ipv6:-null}\",\"mac\":\"${mac:-null}\",\"state\":\"${state:-unknown}\",\"mtu\":${mtu:-1500}}")
            fi
        done < <(ip -o link show | grep -v "lo:")
        
    # RHEL 6 이하 : ifconfig
    elif command -v ifconfig &> /dev/null; then
        while IFS= read -r name; do
            [ -z "$name" ] && continue
            [ "$name" = "lo" ] && continue
            
            # ifconfig 출력 파싱
            iface_info=$(ifconfig "$name" 2>/dev/null)
            
            ipv4=$(echo "$iface_info" | grep "inet " | awk '{print $2}' | sed 's/addr://')
            ipv6=$(echo "$iface_info" | grep "inet6 " | grep -v "Scope:Link" | awk '{print $3}' | cut -d/ -f1)
            mac=$(echo "$iface_info" | grep "ether" | awk '{print $2}')
            
            # 상태 확인
            if echo "$iface_info" | grep -q "UP"; then
                state="UP"
            else
                state="DOWN"
            fi
            
            mtu=$(echo "$iface_info" | grep -oP '(?<=MTU:)\d+')
            
            if [ -n "$ipv4" ] || [ -n "$ipv6" ]; then
                interfaces+=("{\"name\":\"$name\",\"ipv4\":\"${ipv4:-null}\",\"ipv6\":\"${ipv6:-null}\",\"mac\":\"${mac:-null}\",\"state\":\"${state:-unknown}\",\"mtu\":${mtu:-1500}}")
            fi
        done < <(ifconfig -s | tail -n +2 | awk '{print $1}' | grep -v "^lo$")
    fi
    
    local IFS=,
    echo "[${interfaces[*]}]"
}

# Alpine Linux (경량 배포판)
collect_network_alpine() {
    echo "[INFO] Using Alpine Linux network collection method"
    
    local interfaces=()
    
    if command -v ip &> /dev/null; then
        while IFS= read -r iface; do
            name=$(echo "$iface" | awk '{print $2}' | tr -d ':')
            ipv4=$(ip -4 addr show "$name" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
            ipv6=$(ip -6 addr show "$name" 2>/dev/null | grep "inet6" | grep -v "scope link" | awk '{print $2}' | cut -d/ -f1)
            mac=$(ip link show "$name" 2>/dev/null | grep "link/ether" | awk '{print $2}')
            state=$(ip link show "$name" 2>/dev/null | grep -oE '<[^>]+>' | grep -oE 'UP|DOWN')
            
            if [ -n "$ipv4" ] || [ -n "$ipv6" ]; then
                interfaces+=("{\"name\":\"$name\",\"ipv4\":\"${ipv4:-null}\",\"ipv6\":\"${ipv6:-null}\",\"mac\":\"${mac:-null}\",\"state\":\"${state:-unknown}\",\"mtu\":1500}")
            fi
        done < <(ip -o link show | grep -v "lo:")
    fi
    
    local IFS=,
    echo "[${interfaces[*]}]"
}

# 범용 수집 (fallback)
collect_network_generic() {
    echo "[INFO] Using generic network collection method"
    
    local interfaces=()
    
    # /sys/class/net 사용 (모든 Linux에서 동작)
    for iface_path in /sys/class/net/*; do
        [ ! -d "$iface_path" ] && continue
        
        name=$(basename "$iface_path")
        [ "$name" = "lo" ] && continue
        
        # MAC 주소
        if [ -f "$iface_path/address" ]; then
            mac=$(cat "$iface_path/address")
        else
            mac=""
        fi
        
        # IPv4/IPv6는 ip 또는 ifconfig로 가져오기
        if command -v ip &> /dev/null; then
            ipv4=$(ip -4 addr show "$name" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
            ipv6=$(ip -6 addr show "$name" 2>/dev/null | grep "inet6" | grep -v "scope link" | awk '{print $2}' | cut -d/ -f1)
        elif command -v ifconfig &> /dev/null; then
            iface_info=$(ifconfig "$name" 2>/dev/null)
            ipv4=$(echo "$iface_info" | grep "inet " | awk '{print $2}' | sed 's/addr://')
            ipv6=$(echo "$iface_info" | grep "inet6 " | awk '{print $3}' | cut -d/ -f1)
        fi
        
        # 상태 확인
        if [ -f "$iface_path/operstate" ]; then
            state=$(cat "$iface_path/operstate")
        else
            state="unknown"
        fi
        
        if [ -n "$ipv4" ] || [ -n "$ipv6" ]; then
            interfaces+=("{\"name\":\"$name\",\"ipv4\":\"${ipv4:-null}\",\"ipv6\":\"${ipv6:-null}\",\"mac\":\"${mac:-null}\",\"state\":\"${state:-unknown}\",\"mtu\":1500}")
        fi
    done
    
    local IFS=,
    echo "[${interfaces[*]}]"
}

# 메인 로직
main() {
    echo "=========================================="
    echo "Network Collection by OS"
    echo "=========================================="
    
    detect_os
    
    # OS별 수집 메서드 선택
    case "$OS_ID" in
        ubuntu|debian|linuxmint|pop)
            network_data=$(collect_network_debian)
            ;;
        rhel|centos|fedora|rocky|almalinux|ol)
            network_data=$(collect_network_redhat)
            ;;
        alpine)
            network_data=$(collect_network_alpine)
            ;;
        *)
            echo "[WARN] Unknown OS, using generic method"
            network_data=$(collect_network_generic)
            ;;
    esac
    
    # JSON 생성
    cat > "$OUTPUT_JSON" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "os": {
    "id": "$OS_ID",
    "version": "$OS_VERSION",
    "name": "$OS_NAME"
  },
  "network": $network_data
}
EOF
    
    echo ""
    echo "[INFO] Network data collected to: $OUTPUT_JSON"
    echo "[INFO] Preview:"
    cat "$OUTPUT_JSON" | jq . 2>/dev/null || cat "$OUTPUT_JSON"
    
    # KVS 업로드
    if [ -f "$KVSPUT" ]; then
        echo ""
        echo "[INFO] Uploading to KVS with kfactor 'netdiag'..."
        if bash "$KVSPUT" "$OUTPUT_JSON" netdiag; then
            echo "[SUCCESS] Upload completed"
        else
            echo "[ERROR] Upload failed"
            exit 1
        fi
    else
        echo "[WARN] kvsput.sh not found at: $KVSPUT"
        echo "[INFO] To upload manually: bash $KVSPUT $OUTPUT_JSON netdiag"
    fi
}

main "$@"
