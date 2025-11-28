# GIIP Agent Gateway

## Overview

GIIP Agent Gateway is a special version of GIIP Agent designed for **bastion/gateway servers** that manage multiple remote servers via SSH. Instead of executing commands locally, it forwards GIIP commands to remote servers through SSH connections.

## Architecture

```
┌─────────────────────┐
│   GIIP API Server   │
│  (giipasp.azure...) │
└──────────┬──────────┘
           │ HTTPS
           │ Queue Download
           │
┌──────────▼──────────┐
│  Gateway Server     │
│ giipAgentGateway.sh │ ← Runs on bastion/gateway
└──────────┬──────────┘
           │ SSH
           ├─────────────────┐
           │                 │
┌──────────▼──────────┐  ┌──▼────────────────┐
│  Remote Server 1    │  │  Remote Server 2  │
│  (Web Server)       │  │  (DB Server)      │
│  Execute Commands   │  │  Execute Commands │
└─────────────────────┘  └───────────────────┘
```

## Use Cases

1. **Firewall Restrictions**: Remote servers can't directly access internet/GIIP API
2. **Security Policy**: Centralized management through bastion server
3. **Network Segmentation**: DMZ or isolated network environments
4. **Hybrid Cloud**: Managing servers across different networks

## Features

- ✅ Manage multiple remote servers from single gateway
- ✅ SSH key-based authentication (recommended)
- ✅ SSH password-based authentication (for legacy servers)
- ✅ Per-server configuration (hostname, port, SSH key/password)
- ✅ Parallel or sequential execution
- ✅ Individual LSSN (Server ID) for each remote server
- ✅ Enable/disable servers without removing configuration
- ✅ Centralized logging
- ✅ Encrypted password storage in database

## Installation

### Prerequisites

**On Gateway Server:**
- SSH client installed
- Internet access to GIIP API
- dos2unix, wget, curl

**On Remote Servers:**
- SSH server running
- Shell access (bash)
- User account for gateway connection

### Quick Install

```bash
# 1. Clone or download giipAgentLinux
cd ~
git clone https://github.com/LowyShin/giipAgentLinux.git

# 2. Run installation script
cd giipAgentLinux
chmod +x install-gateway.sh
./install-gateway.sh
```

### Manual Installation

```bash
# 1. Create installation directory
mkdir -p ~/giipAgentGateway
cd ~/giipAgentGateway

# 2. Copy gateway files
cp /path/to/giipAgentLinux/giipAgentGateway.sh .
cp /path/to/giipAgentLinux/giipAgent.cnf .
cp /path/to/giipAgentLinux/giipAgentGateway_servers.csv .

# 3. Make executable
chmod +x giipAgentGateway.sh

# 4. Configure
vi giipAgent.cnf  # Set gateway_mode="1" and your GIIP secret key
vi giipAgentGateway_servers.csv  # Add your servers
```

## Configuration

### 1. giipAgent.cnf

Basic gateway configuration:

```bash
# Your GIIP secret key (from web portal)
sk="your_secret_key_here"

# Check interval (seconds)
giipagentdelay="60"

# API endpoints
apiaddr="https://giipasp.azurewebsites.net"
apiaddrv2="https://giipfaw.azurewebsites.net/api/giipApiSk2"

# Server list file
serverlist_file="./giipAgentGateway_servers.csv"
```

### 2. giipAgentGateway_servers.csv

Server list configuration (CSV format):

```csv
# hostname,lssn,ssh_host,ssh_user,ssh_port,ssh_key_path,os_info,enabled

# Production servers
webserver01,1001,192.168.1.10,root,22,~/.ssh/id_rsa,CentOS%207,1
dbserver01,1002,192.168.1.20,dbadmin,22,~/.ssh/db_key,Ubuntu%2020.04,1
appserver01,1003,10.0.0.30,appuser,2222,~/.ssh/app_key,RHEL%208,1

# Disabled server (enabled=0)
oldserver,1004,192.168.1.99,root,22,~/.ssh/id_rsa,CentOS%206,0
```

**Fields:**
- `hostname`: Server hostname (for GIIP identification)
- `lssn`: GIIP Server ID (get from web portal)
- `ssh_host`: SSH connection address (IP or hostname)
- `ssh_user`: SSH username
- `ssh_port`: SSH port (usually 22)
- `ssh_key_path`: Path to SSH private key (empty for password auth)
- `os_info`: OS information (use %20 for spaces)
- `enabled`: 1=enabled, 0=disabled

## SSH Key Setup

### Generate SSH Key (on Gateway)

```bash
# Generate new key for gateway
ssh-keygen -t rsa -b 4096 -f ~/.ssh/giip_gateway_key

# Or use existing key
ls ~/.ssh/id_rsa
```

### Deploy to Remote Servers

