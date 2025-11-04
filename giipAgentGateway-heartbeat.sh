#!/bin/bash
# giipAgentGateway Heartbeat - Ver. 1.0
# Gateway Agent for collecting server information via SSH
# This script connects to remote servers, collects system info, and updates DB
# Written by Lowy Shin at 2025-11-04

sv="1.0"

# Load configuration
config_file=""
if [ -f "./giipAgent.cnf" ]; then
    config_file="./giipAgent.cnf"
elif [ -f "../giipAgent.cnf" ]; then
    config_file="../giipAgent.cnf"
elif [ -f "./giipAgentGateway.cnf" ]; then
    config_file="./giipAgentGateway.cnf"
else
    echo "Error: Configuration file not found (giipAgent.cnf or giipAgentGateway.cnf)"
    exit 1
fi

echo "Loading configuration from: $config_file"
. $config_file

# Get Gateway server's own LSSN from config
if [ -z "$lssn" ]; then
    echo "Error: lssn not configured in $config_file"
    exit 1
fi

gateway_lssn="$lssn"

# Get CSN from config (if not set, try to get from API)
if [ -z "$csn" ]; then
    echo "Warning: csn not configured, will try to detect from API"
fi

# API configuration
if [ -z "$apiaddrv2" ]; then
    apiaddrv2="https://giipfaw.azurewebsites.net/api/giipApiSk2"
fi

if [ -z "$sk" ]; then
    echo "Error: sk (secret key) not configured in $config_file"
    exit 1
fi

# Check required tools
for cmd in ssh sshpass curl jq; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is not installed"
        echo "Please install: $cmd"
        # Don't exit, just warn - giipAgent.sh will handle sshpass installation
        if [ "$cmd" != "sshpass" ]; then
            exit 1
        fi
    fi
done

# Get Gateway server's own LSSN
if [ -z "$gateway_lssn" ]; then
    echo "Error: gateway_lssn (lssn) not found in configuration"
    exit 1
fi

logdt=`date '+%Y%m%d%H%M%S'`
Today=`date '+%Y%m%d'`

# Create log directory in script location
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOG_DIR="${SCRIPT_DIR}/log"
mkdir -p "$LOG_DIR"

LogFileName="${LOG_DIR}/giipAgentGateway_heartbeat_$Today.log"
tmpDir="/tmp/giipGatewayHeartbeat_$$"
mkdir -p $tmpDir

echo "[$logdt] Gateway Heartbeat Started (v${sv}) - Gateway LSSN: $gateway_lssn" >> $LogFileName

# Function: Get managed server list from DB via API
get_managed_servers() {
    local api_url="${apiaddrv2}?code=${apiaddrcode}"
    local response_file="${tmpDir}/managed_servers.json"
    
    echo "[$logdt] Fetching managed server list from API..." >> $LogFileName
    
    curl -s -X POST "$api_url" \
        -H "Content-Type: application/json" \
        -d "{
            \"text\": \"GatewayRemoteServerList\",
            \"token\": \"$sk\",
            \"csn\": ${csn:-0},
            \"gateway_lssn\": $gateway_lssn
        }" > "$response_file"
    
    if [ ! -s "$response_file" ]; then
        echo "[$logdt] Error: Empty response from API" >> $LogFileName
        return 1
    fi
    
    # Check if response contains error
    local rst_val=$(jq -r '.[0].RstVal // empty' "$response_file" 2>/dev/null)
    if [ "$rst_val" != "200" ] && [ ! -z "$rst_val" ]; then
        local rst_msg=$(jq -r '.[0].RstMsg // "Unknown error"' "$response_file" 2>/dev/null)
        echo "[$logdt] API Error: $rst_msg" >> $LogFileName
        return 1
    fi
    
    echo "$response_file"
}

