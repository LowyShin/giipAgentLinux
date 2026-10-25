#!/bin/bash
# Auto-Discovery Script for Linux
# Collects OS, Hardware, Software, Services, Network information
# Output: JSON format
# Parameters: $1=LSSN, $2=Hostname, $3=OS (from giipAgent3.sh)

# ============================================================================
# [로깅] Auto-discover 스크립트 시작
# ============================================================================

# 스크립트 시작 타임스탐프
DISCOVER_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
DISCOVER_SCRIPT_PID=$$

# 파라미터 로깅
LSSN="${1:-unknown}"
HOSTNAME_FROM_PARAM="${2:-unknown}"
OS_FROM_PARAM="${3:-unknown}"

# stderr로 로깅 (giipAgent3.sh에서 캡처)
echo "[auto-discover-linux.sh] 🟢 START - PID=$DISCOVER_SCRIPT_PID at $DISCOVER_START_TIME" >&2
echo "[auto-discover-linux.sh] 📋 Parameters: LSSN=$LSSN, Hostname=$HOSTNAME_FROM_PARAM, OS=$OS_FROM_PARAM" >&2

# Function to escape JSON strings
json_escape() {
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g'
}

# ========================================
# 1. OS Information
# ========================================
echo "[auto-discover-linux.sh] 📋 [Step 1] Collecting OS information..." >&2

if [ -f /etc/os-release ]; then
    . /etc/os-release
    os_name="$NAME"
    os_version="$VERSION"
else
    os_name=$(uname -s)
    os_version=$(uname -r)
fi

echo "[auto-discover-linux.sh] ✅ [Step 1] OS: $os_name $os_version" >&2

# ========================================
# 2. CPU Information
# ========================================
echo "[auto-discover-linux.sh] 📋 [Step 2] Collecting CPU information..." >&2

if command -v lscpu &> /dev/null; then
    cpu_model=$(lscpu | grep "Model name:" | sed 's/Model name:\s*//')
    cpu_cores=$(lscpu | grep "^CPU(s):" | awk '{print $2}')
else
    cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    cpu_cores=$(grep -c "^processor" /proc/cpuinfo)
fi

echo "[auto-discover-linux.sh] ✅ [Step 2] CPU: $cpu_model ($cpu_cores cores)" >&2

# ========================================
# 3. Memory Information
# ========================================
echo "[auto-discover-linux.sh] 📋 [Step 3] Collecting Memory information..." >&2

memory_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
memory_gb=$((memory_total_kb / 1024 / 1024))

echo "[auto-discover-linux.sh] ✅ [Step 3] Memory: ${memory_gb}GB" >&2

# ========================================
# 4. Hostname
# ========================================
echo "[auto-discover-linux.sh] 📋 [Step 4] Collecting Hostname..." >&2

hostname=$(hostname)

echo "[auto-discover-linux.sh] ✅ [Step 4] Hostname: $hostname" >&2

# ========================================
# 5. Network Interfaces (OS-aware collection)
# ========================================
echo "[auto-discover-linux.sh] 📋 [Step 5] Collecting Network interfaces..." >&2

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

# Echo-first public IP (giip 3559): NAT'd hosts (e.g. cctrank03) only have a private
# NIC IP, so the NIC scan above records the private IP as the global IP. Ask an
# external echo endpoint for the true public IP first; fall back to the NIC-derived
# value (then local) when offline/locked-down or curl is missing. Never regress.
is_valid_ipv4() {
    local v="$1"
    [[ $v =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS='.'; local -a o=($v)
    for n in "${o[@]}"; do
        [ "$n" -le 255 ] 2>/dev/null || return 1
    done
    return 0
}

if command -v curl &> /dev/null; then
    for echo_url in "https://api.ipify.org" "https://ifconfig.me/ip" "https://checkip.amazonaws.com"; do
        echo_ip=$(curl -s --connect-timeout 3 --max-time 3 "$echo_url" 2>/dev/null | tr -d '[:space:]')
        if is_valid_ipv4 "$echo_ip"; then
            ipv4_global="$echo_ip"
            echo "[auto-discover-linux.sh] 🌐 [Network] Public IP resolved via echo ($echo_url): $ipv4_global" >&2
            break
        fi
    done
fi

# Fallback: if no global IP (echo failed and no public NIC IP), use local as global
[ -z "$ipv4_global" ] && ipv4_global="$ipv4_local"

# ========================================
# Agent Version
# ========================================
agent_version="1.80"

# ========================================
# [로깅] Generate Final JSON
# ========================================
echo "[auto-discover-linux.sh] 📋 [Step Final] Generating JSON output..." >&2
echo "[auto-discover-linux.sh] 📊 [Statistics] OS: $os_name $os_version | CPU: $cpu_cores cores | Memory: ${memory_gb}GB | Hostname: $hostname" >&2
echo "[auto-discover-linux.sh] 🌐 [Network] IPv4_Local: $ipv4_local | IPv4_Global: $ipv4_global" >&2

# JSON 크기 예측 (로깅용)
network_count=$(echo "[$network_json]" | tr ',' '\n' | wc -l)
software_count=$(echo "[$software_json]" | tr ',' '\n' | wc -l)
services_count=$(echo "[$services_json]" | tr ',' '\n' | wc -l)

echo "[auto-discover-linux.sh] 📦 [Inventory] Networks: ~$network_count | Software: ~$software_count | Services: ~$services_count" >&2

# JSON 생성 시작
echo "[auto-discover-linux.sh] ⏱️  Generating JSON..." >&2

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

# JSON 생성 완료
DISCOVER_END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
echo "[auto-discover-linux.sh] ✅ COMPLETED at $DISCOVER_END_TIME (PID=$DISCOVER_SCRIPT_PID)" >&2
echo "[auto-discover-linux.sh] 🕒 Total execution time: from $DISCOVER_START_TIME to $DISCOVER_END_TIME" >&2

