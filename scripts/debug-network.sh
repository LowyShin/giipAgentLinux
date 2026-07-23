#!/bin/bash
# Debug script to test network collection logic

echo "=========================================="
echo "Network Collection Debug"
echo "=========================================="
echo ""

echo "1. Testing 'ip -o link show' command:"
echo "--------------------------------------"
ip -o link show

echo ""
echo "2. Filtering out loopback:"
echo "--------------------------------------"
ip -o link show | grep -v "lo:"

echo ""
echo "3. Extracting interface names:"
echo "--------------------------------------"
ip -o link show | grep -v "lo:" | awk '{print $2}' | tr -d ':'

echo ""
echo "4. Testing eth0 specifically:"
echo "--------------------------------------"
iface="eth0"
echo "Interface: $iface"
echo "  IPv4 command: ip -4 addr show $iface | grep inet"
ip -4 addr show "$iface" 2>/dev/null | grep inet
echo "  IPv4 result:"
ipv4=$(ip -4 addr show "$iface" 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -1)
echo "    ipv4='$ipv4'"

echo "  IPv6 command: ip -6 addr show $iface | grep inet6 | grep -v 'scope link'"
ip -6 addr show "$iface" 2>/dev/null | grep inet6 | grep -v "scope link"
echo "  IPv6 result:"
ipv6=$(ip -6 addr show "$iface" 2>/dev/null | grep inet6 | grep -v "scope link" | awk '{print $2}' | cut -d/ -f1 | head -1)
echo "    ipv6='$ipv6'"

echo "  MAC command: ip link show $iface | grep link/ether"
ip link show "$iface" 2>/dev/null | grep link/ether
echo "  MAC result:"
mac=$(ip link show "$iface" 2>/dev/null | grep link/ether | awk '{print $2}')
echo "    mac='$mac'"

echo ""
echo "5. Simulating network_json generation:"
echo "--------------------------------------"
network_json=""
if command -v ip &> /dev/null; then
    echo "Using 'ip' command..."
    while IFS= read -r line; do
        echo "Processing line: $line"
        iface=$(echo "$line" | awk '{print $2}' | tr -d ':')
        echo "  Interface: $iface"
        
        ipv4=$(ip -4 addr show "$iface" 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -1)
        ipv6=$(ip -6 addr show "$iface" 2>/dev/null | grep inet6 | grep -v "scope link" | awk '{print $2}' | cut -d/ -f1 | head -1)
        mac=$(ip link show "$iface" 2>/dev/null | grep link/ether | awk '{print $2}')
        
        echo "    ipv4='$ipv4'"
        echo "    ipv6='$ipv6'"
        echo "    mac='$mac'"
        
        if [ -n "$ipv4" ] || [ -n "$ipv6" ]; then
            echo "    ✓ Has IP - adding to JSON"
            [ -n "$network_json" ] && network_json+=","
            network_json+="{\"name\":\"$iface\""
            [ -n "$ipv4" ] && network_json+=",\"ipv4\":\"$ipv4\""
            [ -n "$ipv6" ] && network_json+=",\"ipv6\":\"$ipv6\""
            [ -n "$mac" ] && network_json+=",\"mac\":\"$mac\""
            network_json+="}"
        else
            echo "    ✗ No IP - skipping"
        fi
    done < <(ip -o link show | grep -v "lo:" | awk '{print $2}' | tr -d ':')
else
    echo "ERROR: 'ip' command not found!"
fi

echo ""
echo "6. Final network_json:"
echo "--------------------------------------"
echo "network_json='$network_json'"
echo ""
echo "Formatted:"
echo "[$network_json]"
