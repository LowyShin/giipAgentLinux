# GIIP Agent Modular Architecture Guide (v3.0)

**Last Updated**: 2025-01-10  
**Version**: 3.0  
**Status**: Production Ready

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Architecture Comparison](#architecture-comparison)
3. [Directory Structure](#directory-structure)
4. [Library Modules](#library-modules)
5. [Migration Guide](#migration-guide)
6. [Testing](#testing)
7. [Troubleshooting](#troubleshooting)

---

## 🌟 Overview

GIIP Agent v3.0 introduces a **modular architecture** to improve maintainability, testability, and reusability.

### Why Refactor?

**Before (v2.0):**
- 👎 1,450 lines in single file
- 👎 Difficult to maintain
- 👎 Hard to test individual functions
- 👎 Code duplication

**After (v3.0):**
- ✅ ~180 lines in main script
- ✅ 5 focused library modules
- ✅ Easy to test and maintain
- ✅ Reusable functions
- ✅ Clear separation of concerns

---

## 🏗️ Architecture Comparison

### v2.0 (Monolithic)

```
giipAgentLinux/
├── giipAgent2.sh (1,450 lines)
│   ├── Gateway Functions (600 lines)
│   ├── Normal Mode (400 lines)
│   ├── KVS Logging (100 lines)
│   ├── DB Clients (260 lines)
│   └── Common Utils (90 lines)
└── giipAgent.cnf
```

### v3.0 (Modular)

```
giipAgentLinux/
├── giipAgent3.sh (180 lines) ⭐ Main entry point
├── giipAgent2.sh (1,450 lines) ⚠️ Legacy (preserved for compatibility)
├── giipAgent.cnf
├── lib/
│   ├── common.sh (150 lines) - Config, logging, error handling
│   ├── kvs.sh (130 lines) - KVS execution logging
│   ├── db_clients.sh (260 lines) - DB client installation
│   ├── gateway.sh (300 lines) - Gateway mode functions
│   └── normal.sh (220 lines) - Normal mode functions
└── test-agent-refactored.sh (Test suite)
```

**Total**: ~1,240 lines (modular) vs 1,450 lines (monolithic)

---

## 📁 Directory Structure

```bash
giipAgentLinux/
│
├── giipAgent3.sh          # Main entry point (v3.0)
├── giipAgent2.sh          # Legacy version (v2.0)
├── giipAgent.cnf          # Configuration file
│
├── lib/                   # Library modules (v3.0)
│   ├── common.sh          # Common functions
│   ├── kvs.sh             # KVS logging
│   ├── db_clients.sh      # DB client management
│   ├── gateway.sh         # Gateway mode
│   └── normal.sh          # Normal mode
│
├── test-agent-refactored.sh  # Test suite
│
├── docs/                  # Documentation
│   ├── MODULAR_ARCHITECTURE.md (this file)
│   ├── AUTO_DISCOVERY_ARCHITECTURE.md
│   ├── GATEWAY_SETUP_GUIDE.md
│   └── GIIPAGENT2_SPECIFICATION.md
│
├── giipscripts/           # Helper scripts
│   ├── kvsput.sh
│   └── ...
│
└── log/                   # Log files
    └── giipAgent3_YYYYMMDD.log
```

---

## 📚 Library Modules

### 1. common.sh (Core Utilities)

**Purpose**: Configuration loading, logging, error handling

**Functions**:
```bash
load_config()           # Load giipAgent.cnf
log_message()           # Write log with timestamp
error_handler()         # Handle errors and exit
check_dos2unix()        # Check/install dos2unix
detect_os()             # Detect OS type
init_log_dir()          # Initialize log directory
build_api_url()         # Build API URL with code
```

**Usage**:
```bash
. "${LIB_DIR}/common.sh"

# Load configuration
load_config "../giipAgent.cnf"

# Log messages
log_message "INFO" "Starting agent..."
log_message "ERROR" "Failed to connect"

# Handle errors
error_handler "Configuration file not found" 1
```

---

### 2. kvs.sh (KVS Logging)

**Purpose**: Save execution logs to KVS (giipagent factor)

**Functions**:
```bash
save_execution_log()    # Save execution event to KVS
kvs_put()               # Generic KVS put operation
save_gateway_status()   # Save gateway status (backward compatibility)
```

**Event Types**:
- `startup` - Agent started
- `queue_check` - Queue fetch attempted
- `script_execution` - Script executed
- `error` - Error occurred
- `shutdown` - Agent stopped
- `gateway_init` - Gateway initialized
- `heartbeat` - Heartbeat collected

**Usage**:
```bash
. "${LIB_DIR}/kvs.sh"

# Save startup event
startup_details='{"pid":12345,"config_file":"giipAgent.cnf"}'
save_execution_log "startup" "$startup_details"

# Save error
error_details='{"error_type":"api_error","error_message":"Connection failed"}'
save_execution_log "error" "$error_details"
```

**⚠️ API Rules** (Follow giipapi_rules.md):
```bash
# ✅ CORRECT
text="KVSPut kType kKey kFactor"  # Parameter names only
jsondata='{"kType":"lssn","kKey":"71174","kFactor":"giipagent"}'  # Actual values

# ❌ WRONG
text="KVSPut lssn 71174 giipagent"  # Don't put values in text!
```

---

### 3. db_clients.sh (Database Client Management)

**Purpose**: Install and check database clients for Gateway mode

**Functions**:
```bash
check_sshpass()             # Check/install sshpass
check_python_environment()  # Check/install Python3
check_mysql_client()        # Check/install MySQL client
check_psql_client()         # Check/install PostgreSQL client
check_mssql_client()        # Check/install MSSQL client (pyodbc)
check_oracle_client()       # Check/install Oracle client (cx_Oracle)
check_db_clients()          # Check all DB clients
```

**Usage**:
```bash
. "${LIB_DIR}/db_clients.sh"

# Check and install all DB clients
check_db_clients

# Check specific client
check_mysql_client
```

**Supported Databases**:
- MySQL/MariaDB
- PostgreSQL
- Microsoft SQL Server (via pyodbc)
- Oracle (via cx_Oracle)

---

### 4. gateway.sh (Gateway Mode)

**Purpose**: Manage remote servers via SSH

**Functions**:
```bash
sync_gateway_servers()      # Fetch server list from API
sync_db_queries()           # Fetch DB query list from API
execute_remote_command()    # Execute script on remote server
get_script_by_mssn()        # Fetch script from repository
get_remote_queue()          # Get queue for specific server
process_gateway_servers()   # Process all gateway servers
```

**Usage**:
```bash
. "${LIB_DIR}/gateway.sh"

# Sync servers from API
sync_gateway_servers

# Process all servers
process_gateway_servers
```

**SSH Authentication**:
- Password authentication (via sshpass)
- Key-based authentication

---

### 5. normal.sh (Normal Mode)

**Purpose**: Local agent queue processing

**Functions**:
```bash
fetch_queue()           # Fetch queue from API
parse_json_response()   # Parse JSON response
execute_script()        # Execute script file
run_normal_mode()       # Main normal mode function
```

**Usage**:
```bash
. "${LIB_DIR}/normal.sh"

# Run normal mode
run_normal_mode "$lssn" "$hostname" "$os"
```

**Execution Flow**:
1. Fetch queue from API
2. Parse JSON response
3. Extract script (ms_body or repository)
4. Execute script (bash or expect)
5. Log to KVS

---

## 🔄 Migration Guide

### For New Installations

**Use giipAgent3.sh (v3.0)**:

```bash
cd /opt
git clone https://github.com/LowyShin/giipAgentLinux.git
cd giipAgentLinux

# Configure
cp giipAgent.cnf.template giipAgent.cnf
vi giipAgent.cnf  # Set sk, lssn, etc.

# Test
bash test-agent-refactored.sh

# Run (Normal mode)
bash giipAgent3.sh

# Run (Gateway mode)
# Set gateway_mode="1" in giipAgent.cnf
bash giipAgent3.sh
```

### For Existing Installations

**Option 1: Keep Using giipAgent2.sh (Recommended for stability)**

```bash
# No changes needed
# giipAgent2.sh continues to work
```

**Option 2: Migrate to giipAgent3.sh (For new features)**

```bash
# Backup current setup
cp giipAgent2.sh giipAgent2.sh.backup
cp giipAgent.cnf giipAgent.cnf.backup

# Pull latest changes
git pull

# Test new version
bash test-agent-refactored.sh

# Update cron job
crontab -e
# Change: */5 * * * * /opt/giipAgentLinux/giipAgent2.sh
# To:     */5 * * * * /opt/giipAgentLinux/giipAgent3.sh
```

### Rollback Plan

```bash
# If issues occur, rollback to v2.0
crontab -e
# Change back to: */5 * * * * /opt/giipAgentLinux/giipAgent2.sh

# Or restore backup
cp giipAgent2.sh.backup giipAgent2.sh
cp giipAgent.cnf.backup giipAgent.cnf
```

---

## ✅ Testing

### Run Test Suite

```bash
cd /opt/giipAgentLinux

# Run full test suite
bash test-agent-refactored.sh
```

**Test Coverage**:
1. ✅ Library files existence
2. ✅ Library loading
3. ✅ Configuration loading
4. ✅ Function availability
5. ✅ Syntax checking

**Expected Output**:
```
==================================================
GIIP Agent Refactored Test Suite
==================================================

[TEST 1] Checking library files...
  ✅ lib/common.sh exists
  ✅ lib/kvs.sh exists
  ✅ lib/db_clients.sh exists
  ✅ lib/gateway.sh exists
  ✅ lib/normal.sh exists
  ✅ giipAgent3.sh exists
  Result: 6 passed, 0 failed

[TEST 2] Testing library loading...
  ✅ common.sh loaded successfully
  ✅ kvs.sh loaded successfully
  ✅ db_clients.sh loaded successfully
  ✅ gateway.sh loaded successfully
  ✅ normal.sh loaded successfully

...

==================================================
Test completed!
==================================================
```

### Manual Testing

**Test Normal Mode**:
```bash
# Edit config
vi giipAgent.cnf
# Set: gateway_mode="0"

# Run once
bash giipAgent3.sh

# Check logs
tail -30 log/giipAgent3_$(date +%Y%m%d).log

# Check KVS data
pwsh ../giipdb/mgmt/query-kvs-giipagent.ps1 -Lssn "YOUR_LSSN" -Top 10
```

**Test Gateway Mode**:
```bash
# Edit config
vi giipAgent.cnf
# Set: gateway_mode="1"

# Run once
bash giipAgent3.sh

# Check logs
tail -50 log/giipAgent3_$(date +%Y%m%d).log

# Verify server list
cat /tmp/gateway_servers.csv
```

---

## 🔧 Troubleshooting

### Common Issues

#### 1. Library not found

**Error**:
```
❌ Error: common.sh not found in /opt/giipAgentLinux/lib
```

**Solution**:
```bash
# Check lib directory exists
ls -la lib/

# Re-clone if missing
cd /opt
rm -rf giipAgentLinux
git clone https://github.com/LowyShin/giipAgentLinux.git
```

#### 2. Function not available

**Error**:
```
bash: load_config: command not found
```

**Solution**:
```bash
# Check if library is sourced
grep "source.*lib/common.sh" giipAgent3.sh

# Manually source for testing
. lib/common.sh
```

#### 3. Permission denied

**Error**:
```
bash: lib/common.sh: Permission denied
```

**Solution**:
```bash
# Make libraries executable (run on server)
chmod +x giipAgent3.sh lib/*.sh test-agent-refactored.sh
```

#### 4. Configuration load failed

**Error**:
```
❌ Failed to load configuration
```

**Solution**:
```bash
# Check config file exists
ls -l ../giipAgent.cnf

# Verify required variables
grep -E "^(lssn|sk|apiaddrv2)" ../giipAgent.cnf

# Test config loading
bash -c '. lib/common.sh; load_config "../giipAgent.cnf" && echo OK'
```

### Debug Mode

**Enable verbose logging**:
```bash
# Edit giipAgent3.sh
# Add at top:
set -x  # Enable debug mode
```

**Check execution trace**:
```bash
bash -x giipAgent3.sh 2>&1 | tee debug.log
```

---

## 📊 Performance Comparison

| Metric | v2.0 (Monolithic) | v3.0 (Modular) | Improvement |
|--------|-------------------|----------------|-------------|
| Main file size | 1,450 lines | 180 lines | 🔻 87% reduction |
| Load time | ~0.5s | ~0.6s | Similar |
| Memory usage | ~15MB | ~16MB | Similar |
| Test coverage | Manual only | Automated suite | ✅ Improved |
| Maintainability | Low | High | ✅ Much better |
| Reusability | None | High | ✅ Functions reusable |

---

## 🎯 Best Practices

### 1. Use Appropriate Version

- **Production servers (stable)**: Use `giipAgent2.sh`
- **New deployments (modern)**: Use `giipAgent3.sh`
- **Testing/Development**: Use `giipAgent3.sh`

### 2. Always Test Before Deploy

```bash
# Test on one server first
bash test-agent-refactored.sh
bash giipAgent3.sh

# Monitor for 1 day
tail -f log/giipAgent3_*.log

# Roll out to other servers
```

### 3. Keep Configuration Secure

```bash
# Store config outside git
cp giipAgent.cnf ../giipAgent.cnf.prod
chmod 600 ../giipAgent.cnf.prod

# Use symlink
ln -sf ../giipAgent.cnf.prod giipAgent.cnf
```

### 4. Monitor Logs

```bash
# Check recent logs
tail -50 log/giipAgent3_$(date +%Y%m%d).log

# Check for errors
grep -i "error\|failed" log/giipAgent3_*.log

# Check KVS logging
pwsh ../giipdb/mgmt/query-kvs-giipagent.ps1 -Lssn "71174" -Top 20
```

### 5. Writing New Shell Scripts (CRITICAL RULES)

**⚠️ Configuration File Path Rule:**

All shell scripts in `giipAgentLinux/` directory **MUST** follow the same config path as `giipAgent3.sh`.

**✅ CORRECT:**
```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../giipAgent.cnf"  # ← Parent directory

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config file not found: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"
```

**❌ WRONG:**
```bash
# ❌ Don't use different config paths!
CONFIG_FILE="$SCRIPT_DIR/giipAgentGateway.cnf"  # WRONG
CONFIG_FILE="./giipAgent.cnf"                   # WRONG (relative path)
CONFIG_FILE="/etc/giip/config.cnf"              # WRONG (absolute path)
```

**Why?**
- `giipAgent3.sh` uses `../giipAgent.cnf` (parent directory)
- All scripts must use the **same config file** for consistency
- Config location: `/opt/giipAgent.cnf` or `/home/giip/giipAgent.cnf`
- Scripts location: `/opt/giipAgentLinux/` or `/home/giip/giipAgentLinux/`

**Example Scripts:**
- ✅ `test-managed-db-check.sh` - Uses `../giipAgent.cnf`
- ✅ `giipAgent3.sh` - Uses `../giipAgent.cnf`
- ✅ `lib/common.sh` - `load_config("../giipAgent.cnf")`

**Loading Library Modules:**

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Load common functions first
if [ -f "${LIB_DIR}/common.sh" ]; then
    . "${LIB_DIR}/common.sh"
else
    echo "❌ Error: common.sh not found in ${LIB_DIR}"
    exit 1
fi

# Load config using common.sh function
load_config "../giipAgent.cnf"
if [ $? -ne 0 ]; then
    echo "❌ Failed to load configuration"
    exit 1
fi

# Now you have: lssn, sk, apiaddrv2, apiaddrcode, etc.
```

**Template for New Scripts:**

```bash
#!/bin/bash
# Script Name: example-script.sh
# Purpose: Brief description
# Author: Your Name
# Date: YYYY-MM-DD

# Initialize paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
CONFIG_FILE="$SCRIPT_DIR/../giipAgent.cnf"

# Load library modules (if needed)
if [ -f "${LIB_DIR}/common.sh" ]; then
    . "${LIB_DIR}/common.sh"
    load_config "../giipAgent.cnf" || exit 1
else
    # Standalone script (no lib dependency)
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "❌ Config file not found: $CONFIG_FILE"
        exit 1
    fi
    source "$CONFIG_FILE"
fi

# Validate required variables
if [ -z "$lssn" ] || [ -z "$sk" ] || [ -z "$apiaddrv2" ]; then
    echo "❌ Missing required config: lssn, sk, apiaddrv2"
    exit 1
fi

# Your script logic here
echo "✅ Script initialized successfully"
echo "   LSSN: $lssn"
echo "   API: $apiaddrv2"
```

**Checklist for New Scripts:**
- [ ] Config path: `../giipAgent.cnf` (parent directory)
- [ ] Use `SCRIPT_DIR` for relative paths
- [ ] Validate required variables (lssn, sk, apiaddrv2)
- [ ] Error handling: exit 1 on failures
- [ ] Echo clear error messages with ❌ emoji
- [ ] Use `#!/bin/bash` shebang (not `#!/bin/sh`)
- [ ] Make executable: `chmod +x script.sh`
- [ ] Test before commit: `bash -n script.sh` (syntax check)

---

## 📝 Summary

**v3.0 Benefits**:
- ✅ **Maintainable** - Each module has single responsibility
- ✅ **Testable** - Functions can be tested independently
- ✅ **Reusable** - Libraries can be used in other scripts
- ✅ **Readable** - Clear separation of concerns
- ✅ **Extensible** - Easy to add new features

**Migration Path**:
- **Low Risk**: Keep using giipAgent2.sh
- **Medium Risk**: Test giipAgent3.sh on non-critical servers
- **Production Ready**: After successful testing period

**Next Steps**:
1. Run test suite: `bash test-agent-refactored.sh`
2. Test on dev server: `bash giipAgent3.sh`
3. Monitor logs for 1 day
4. Deploy to production

---

**Questions or Issues?**
- GitHub: https://github.com/LowyShin/giipAgentLinux/issues
- Documentation: [README.md](../README.md)
- Specification: [GIIPAGENT2_SPECIFICATION.md](GIIPAGENT2_SPECIFICATION.md)