**Method 1: ssh-copy-id (recommended)**
```bash
ssh-copy-id -i ~/.ssh/giip_gateway_key.pub root@192.168.1.10
```

**Method 2: Manual**
```bash
# On gateway server
cat ~/.ssh/giip_gateway_key.pub

# On remote server
mkdir -p ~/.ssh
chmod 700 ~/.ssh
vi ~/.ssh/authorized_keys  # Paste public key
chmod 600 ~/.ssh/authorized_keys
```

### Test SSH Connection

```bash
# Test key authentication
ssh -i ~/.ssh/giip_gateway_key root@192.168.1.10 "hostname && uname -a"

# Test without password prompt
ssh -o BatchMode=yes -i ~/.ssh/giip_gateway_key root@192.168.1.10 "echo success"

# Test password authentication (if PubkeyAuthentication is disabled)
sshpass -p 'your_password' ssh root@192.168.1.10 "hostname"
```

## SSH Authentication Methods

### Method 1: SSH Key Authentication (Recommended)

**Advantages:**
- ✅ More secure (no password transmission)
- ✅ No sshpass dependency
- ✅ Faster authentication
- ✅ Can use SSH agent

**Configuration:**
- Set `ssh_key_path` in server CSV
- Leave `ssh_password` empty

### Method 2: Password Authentication

**Use Cases:**
- ⚠️ Legacy servers with `PubkeyAuthentication no`
- ⚠️ Corporate policy requires password auth
- ⚠️ Cannot modify remote server SSH config

**Advantages:**
- ✅ Works with any SSH server
- ✅ No key file management

**Disadvantages:**
- ❌ Less secure (password in CSV file)
- ❌ Requires sshpass installation
- ❌ Password visible in process list (briefly)

**Configuration:**
1. Install sshpass:
```bash
chmod +x install-sshpass.sh
sudo ./install-sshpass.sh
```

2. Configure server with password:
```csv
# Leave ssh_key_path empty, provide password
oldserver01,1003,10.0.0.30,admin,22,,MyPassword123,RHEL%205,1
```

3. **Security**: Set file permissions
```bash
chmod 600 giipAgentGateway_servers.csv
```

### Automatic Sync from Database

If you store passwords encrypted in the GIIP database:

```bash
# Configure database connection in giipAgent.cnf
db_server="your-db-server.database.windows.net"
db_name="giipDB"
db_user="giip_readonly"
db_password="your_db_password"

# Sync servers from database (decrypts passwords)
chmod +x sync-gateway-servers.sh
./sync-gateway-servers.sh

# This generates giipAgentGateway_servers.csv automatically
```

**Benefits:**
- ✅ Passwords encrypted in database
- ✅ Centralized management via Web UI
- ✅ Auto-sync with database
- ✅ No manual CSV editing

## Running the Gateway Agent

### Manual Start

```bash
cd ~/giipAgentGateway
./giipAgentGateway.sh
```

### Cron Job (Auto-restart)

```bash
# Edit crontab
crontab -e

# Add this line (runs every 5 minutes)
*/5 * * * * cd $HOME/giipAgentGateway && ./giipAgentGateway.sh >/dev/null 2>&1
```

The agent will:
1. Check if already running (prevents duplicates)
2. Process each enabled server in the list
3. Get command queue from GIIP API for each server
4. Execute commands on remote servers via SSH
5. Sleep for configured interval
6. Repeat

## Monitoring

### Check Logs

```bash
# Today's log
tail -f /var/log/giipAgentGateway_$(date +%Y%m%d).log

# All logs
ls -lh /var/log/giipAgentGateway_*.log

# Recent activity
tail -100 /var/log/giipAgentGateway_$(date +%Y%m%d).log
```

### Check Process

```bash
# Check if running
ps aux | grep giipAgentGateway.sh

# Check multiple instances (should be ≤ 3)
ps aux | grep giipAgentGateway.sh | grep -v grep | wc -l
```

### Log Format

```
[20251101120001] Gateway Agent Started (v1.0)
[20251101120001] Starting server processing cycle...
[20251101120001] Processing server: webserver01 (LSSN: 1001, SSH: root@192.168.1.10:22)
[20251101120002] Queue received for webserver01, executing remotely...
[20251101120005] Successfully executed on webserver01
[20251101120005] Processing server: dbserver01 (LSSN: 1002, SSH: dbadmin@192.168.1.20:22)
[20251101120006] No queue for dbserver01
[20251101120006] Cycle completed, sleeping 60 seconds...
```

## Troubleshooting

### SSH Connection Fails

```bash
# Test SSH connectivity
ssh -vvv -i ~/.ssh/giip_gateway_key root@192.168.1.10

# Check SSH key permissions
ls -l ~/.ssh/giip_gateway_key  # Should be 600
chmod 600 ~/.ssh/giip_gateway_key

# Check known_hosts
ssh-keyscan -H 192.168.1.10 >> ~/.ssh/known_hosts
```

