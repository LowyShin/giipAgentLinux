# GIIP Agent for Linux

![GIIP Logo](https://giipasp.azurewebsites.net/logo.png)

## 🌟 Overview

GIIP Agent is an intelligent monitoring and management agent that:
- **Executes remote commands** via CQE (Command Queue Execution) system
- **Auto-discovers infrastructure** (OS, hardware, software, services, network)
- **Provides operational advice** based on collected data
- **Reports heartbeat** every 5 minutes to central management

For Windows version: https://github.com/LowyShin/giipAgentWin

> **🔒 SECURITY WARNING**
> 
> **NEVER commit `giipAgent.cnf` with real credentials!**
> 
> The `giipAgent.cnf` file in this repository is a **TEMPLATE ONLY**.
> - Keep your actual configuration file **OUTSIDE** of the git repository
> - The `.gitignore` file is configured to prevent accidental commits
> - Always verify before `git push` that no secrets are included
> 
> **Safe practice:**
> ```bash
> # Keep your config in parent directory
> cp giipAgent.cnf ../giipAgent.cnf.myserver
> vi ../giipAgent.cnf.myserver  # Edit with real secrets
> ln -s ../giipAgent.cnf.myserver giipAgent.cnf  # Symlink for agent to use
> ```

---

## 📋 Prerequisites

### Required Packages
- Git
- Bash shell
- Root or sudo privileges
- Internet connectivity

### Auto-installed Packages
The installation script will automatically install:
- `dos2unix` - Text file format converter
- `wget` - File downloader
- `curl` - HTTP client for API calls

---

## 🚀 Quick Installation

### Step 1: Download Agent

```bash
# Choose installation directory (e.g., /opt, /usr/local, or home directory)
cd /opt

# Clone the repository
git clone https://github.com/LowyShin/giipAgentLinux.git
cd giipAgentLinux
```

### Step 2: Configure Agent

Edit the configuration file:
```bash
vi giipAgent.cnf
```

**Configuration parameters:**
```bash
# Your Secret Key from GIIP portal (https://giipasp.azurewebsites.net)
sk="your-secret-key-here"

# Logical Server Serial Number
# Use "0" for first-time installation (will be auto-assigned)
lssn="0"

# Agent execution interval (seconds)
giipagentdelay="60"

# API server address
apiaddr="https://giipasp.azurewebsites.net"
```

### Step 3: Install Agent

Run the installation script:
```bash
# Make script executable
chmod +x giipcronreg.sh

# Run installation (requires sudo for package installation)
sudo ./giipcronreg.sh
```

**What happens during installation:**
1. Checks for existing GIIP installations
2. Prompts for removal if found (Y/N)
3. Installs required packages (dos2unix, wget, curl)
4. Registers 3 cron jobs:
   - GIIP Agent: Every 1 minute
   - Auto-Discovery: Every 5 minutes
   - Daily Recycle: 23:59 daily
5. Sets executable permissions for scripts

---

## ✅ Verify Installation

### Check Cron Registration
```bash
crontab -l | grep giip
```

**Expected output:**
```
# GIIP Agent - installed 2025-10-27 10:30:45
* * * * * cd /opt/giipAgentLinux; bash --login -c 'sh /opt/giipAgentLinux/giipAgent.sh'
59 23 * * * cd /opt/giipAgentLinux; bash --login -c 'sh /opt/giipAgentLinux/giiprecycle.sh'
*/5 * * * * cd /opt/giipAgentLinux; bash --login -c 'sh /opt/giipAgentLinux/giip-auto-discover.sh'
```

### Check Logs
```bash
# Agent main log
tail -f /var/log/giipAgent_$(date +%Y%m%d).log

# Auto-discovery log
tail -f /var/log/giip-auto-discover.log
```

### Manual Test

Test auto-discovery script:
```bash
# Test discovery collection (JSON output)
./giipscripts/auto-discover-linux.sh

# Test full auto-discovery with API call
./giip-auto-discover.sh
```

---

## 📊 Auto-Discovery Features

The agent automatically collects:

### System Information
- OS name and version (`/etc/os-release`)
- CPU model and core count (`lscpu`)
- Memory size (`/proc/meminfo`)
- Hostname

### Network Configuration
- Interface names
- IPv4/IPv6 addresses
- MAC addresses
- Network device info (`ip addr` or `ifconfig`)

### Software Inventory
- **RPM-based** (CentOS, RHEL, Fedora): `rpm -qa`
- **DEB-based** (Ubuntu, Debian): `dpkg-query`
- Package name, version, vendor
- Up to 100 packages collected

### Service Status
- **systemd**: `systemctl list-units --type=service`
- **SysV**: `service --status-all`
- Service name, status (Running/Stopped)
- Start type (Auto/Manual/Disabled)
- Port numbers for common services
- Up to 50 services collected

### Operational Advice
Automatically generated based on:
- Hardware capacity (CPU, memory)
- OS end-of-life status
- Missing security software
- Missing backup solutions
- Critical service failures
- Web server SSL configuration
- Database monitoring

---

## 🔧 Configuration Details

### File Structure
```
giipAgentLinux/
├── giipAgent.sh              # Main agent (CQE executor)
├── giipAgent.cnf             # Configuration file
├── giipcronreg.sh           # Installation script
├── giiprecycle.sh           # Daily cleanup script
├── giip-auto-discover.sh    # Auto-discovery wrapper
├── giipinstmodule.sh        # Package installer helper
├── giipscripts/
│   ├── auto-discover-linux.sh   # Discovery data collector
│   ├── execmysql.sh
│   ├── kvsput.sh
│   └── mysql_rst2json.sh
└── README.md
```

### Cron Schedule
| Task | Schedule | Purpose |
|------|----------|---------|
| giipAgent.sh | Every 1 minute | Execute remote commands from CQE queue |
| giip-auto-discover.sh | Every 5 minutes | Collect and report infrastructure data |
| giiprecycle.sh | 23:59 daily | Clean up temporary files and logs |

---

## 🔍 Troubleshooting

### Installation Issues

**Problem: Permission denied**
```bash
# Solution: Use sudo
sudo ./giipcronreg.sh
```

**Problem: curl command not found**
```bash
# CentOS/RHEL
sudo yum install -y curl

# Ubuntu/Debian
sudo apt-get install -y curl
```

**Problem: Cron not executing**
```bash
# Check cron service
sudo systemctl status cron     # Debian/Ubuntu
sudo systemctl status crond    # CentOS/RHEL

# Check logs
grep CRON /var/log/syslog     # Debian/Ubuntu
grep CRON /var/log/cron       # CentOS/RHEL
```

### Discovery Issues

**Problem: JSON parsing error**
```bash
# Install jq for validation
sudo yum install -y jq  # CentOS/RHEL
sudo apt-get install -y jq  # Ubuntu/Debian

# Test JSON validity
./giipscripts/auto-discover-linux.sh | jq .
```

**Problem: API call fails**
```bash
# Check network connectivity
curl -v https://giipasp.azurewebsites.net

# Check SSL/TLS
curl --tlsv1.2 https://giipasp.azurewebsites.net

# Manual test
./giip-auto-discover.sh
# Check log: /var/log/giip-auto-discover.log
```

**Problem: No data in GIIP portal**
```bash
# Verify secret key
grep "sk=" giipAgent.cnf

# Check LSSN assignment
grep "lssn=" giipAgent.cnf

# Test API manually
curl -X POST "https://giipasp.azurewebsites.net/api/giipApi?cmd=AgentAutoRegister" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_SECRET_KEY" \
  -d '{"at":"YOUR_SECRET_KEY","jsondata":{}}'
```

---

## 🔄 Reinstallation

### Update Existing Installation

```bash
cd /opt/giipAgentLinux

# Pull latest version
git pull

# Reinstall (will prompt to remove old cron entries)
sudo ./giipcronreg.sh
# Answer 'Y' when prompted to remove old entries
```

### Clean Reinstall

```bash
# Remove cron entries manually
crontab -e
# Delete all lines containing: giipAgent.sh, giip-auto-discover.sh, giiprecycle.sh

# Or use sed
crontab -l | grep -v "giip" | crontab -

# Reinstall
cd /opt/giipAgentLinux
sudo ./giipcronreg.sh
```

---

## 🗑️ Uninstallation

```bash
# Remove cron entries
crontab -l | grep -v "giipAgent.sh\|giip-auto-discover.sh\|giiprecycle.sh\|# GIIP Agent" | crontab -

# Remove agent directory
sudo rm -rf /opt/giipAgentLinux

# Remove logs (optional)
sudo rm -f /var/log/giipAgent_*.log
sudo rm -f /var/log/giip-auto-discover.log
```

---

## 📚 Additional Resources

- **GIIP Portal**: https://giipasp.azurewebsites.net
- **Documentation**: [docs/AGENT_INSTALLATION_GUIDE.md](../docs/AGENT_INSTALLATION_GUIDE.md)
- **Architecture**: [docs/GIIP_ARCHITECTURE.md](../docs/GIIP_ARCHITECTURE.md)
- **Auto-Discovery Design**: [docs/AUTO_DISCOVERY_DESIGN.md](../docs/AUTO_DISCOVERY_DESIGN.md)
- **Windows Agent**: https://github.com/LowyShin/giipAgentWin

---

## 🤝 Support

- **Issues**: https://github.com/LowyShin/giipAgentLinux/issues
- **Email**: support@giip.io
- **Web**: https://giipasp.azurewebsites.net

---

## 📄 License

Free to use for infrastructure management and monitoring.

## Fully automate servers, robots, IoT by giip.

* Go to giip service Page : http://giipasp.azurewebsites.net
* Documentation : https://github.com/LowyShin/giip/wiki
* Sample automation scripts : https://github.com/LowyShin/giip/tree/gh-pages/giipscripts

## GIIP Token uses for engineers!

See more : https://github.com/LowyShin/giip/wiki

* Token exchanges : https://tokenjar.io/GIIP
* Token exchanges manual : https://www.slideshare.net/LowyShin/giipentokenjario-giip-token-trade-manual-20190416-141149519
* GIIP Token Etherscan : https://etherscan.io/token/0x33be026eff080859eb9dfff6029232b094732c52

If you want get GIIP, contact us any time!

## Other Languages

* [English](https://github.com/LowyShin/giip/wiki)
* [日本語](https://github.com/LowyShin/giip-ja/wiki)
* [한국어](https://github.com/LowyShin/giip-ko/wiki)

## Contact

* [Contact Us](https://github.com/LowyShin/giip/wiki/Contact-Us)

