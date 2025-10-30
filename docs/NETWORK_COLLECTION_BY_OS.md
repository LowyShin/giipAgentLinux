# Network Collection by OS Distribution

## Problem
Linux distributions have different network tools and command output formats:
- **Modern**: `ip` command (iproute2) - Ubuntu 16.04+, CentOS 7+, Debian 8+
- **Legacy**: `ifconfig` command (net-tools) - CentOS 6, RHEL 6, older systems
- **Output format varies** by distro (especially ifconfig)

## Solution Strategy

### 1. Detection Priority
```
1st: Try 'ip' command (modern, standardized)
2nd: Try 'ifconfig' command (legacy, OS-specific parsing)
3rd: Fallback to /sys/class/net (kernel interface)
```

### 2. Command Differences

#### Modern: `ip` command
```bash
# Interface list (parse field 2 with ':')
ip -o link show
# Output: "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ..."

# Extract interface name
ip -o link show | awk -F': ' '{print $2}'  # ✅ Better than awk '{print $2}' | tr -d ':'

# Get IPv4 (note the space after 'inet')
ip -4 addr show eth0 | grep "inet "  # ← Space prevents matching 'inet6'
# Output: "    inet 10.2.0.5/16 brd 10.2.255.255 scope global eth0"

# Get MAC
ip link show eth0 | grep "link/ether"
# Output: "    link/ether 00:22:48:0e:a4:93 brd ff:ff:ff:ff:ff:ff"
```

**Bug in Original Code**:
```bash
# ❌ WRONG: This extracts "eth0:" (with colon)
ip -o link show | grep -v "lo:" | awk '{print $2}' | tr -d ':'

# ✅ CORRECT: Split by ': ' delimiter
ip -o link show | awk -F': ' '{print $2}' | grep -v "^lo$"
```

#### Legacy: `ifconfig` command

**RHEL/CentOS format** (net-tools 1.x):
```bash
ifconfig eth0
# Output:
# eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
#         inet addr:192.168.1.1  Bcast:192.168.1.255  Mask:255.255.255.0
#         inet6 fe80::a00:27ff:fe4e:66a1/64  Scope:Link
#         ether 08:00:27:4e:66:a1  txqueuelen 1000  (Ethernet)
```
- IPv4: `inet addr:192.168.1.1` (needs `sed 's/addr://'`)

**Debian/Ubuntu format** (net-tools 2.x):
```bash
ifconfig eth0
# Output:
# eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
#         inet 192.168.1.1  netmask 255.255.255.0  broadcast 192.168.1.255
#         inet6 fe80::a00:27ff:fe4e:66a1  prefixlen 64  scopeid 0x20<link>
#         ether 08:00:27:4e:66:a1  txqueuelen 1000  (Ethernet)
```
- IPv4: `inet 192.168.1.1` (no "addr:")

### 3. Implementation

```bash
# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="$ID"  # ubuntu, centos, rhel, debian, etc.
fi

# Method 1: Modern (ip command)
if command -v ip &> /dev/null; then
    while IFS= read -r iface_name; do
        ipv4=$(ip -4 addr show "$iface_name" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
        ipv6=$(ip -6 addr show "$iface_name" 2>/dev/null | grep "inet6" | grep -v "scope link" | awk '{print $2}' | cut -d/ -f1 | head -1)
        mac=$(ip link show "$iface_name" 2>/dev/null | grep "link/ether" | awk '{print $2}')
        
        # Add to JSON...
    done < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -v "^lo$")

# Method 2: Legacy (ifconfig - OS-specific)
elif command -v ifconfig &> /dev/null; then
    case "$OS_ID" in
        centos|rhel|fedora)
            # RHEL format: inet addr:192.168.1.1
            ipv4=$(ifconfig "$iface_name" | grep "inet " | awk '{print $2}' | sed 's/addr://')
            ;;
        *)
            # Debian/Ubuntu format: inet 192.168.1.1
            ipv4=$(ifconfig "$iface_name" | grep "inet " | awk '{print $2}')
            ;;
    esac

# Method 3: Fallback (/sys/class/net)
else
    for iface_path in /sys/class/net/*; do
        iface_name=$(basename "$iface_path")
        [ "$iface_name" = "lo" ] && continue
        
        # MAC from sysfs
        mac=$(cat "$iface_path/address" 2>/dev/null)
        
        # IP from kernel routing table (limited)
        ipv4=$(grep -A 2 "$iface_name" /proc/net/fib_trie 2>/dev/null | grep "host LOCAL" | awk '{print $2}' | head -1)
        
        # Add to JSON...
    done
fi
```