### No Queue Downloaded

```bash
# Check API connectivity
curl "https://giipasp.azurewebsites.net/api/cqe/cqequeueget03.asp?sk=YOUR_SK&lssn=1001&hn=test&os=Linux&df=os&sv=1.0"

# Check configuration
cat <installation_directory>/giipAgent.cnf | grep sk=  # e.g., /opt/giipAgent.cnf
```

### Agent Not Running

```bash
# Check process count
ps aux | grep giipAgentGateway.sh

# Kill stuck processes
pkill -f giipAgentGateway.sh

# Restart
cd ~/giipAgentGateway && ./giipAgentGateway.sh
```

### Remote Execution Fails

```bash
# Check remote server logs
ssh root@192.168.1.10 "ls -l /tmp/giipTmpScript.sh"
ssh root@192.168.1.10 "cat /tmp/giipTmpScript.sh"

# Test manual execution
ssh root@192.168.1.10 "echo 'echo test' > /tmp/test.sh && chmod +x /tmp/test.sh && /tmp/test.sh"
```

## Advanced Configuration

### Different SSH Keys per Server

```csv
webserver01,1001,192.168.1.10,root,22,~/.ssh/web_key,CentOS%207,1
dbserver01,1002,192.168.1.20,dbadmin,22,~/.ssh/db_key,Ubuntu%2020.04,1
```

### Non-standard SSH Ports

```csv
appserver01,1003,10.0.0.30,appuser,2222,~/.ssh/app_key,RHEL%208,1
```

### Password Authentication (Not Recommended)

Leave ssh_key_path empty, but you'll need to configure SSH password authentication:

```csv
testserver,2001,192.168.2.10,testuser,22,,Ubuntu%2022.04,1
```

Then install `sshpass`:
```bash
# Modify execute_remote_command() in giipAgentGateway.sh to use sshpass
```

## Security Best Practices

1. ✅ Use SSH key authentication (not passwords)
2. ✅ Restrict SSH key permissions (chmod 600)
3. ✅ Use dedicated SSH user with minimal privileges
4. ✅ Keep GIIP secret key secure (don't commit to git)
5. ✅ Use SSH bastion/jump host if possible
6. ✅ Enable SSH connection timeout
7. ✅ Monitor gateway logs regularly
8. ✅ Disable unused servers (set enabled=0)

## Comparison: Standard vs Gateway Agent

| Feature | Standard Agent | Gateway Agent |
|---------|----------------|---------------|
| **Installation** | On each server | On gateway only |
| **Execution** | Local | Remote via SSH |
| **Internet Access** | Required | Gateway only |
| **LSSN** | One per server | One per remote server |
| **Configuration** | Per server | Centralized CSV |
| **SSH Required** | No | Yes |
| **Use Case** | Direct access | Restricted network |

## Migration from Standard Agent

If you have existing servers with standard agent and want to migrate to gateway:

1. **Get LSSN from existing servers:**
   ```bash
   ssh server1 "grep lssn <installation_directory>/giipAgent.cnf"  # e.g., /opt/giipAgent.cnf
   ```

2. **Add to gateway server list:**
   ```csv
   server1,1001,192.168.1.10,root,22,~/.ssh/id_rsa,CentOS%207,1
   ```

3. **Test gateway execution:**
   ```bash
   # Temporarily enable both
   # Monitor logs to ensure gateway works
   ```

4. **Disable standard agent on remote server:**
   ```bash
   ssh server1 "crontab -l | grep -v giipAgent.sh | crontab -"
   ```

## FAQ

**Q: Can I mix standard and gateway agents?**  
A: Yes, but avoid duplicate execution. Use different LSSN or disable one method.

**Q: How many servers can one gateway manage?**  
A: Depends on command frequency. Generally 50-100 servers per gateway.

**Q: What if SSH connection is slow?**  
A: Increase `giipagentdelay` or use parallel execution (future feature).

**Q: Can I use gateway for Windows servers?**  
A: Only if remote Windows has SSH server (Windows 10/Server 2019+).

**Q: How to handle SSH fingerprint changes?**  
A: Use `StrictHostKeyChecking=no` (already in script) or manage known_hosts.

## See Also

- [Standard Agent README](README.md)
- [GIIP CQE Architecture](docs/CQE_ARCHITECTURE.md)
- [GIIP API Documentation](docs/GIIP_API_AUTHENTICATION.md)

## Support

For issues or questions:
- GitHub: https://github.com/LowyShin/giipAgentLinux
- Email: support@giip.net

---

**Version**: 1.0  
**Last Updated**: 2025-11-01  
**Author**: Lowy Shin
