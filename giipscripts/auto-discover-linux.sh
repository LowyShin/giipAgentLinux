#!/bin/bash
# Auto-Discovery Script for Linux
# Collects OS, Hardware, Software, Services, Network information
# Output: JSON format

# Function to escape JSON strings
json_escape() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g'
}

# ========================================
# 1. OS Information
# ========================================
if [ -f /etc/os-release ]; then
    . /etc/os-release
    os_name="$NAME"
    os_version="$VERSION"
else
    os_name=$(uname -s)
    os_version=$(uname -r)
fi

# ========================================
# 2. CPU Information
# ========================================
if command -v lscpu &> /dev/null; then
    cpu_model=$(lscpu | grep "Model name:" | sed 's/Model name:\s*//')
    cpu_cores=$(lscpu | grep "^CPU(s):" | awk '{print $2}')
else
    cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    cpu_cores=$(grep -c "^processor" /proc/cpuinfo)
fi

# ========================================
# 3. Memory Information
# ========================================
memory_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
memory_gb=$((memory_total_kb / 1024 / 1024))

# ========================================
# 4. Hostname
# ========================================
hostname=$(hostname)

# ========================================
# 5. Network Interfaces (OS-aware collection)
# ========================================
network_json=""

# Detect OS distribution for network collection strategy
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="$ID"
else
    OS_ID="unknown"
fi

# Modern Linux (Ubuntu 16.04+, CentOS 7+, Debian 8+)
if command -v ip &> /dev/null; then
    # Use 'ip' command (iproute2 package)
    while IFS= read -r iface_name; do
        # Get IPv4 (space after 'inet' is important!)
        ipv4=$(ip -4 addr show "$iface_name" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
        
        # Get IPv6 (global scope only)
        ipv6=$(ip -6 addr show "$iface_name" 2>/dev/null | grep "inet6" | grep -v "scope link" | awk '{print $2}' | cut -d/ -f1 | head -1)
        
        # Get MAC address
        mac=$(ip link show "$iface_name" 2>/dev/null | grep "link/ether" | awk '{print $2}')
        
        # Only add if has IP address
        if [ -n "$ipv4" ] || [ -n "$ipv6" ]; then
            [ -n "$network_json" ] && network_json+=","
            network_json+="{\"name\":\"$iface_name\""
            [ -n "$ipv4" ] && network_json+=",\"ipv4\":\"$ipv4\""
            [ -n "$ipv6" ] && network_json+=",\"ipv6\":\"$ipv6\""
            [ -n "$mac" ] && network_json+=",\"mac\":\"$mac\""
            network_json+="}"
        fi
    done < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -v "^lo$")
    
# Legacy Linux (CentOS 6, RHEL 6, older distributions)
elif command -v ifconfig &> /dev/null; then
    # Use ifconfig (net-tools package)
    case "$OS_ID" in
        centos|rhel|fedora)
            # RHEL/CentOS ifconfig format: "inet addr:192.168.1.1"
            while IFS= read -r iface_name; do
                [ -z "$iface_name" ] && continue
                
                iface_info=$(ifconfig "$iface_name" 2>/dev/null)
                ipv4=$(echo "$iface_info" | grep "inet " | awk '{print $2}' | sed 's/addr://')
                ipv6=$(echo "$iface_info" | grep "inet6 " | awk '{print $3}' | cut -d/ -f1)
                mac=$(echo "$iface_info" | grep "ether" | awk '{print $2}')
                
                if [ -n "$ipv4" ] || [ -n "$ipv6" ]; then
                    [ -n "$network_json" ] && network_json+=","
                    network_json+="{\"name\":\"$iface_name\""
                    [ -n "$ipv4" ] && network_json+=",\"ipv4\":\"$ipv4\""
                    [ -n "$ipv6" ] && network_json+=",\"ipv6\":\"$ipv6\""
                    [ -n "$mac" ] && network_json+=",\"mac\":\"$mac\""
                    network_json+="}"
                fi
            done < <(ifconfig -s 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v "^lo$")
            ;;
        *)
            # Debian/Ubuntu ifconfig format: "inet 192.168.1.1"
            while IFS= read -r iface_name; do
                [ -z "$iface_name" ] && continue
                
                iface_info=$(ifconfig "$iface_name" 2>/dev/null)
                ipv4=$(echo "$iface_info" | grep "inet " | awk '{print $2}')
                ipv6=$(echo "$iface_info" | grep "inet6 " | awk '{print $2}' | cut -d/ -f1)
                mac=$(echo "$iface_info" | grep "ether" | awk '{print $2}')
                
                if [ -n "$ipv4" ] || [ -n "$ipv6" ]; then
                    [ -n "$network_json" ] && network_json+=","
                    network_json+="{\"name\":\"$iface_name\""
                    [ -n "$ipv4" ] && network_json+=",\"ipv4\":\"$ipv4\""
                    [ -n "$ipv6" ] && network_json+=",\"ipv6\":\"$ipv6\""
                    [ -n "$mac" ] && network_json+=",\"mac\":\"$mac\""
                    network_json+="}"
                fi
            done < <(ifconfig -s 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v "^lo$")
            ;;
    esac
    