## OS-Specific Commands

### Ubuntu/Debian
```bash
# List interfaces
ip link show
# or
ifconfig -s

# Get IP
ip addr show eth0
# or
ifconfig eth0
```

### CentOS/RHEL 7+
```bash
# Same as Ubuntu (uses iproute2)
ip link show
ip addr show eth0
```

### CentOS/RHEL 6
```bash
# Uses net-tools (ifconfig)
ifconfig -s
ifconfig eth0

# Install iproute if needed
yum install iproute
```

### Alpine Linux
```bash
# Uses ip command (iproute2-ss)
ip link show
ip addr show eth0
```

## Testing Network Collection

### Test Script
Use the provided `collect-network-by-os.sh`:

```bash
cd /opt/giipAgentLinux/giipscripts
bash collect-network-by-os.sh
```

**Output**:
1. Console: Shows detected OS and collection method
2. File: `/tmp/network-info.json` - Collected data
3. KVS: Uploaded with kfactor `netdiag`

### Manual Testing by OS

#### Test on Ubuntu 20.04
```bash
# Should use 'ip' command
ip -o link show | awk -F': ' '{print $2}' | grep -v "^lo$"
# Expected: eth0, ens33, enp0s3, etc.

ip -4 addr show eth0 | grep "inet "
# Expected: inet 10.2.0.5/16 ...
```

#### Test on CentOS 7
```bash
# Should use 'ip' command (same as Ubuntu)
ip -o link show | awk -F': ' '{print $2}'
ip -4 addr show eth0 | grep "inet "
```

#### Test on CentOS 6
```bash
# Should use 'ifconfig' command
ifconfig -s | tail -n +2 | awk '{print $1}'
# Expected: eth0, eth1, etc.

ifconfig eth0 | grep "inet "
# Expected: inet addr:192.168.1.1 ...
```

## Debugging Empty Network Array

### 1. Check Command Availability
```bash
command -v ip && echo "ip available"
command -v ifconfig && echo "ifconfig available"
```

### 2. Test Interface List Extraction
```bash
# Modern
ip -o link show | awk -F': ' '{print $2}'

# Legacy
ifconfig -s | tail -n +2 | awk '{print $1}'
```

### 3. Test IP Extraction
```bash
iface="eth0"

# IPv4
ip -4 addr show "$iface" | grep "inet "
# Should show: "    inet 10.2.0.5/16 brd ..."

# Extract IP
ip -4 addr show "$iface" | grep "inet " | awk '{print $2}' | cut -d/ -f1
# Should show: 10.2.0.5
```

### 4. Check for Empty Result
```bash
iface="eth0"
ipv4=$(ip -4 addr show "$iface" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)

if [ -z "$ipv4" ]; then
    echo "IPv4 empty for $iface"
else
    echo "IPv4: $ipv4"
fi
```

## Common Issues

### Issue 1: `grep inet` matches `inet6`
```bash
# ❌ WRONG
grep inet  # Matches both 'inet' and 'inet6'

# ✅ CORRECT
grep "inet "  # Space ensures only IPv4
```