# Function: Collect server info via SSH
collect_server_info() {
    local ssh_host=$1
    local ssh_user=$2
    local ssh_port=$3
    local ssh_key=$4
    local ssh_password=$5
    local hostname=$6
    
    local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
    local info_script="${tmpDir}/collect_info.sh"
    
    # Create info collection script
    cat > "$info_script" << 'EOFSCRIPT'
#!/bin/bash
# Collect server information in JSON format

# Hostname
HOSTNAME=$(hostname -f 2>/dev/null || hostname)

# OS Info
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME="$NAME"
    OS_VERSION="$VERSION_ID"
elif [ -f /etc/redhat-release ]; then
    OS_NAME=$(cat /etc/redhat-release)
    OS_VERSION=""
else
    OS_NAME=$(uname -s)
    OS_VERSION=$(uname -r)
fi

# Memory (GB)
MEM_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_GB=$(awk "BEGIN {printf \"%.1f\", $MEM_TOTAL_KB / 1024 / 1024}")

# Disk (GB) - Root partition
DISK_TOTAL=$(df -BG / | tail -1 | awk '{print $2}' | sed 's/G//')
DISK_USED=$(df -BG / | tail -1 | awk '{print $3}' | sed 's/G//')

# CPU Info
CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
CPU_CORES=$(grep -c ^processor /proc/cpuinfo)

# Network - Primary IP
PRIMARY_IP=$(ip route get 1 2>/dev/null | grep -oP 'src \K\S+' || hostname -I | awk '{print $1}')

# Output JSON
cat << EOF
{
    "hostname": "$HOSTNAME",
    "os_name": "$OS_NAME",
    "os_version": "$OS_VERSION",
    "memory_gb": $MEM_GB,
    "disk_total_gb": $DISK_TOTAL,
    "disk_used_gb": $DISK_USED,
    "cpu_model": "$CPU_MODEL",
    "cpu_cores": $CPU_CORES,
    "ipv4_global": "$PRIMARY_IP",
    "agent_ver": "gateway-collected-$sv",
    "collected_at": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF
EOFSCRIPT
    
    chmod +x "$info_script"
    
    # Execute via SSH
    local result=""
    if [ -n "$ssh_password" ]; then
        # Password authentication
        result=$(sshpass -p "$ssh_password" ssh $ssh_opts -p $ssh_port ${ssh_user}@${ssh_host} 'bash -s' < "$info_script" 2>/dev/null)
    elif [ -n "$ssh_key" ] && [ -f "$ssh_key" ]; then
        # Key authentication
        result=$(ssh $ssh_opts -i "$ssh_key" -p $ssh_port ${ssh_user}@${ssh_host} 'bash -s' < "$info_script" 2>/dev/null)
    else
        # Default authentication
        result=$(ssh $ssh_opts -p $ssh_port ${ssh_user}@${ssh_host} 'bash -s' < "$info_script" 2>/dev/null)
    fi
    
    if [ $? -eq 0 ] && [ ! -z "$result" ]; then
        echo "$result"
        return 0
    else
        echo "[$logdt]   → SSH connection failed: ${ssh_user}@${ssh_host}:${ssh_port}" >> $LogFileName
        return 1
    fi
}

# Function: Update server info via API
update_server_info() {
    local lssn=$1
    local hostname=$2
    local json_data=$3
    
    local api_url="${apiaddrv2}?code=${apiaddrcode}"
    local response_file="${tmpDir}/update_response_${lssn}.json"
    
    # Prepare JSON payload
    local payload=$(jq -n \
        --arg text "AgentAutoRegister" \
        --arg token "$sk" \
        --arg hostname "$hostname" \
        --argjson jsondata "$json_data" \
        '{text: $text, token: $token, hostname: $hostname, jsondata: $jsondata}')
    
    echo "[$logdt]   → Updating DB via API..." >> $LogFileName
    
    curl -s -X POST "$api_url" \
        -H "Content-Type: application/json" \
        -d "$payload" > "$response_file"
    
    local rst_val=$(jq -r '.RstVal // empty' "$response_file" 2>/dev/null)
    
    if [ "$rst_val" == "200" ]; then
        echo "[$logdt]   → ✅ Update successful" >> $LogFileName
        return 0
    else
        local rst_msg=$(jq -r '.RstMsg // "Unknown error"' "$response_file" 2>/dev/null)
        echo "[$logdt]   → ❌ Update failed: $rst_msg" >> $LogFileName
        return 1
    fi
}

# Main processing function
process_managed_servers() {
    local server_list_file=$(get_managed_servers)
    
    if [ $? -ne 0 ] || [ ! -f "$server_list_file" ]; then
        echo "[$logdt] Failed to get managed server list" >> $LogFileName
        return 1
    fi
    
    local server_count=$(jq 'length' "$server_list_file" 2>/dev/null)
    echo "[$logdt] Found $server_count managed servers" >> $LogFileName
    
    # Process each server
    local index=0
    while [ $index -lt $server_count ]; do
        local server=$(jq ".[$index]" "$server_list_file")
        
        # Extract server details (case-insensitive)
        local lssn=$(echo "$server" | jq -r '.LSSN // .lssn // empty')
        local hostname=$(echo "$server" | jq -r '.LSHostname // .lshostname // empty')
        local ssh_host=$(echo "$server" | jq -r '.gateway_ssh_host // .gatewaysshhost // empty')
        local ssh_user=$(echo "$server" | jq -r '.gateway_ssh_user // .gatewaysshuser // "root"')
        local ssh_port=$(echo "$server" | jq -r '.gateway_ssh_port // .gatewaysshport // "22"')
        local ssh_key=$(echo "$server" | jq -r '.gateway_ssh_key_path // .gatewaysskeypath // empty')
        local ssh_password=$(echo "$server" | jq -r '.gateway_ssh_password // .gatewaysshpassword // empty')
        
        if [ -z "$lssn" ] || [ -z "$ssh_host" ]; then
            echo "[$logdt] ⚠️  Skipping invalid server entry" >> $LogFileName
            index=$((index + 1))
            continue
        fi
        
        logdt=`date '+%Y%m%d%H%M%S'`
        echo "[$logdt] Processing: $hostname (LSSN: $lssn) → ${ssh_user}@${ssh_host}:${ssh_port}" >> $LogFileName
        
        # Collect server info
        local server_info=$(collect_server_info "$ssh_host" "$ssh_user" "$ssh_port" "$ssh_key" "$ssh_password" "$hostname")
        
        if [ $? -eq 0 ] && [ ! -z "$server_info" ]; then
            echo "[$logdt]   → ✅ Info collected successfully" >> $LogFileName
            
            # Update DB
            update_server_info "$lssn" "$hostname" "$server_info"
        else
            echo "[$logdt]   → ❌ Failed to collect info" >> $LogFileName
        fi
        
        index=$((index + 1))
        
        # Small delay between servers
        sleep 2
    done
}

# Main execution
echo "[$logdt] ========================================" >> $LogFileName
echo "[$logdt] Starting heartbeat cycle..." >> $LogFileName

process_managed_servers

logdt=`date '+%Y%m%d%H%M%S'`
echo "[$logdt] Heartbeat cycle completed" >> $LogFileName
echo "[$logdt] ========================================" >> $LogFileName

# Cleanup
rm -rf $tmpDir

exit 0