# Ultimate fallback: /sys/class/net (works on all Linux)
else
    for iface_path in /sys/class/net/*; do
        [ ! -d "$iface_path" ] && continue
        
        iface_name=$(basename "$iface_path")
        [ "$iface_name" = "lo" ] && continue
        
        # Get MAC from sysfs
        if [ -f "$iface_path/address" ]; then
            mac=$(cat "$iface_path/address" 2>/dev/null)
        else
            mac=""
        fi
        
        # Try to get IP from /proc/net/fib_trie (kernel routing table)
        # This is a last resort and may not always work
        ipv4=$(grep -A 2 "$iface_name" /proc/net/fib_trie 2>/dev/null | grep "host LOCAL" | awk '{print $2}' | head -1)
        
        if [ -n "$ipv4" ] || [ -n "$mac" ]; then
            [ -n "$network_json" ] && network_json+=","
            network_json+="{\"name\":\"$iface_name\""
            [ -n "$ipv4" ] && network_json+=",\"ipv4\":\"$ipv4\""
            [ -n "$mac" ] && network_json+=",\"mac\":\"$mac\""
            network_json+="}"
        fi
    done
fi

# ========================================
# 6. Software Inventory (Service-related only)
# ========================================
# Filter: 주요 서비스 관련 패키지만 수집 (백업/감시/웹/DB/미들웨어)
SERVICE_FILTER='nginx|httpd|apache|mysql|mariadb|postgresql|postgres|redis|memcache|mongodb|elastic|kafka|rabbitmq|haproxy|varnish|tomcat|jboss|wildfly|weblogic|glassfish|nodejs|node-|php|python3|java-|openjdk|bacula|amanda|rsync|rclone|borg|duplicity|restic|nagios|zabbix|prometheus|grafana|sensu|icinga|monit|collectd|telegraf|datadog|newrelic|splunk|logstash|filebeat|fluentd|syslog|docker|kubernetes|openshift|ansible|puppet|chef|salt|terraform|jenkins|gitlab|nexus|artifactory|sonarqube|vault|consul|etcd'

software_json=""
count=0

if command -v rpm &> /dev/null; then
    # RPM-based (CentOS, RHEL, Fedora)
    while IFS='|' read -r name version vendor; do
        [ -n "$software_json" ] && software_json+=","
        name_escaped=$(json_escape "$name")
        version_escaped=$(json_escape "$version")
        vendor_escaped=$(json_escape "$vendor")
        software_json+="{\"name\":\"$name_escaped\",\"version\":\"$version_escaped\",\"vendor\":\"$vendor_escaped\",\"type\":\"RPM\"}"
        ((count++))
    done < <(rpm -qa --queryformat '%{NAME}|%{VERSION}-%{RELEASE}|%{VENDOR}\n' 2>/dev/null | grep -iE "$SERVICE_FILTER")
    
elif command -v dpkg &> /dev/null; then
    # DEB-based (Ubuntu, Debian)
    while IFS='|' read -r name version; do
        [ -n "$software_json" ] && software_json+=","
        name_escaped=$(json_escape "$name")
        version_escaped=$(json_escape "$version")
        software_json+="{\"name\":\"$name_escaped\",\"version\":\"$version_escaped\",\"type\":\"DEB\"}"
        ((count++))
    done < <(dpkg-query -W -f='${Package}|${Version}\n' 2>/dev/null | grep -iE "$SERVICE_FILTER")
fi

# ========================================
# 7. Service Status
# ========================================
services_json=""
count=0
max_services=50  # Limit to prevent huge JSON

if command -v systemctl &> /dev/null; then
    # systemd-based
    while IFS='|' read -r name status; do
        [ $count -ge $max_services ] && break
        [ -n "$services_json" ] && services_json+=","
        
        # Get more details
        start_type="Auto"
        if systemctl is-enabled "$name" 2>/dev/null | grep -q "disabled"; then
            start_type="Disabled"
        fi
        
        # Try to get port (common services)
        port=""
        case "$name" in
            *nginx*|*httpd*|*apache*) port="80" ;;
            *mysql*|*mariadb*) port="3306" ;;
            *postgres*) port="5432" ;;
            *redis*) port="6379" ;;
            *ssh*) port="22" ;;
        esac
        
        services_json+="{\"name\":\"$name\",\"status\":\"$status\",\"start_type\":\"$start_type\""
        [ -n "$port" ] && services_json+=",\"port\":$port"
        services_json+="}"
        ((count++))
    done < <(systemctl list-units --type=service --all --no-pager --no-legend | \
             awk '{print $1"|"$4}' | sed 's/.service|/|/' | head -n $max_services)
    
elif command -v service &> /dev/null; then
    # SysV init
    while read -r name; do
        [ $count -ge $max_services ] && break
        status="Unknown"
        if service "$name" status &>/dev/null; then
            status="Running"
        else
            status="Stopped"
        fi
        [ -n "$services_json" ] && services_json+=","
        services_json+="{\"name\":\"$name\",\"status\":\"$status\"}"
        ((count++))
    done < <(service --status-all 2>/dev/null | grep -E '^\s*\[' | awk '{print $4}' | head -n $max_services)
fi

# ========================================
# Disk Information
# ========================================
disk_total_gb=$(df -BG / | tail -1 | awk '{print $2}' | sed 's/G//')

# ========================================
# IP Addresses (Global/Local)
# ========================================
ipv4_global=""
ipv4_local=""

# Try to get first non-loopback IPv4
while IFS= read -r ip; do
    if [[ $ip =~ ^10\. ]] || [[ $ip =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || [[ $ip =~ ^192\.168\. ]]; then
        [ -z "$ipv4_local" ] && ipv4_local="$ip"
    else
        [ -z "$ipv4_global" ] && ipv4_global="$ip"
    fi
done < <(ip -4 addr show | grep inet | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1)

# Fallback: if no global IP, use local as global
[ -z "$ipv4_global" ] && ipv4_global="$ipv4_local"

# ========================================
# Agent Version
# ========================================
agent_version="1.80"

# ========================================
# Generate Final JSON
# ========================================
cat <<EOF
{
  "hostname": "$hostname",
  "os": "$os_name $os_version",
  "cpu": "$cpu_model",
  "cpu_cores": $cpu_cores,
  "memory_gb": $memory_gb,
  "disk_gb": $disk_total_gb,
  "agent_version": "$agent_version",
  "ipv4_global": "$ipv4_global",
  "ipv4_local": "$ipv4_local",
  "network": [$network_json],
  "software": [$software_json],
  "services": [$services_json]
}
EOF