### Issue 2: Interface name has colon
```bash
# ❌ WRONG: awk splits by space, field 2 is "eth0:"
ip -o link show | awk '{print $2}'  # → "eth0:"

# ✅ CORRECT: Split by ': ' delimiter
ip -o link show | awk -F': ' '{print $2}'  # → "eth0"
```

### Issue 3: ifconfig format varies
```bash
# CentOS 6: inet addr:192.168.1.1
ifconfig eth0 | grep "inet " | awk '{print $2}'  # → "addr:192.168.1.1"
# Need: sed 's/addr://'

# Ubuntu: inet 192.168.1.1
ifconfig eth0 | grep "inet " | awk '{print $2}'  # → "192.168.1.1"
# OK as-is
```

### Issue 4: No IP on interface
```bash
# Interface exists but has no IP (not configured)
ip link show eth1  # Shows interface
ip addr show eth1  # No 'inet' line

# Solution: Check if ipv4/ipv6 variables are non-empty
if [ -n "$ipv4" ] || [ -n "$ipv6" ]; then
    # Add to JSON
fi
```

## KVS Upload

### Upload Network Debug Data
```bash
# Create JSON
cat > /tmp/netdebug.json <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "test": "network-collection-debug",
  "ip_command_output": "$(ip -o link show 2>&1 | base64 -w0)",
  "interfaces": ["eth0", "eth1"]
}
EOF

# Upload to KVS
/opt/giipAgentLinux/giipscripts/kvsput.sh /tmp/netdebug.json netdebug
```

### Query in Database
```sql
-- Check uploaded data
SELECT 
    KVSsn,
    LSsn,
    KFactor,
    LEFT(KData, 200) AS KDataPreview,
    kRegdt
FROM tKVS
WHERE KFactor = 'netdebug'
ORDER BY kRegdt DESC;

-- Full data for specific entry
SELECT KData FROM tKVS WHERE KVSsn = 12345;
```

### Extract JSON from Database
```powershell
# PowerShell script to extract and view
$query = "SELECT TOP 1 KData FROM tKVS WHERE KFactor = 'netdiag' ORDER BY kRegdt DESC"
$result = Invoke-Sqlcmd -Query $query -ServerInstance "giipdb-server.database.windows.net" -Database "giipdb"
$result.KData | ConvertFrom-Json | ConvertTo-Json -Depth 10
```

## Distribution Support Matrix

| Distribution | Version | Tool | Status | Notes |
|--------------|---------|------|--------|-------|
| Ubuntu | 16.04+ | ip | ✅ Supported | Standard |
| Ubuntu | 14.04 | ifconfig | ✅ Supported | Legacy |
| Debian | 8+ | ip | ✅ Supported | Standard |
| Debian | 7 | ifconfig | ✅ Supported | Legacy |
| CentOS | 7+ | ip | ✅ Supported | Standard |
| CentOS | 6 | ifconfig | ✅ Supported | Legacy (addr: format) |
| RHEL | 7+ | ip | ✅ Supported | Same as CentOS |
| RHEL | 6 | ifconfig | ✅ Supported | Same as CentOS 6 |
| Fedora | All | ip | ✅ Supported | Standard |
| Rocky Linux | 8+ | ip | ✅ Supported | RHEL clone |
| AlmaLinux | 8+ | ip | ✅ Supported | RHEL clone |
| Alpine | 3.x | ip | ✅ Supported | iproute2-ss package |
| openSUSE | All | ip/ifconfig | ⚠️ Untested | Should work |
| Arch Linux | All | ip | ⚠️ Untested | Should work |

## Related Documentation
- [KVSPUT_USAGE_GUIDE.md](KVSPUT_USAGE_GUIDE.md) - KVS upload documentation
- [SQLNETINV_DATA_FLOW.md](../../docs/SQLNETINV_DATA_FLOW.md) - Network data flow

---

**Version**: 1.0.0  
**Last Updated**: October 30, 2025  
**Author**: GIIP Development Team
