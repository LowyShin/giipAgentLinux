# GIIP Agent for Linux

![GIIP Logo](https://giipasp.azurewebsites.net/logo.png)

**Last Updated**: 2025-11-26 - Clean Architecture & Directory Organization 🎯

**Version**: 3.0 (Modular Architecture)

> **🚨 FOR AI AGENTS: Configuration File Warning**
> 
> **`giipAgent.cnf` in this repository is a SAMPLE/TEMPLATE ONLY!**
> 
> - ❌ DO NOT read this file to diagnose production issues
> - ❌ DO NOT use values from this git file for troubleshooting
> - ✅ ALWAYS check the ACTUAL file on deployed servers:
>   ```bash
>   ssh user@server "cat ~/giipAgent/giipAgent.cnf"
>   ```
> - Repository file is ONLY for new installations, NOT for debugging

## 📋 Documentation

### 🆕 Architecture & Design (v3.0)
- **[Modular Architecture Guide](docs/MODULAR_ARCHITECTURE.md)** - 리팩토링된 구조 설명 (v3.0) 🆕
- **[SSH Connection Module Guide](docs/SSH_CONNECTION_MODULE_GUIDE.md)** - 🆕 SSH 연결 테스트 별도 모듈 사용 가이드
- [Auto-Discovery Architecture](docs/AUTO_DISCOVERY_ARCHITECTURE.md) - 파일 구조와 실행 흐름 상세 설명
- [Service Package Filter](docs/SERVICE_PACKAGE_FILTER.md) - 소프트웨어 필터링 규칙
- **[giipAgent3.sh Specification](docs/GIIPAGENT3_SPECIFICATION.md)** - giipAgent3.sh 실행 조건, 동작 흐름, KVS 저장 로직 완전 문서화 🆕
- **[📊 DPA Integration](docs/DPA_INTEGRATION_TEST.md)** - 🚨 Database Performance Analysis 시스템 완전 가이드
  - DPA 데이터 수집/저장 구조
  - kType='database', kKey=mdb_id 명명 규칙
  - Shell scripts: dpa-managed-databases.sh, dpa-put-mssql.sh, dpa-put-mysql.sh
  - Frontend 연동: SQL3D 페이지에서 DPA 데이터 조회/표시 방법

### Gateway & Remote Control
- **[⚠️ Gateway Configuration Philosophy](docs/GATEWAY_CONFIG_PHILOSOPHY.md)** - **필독! DB as Single Source of Truth** 🔥
- **[⚠️ Config Addition Checklist](docs/CHECKLIST_BEFORE_ADDING_CONFIG.md)** - **설정 추가 전 필수 확인사항** 🚨
- **[Gateway Setup Guide](docs/GATEWAY_SETUP_GUIDE.md)** - 실제 환경 설정 가이드 (실무 중심)
- [Gateway README](gateway/README_GATEWAY.md) - Gateway Agent 전체 매뉴얼
- [Gateway Quick Start (KR)](gateway/GATEWAY_QUICKSTART_KR.md) - 빠른 시작 가이드
- [Gateway Implementation Summary](docs/GATEWAY_IMPLEMENTATION_SUMMARY.md) - 기술적 구현 세부사항

### API & Integration
- [API Endpoints Comparison](../giipfaw/docs/API_ENDPOINTS_COMPARISON.md) - giipApi vs giipApiSk vs giipApiSk2 차이점

### Installation & Operation
- [Agent Installation Guide](../giipdb/docs/AGENT_INSTALLATION_GUIDE.md) - Linux/Windows 에이전트 설치
- [Test Server Installation](../giipdb/docs/TEST_SERVER_INSTALLATION.md) - 테스트 환경 구축

## 📁 폴더 구조 (v3.0 Clean Architecture)

```
giipAgentLinux/
├── 📄 giipAgent.sh           ✅ 핵심: 기존 에이전트
├── 📄 giipAgent3.sh          ✅ 핵심: 개선된 에이전트 (권장)
├── 📄 giipAgent.cnf          ✅ 핵심: 설정 파일 (템플릿)
├── 📄 README.md              ✅ 핵심: 이 문서
│
├── 📁 docs/                  문서 (가이드, 설명서)
│   ├── *.md                  아키텍처, 설정, 가이드 등
│   └── README.md
│
├── 📁 lib/                   라이브러리 (핵심 함수 모음)
│   ├── *.sh                  공통 함수, KVS API 등
│   └── README.md
│
├── 📁 giipscripts/           기본 스크립트 (auto-discover 등)
│   └── README.md
│
├── 📁 scripts/               유틸리티 스크립트 (진단, 모니터링, 동기화)
│   ├── check-*.sh
│   ├── collect-*.sh
│   ├── diagnose-*.sh
│   ├── run-*.sh
│   ├── sync-*.sh
│   └── README.md
│
├── 📁 tests/                 테스트 스크립트 (개발, 검증용)
│   ├── test-*.sh
│   ├── test-*.ps1
│   └── README.md
│
├── 📁 gateway/               Gateway 모드 스크립트
│   ├── giipAgentGateway.sh
│   ├── giipAgentGateway-heartbeat.sh
│   ├── *.csv.template
│   ├── GATEWAY_*.md
│   ├── README_GATEWAY*.md
│   └── README.md
│
├── 📁 cqe/                   CQE (명령 큐) 관련 스크립트
│   ├── giipCQE.sh
│   ├── giipCQECtrl.sh
│   ├── CQE_TEST_GUIDE.md
│   └── README.md
│
└── 📁 admin/                 관리자용 스크립트 (설치, 등록, 유지보수)
    ├── install-*.sh
    ├── giip*.sh
    └── README.md
```

### 📌 시작하기

1. **표준 설치**: `giipAgent3.sh` 실행
2. **Gateway 설정**: `gateway/` 폴더 참고
3. **문제 해결**: `docs/` 폴더의 가이드 참고
4. **스크립트 설명**: 각 폴더의 `README.md` 참고

---

- **Standard Agent**: Install directly on each server (standard installation)
- **Gateway Agent**: Install on bastion/gateway server to manage multiple remote servers via SSH
  - 🆕 **Web UI Configuration**: No more manual SSH configuration!
  - See [docs/GATEWAY_AUTO_CONFIGURATION.md](docs/GATEWAY_AUTO_CONFIGURATION.md) for details
  - See [docs/GATEWAY_USAGE_GUIDE.md](docs/GATEWAY_USAGE_GUIDE.md) for usage guide
  - See [gateway/README_GATEWAY.md](gateway/README_GATEWAY.md) for traditional setup

For Windows version: https://github.com/LowyShin/giipAgentWin

> **🔒 CRITICAL: API Endpoint Configuration**
> 
> **giip-auto-discover.sh MUST use apiaddrv2 (giipApiSk2)**
> 
> ```bash
> # ✅ CORRECT
> API_URL="${apiaddrv2}"  # giipApiSk2 - SK authentication
> 
> # ❌ WRONG
> API_URL="${Endpoint}"   # giipApi - Session authentication (Web UI only)
> ```
> 
> **Why?**
> - `Endpoint` (giipApi) = Session-based, 2hr TTL, requires web login

## 🌟 Overview

GIIP Agent is an intelligent monitoring and management agent that:
- **Executes remote commands** via CQE (Command Queue Execution) system 🚀 **v2.0**
- **Gateway mode** for managing multiple remote servers via SSH 🆕 **v3.0**
- **Auto-discovers infrastructure** (OS, hardware, software, services, network)
- **Provides operational advice** based on collected data
- **Reports heartbeat** every 5 minutes to central management
- **Tracks execution history** via KVS (giipagent factor) for full audit trail 🆕 **v2.0**

**NEW in v3.0**: Web UI-based Gateway configuration with automatic script deployment!

**NEW in v2.0**: Execution tracking - All agent activities (queue checks, script executions, errors) are automatically logged to KVS with "giipagent" factor for complete audit trail and troubleshooting.

### Deployment Options

- **Standard Agent**: Install directly on each server (standard installation)
- **Gateway Agent**: Install on bastion/gateway server to manage multiple remote servers via SSH
  - 🆕 **Web UI Configuration**: No more manual SSH configuration!
  - See [docs/GATEWAY_AUTO_CONFIGURATION.md](docs/GATEWAY_AUTO_CONFIGURATION.md) for details
  - See [docs/GATEWAY_USAGE_GUIDE.md](docs/GATEWAY_USAGE_GUIDE.md) for usage guide
  - See [gateway/README_GATEWAY.md](gateway/README_GATEWAY.md) for traditional setup

For Windows version: https://github.com/LowyShin/giipAgentWin

> **� CRITICAL: API Endpoint Configuration**
> 
> **giip-auto-discover.sh MUST use apiaddrv2 (giipApiSk2)**
> 
> ```bash
> # ✅ CORRECT
> API_URL="${apiaddrv2}"  # giipApiSk2 - SK authentication
> 
> # ❌ WRONG
> API_URL="${Endpoint}"   # giipApi - Session authentication (Web UI only)
> ```
> 
> **Why?**
> - `Endpoint` (giipApi) = Session-based, 2hr TTL, requires web login
> - `apiaddrv2` (giipApiSk2) = SK-based, permanent, for server agents
> 
> See [API_ENDPOINTS_COMPARISON.md](../giipfaw/docs/API_ENDPOINTS_COMPARISON.md) for details.

> **�🔒 SECURITY WARNING**
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

## � Documentation

### Architecture & Design
- [Auto-Discovery Architecture](docs/AUTO_DISCOVERY_ARCHITECTURE.md) - 파일 구조와 실행 흐름 상세 설명
- [Service Package Filter](docs/SERVICE_PACKAGE_FILTER.md) - 소프트웨어 필터링 규칙

### Gateway & Remote Control
- **[Gateway Setup Guide](docs/GATEWAY_SETUP_GUIDE.md)** - 실제 환경 설정 가이드 (실무 중심)
- [Gateway README](gateway/README_GATEWAY.md) - Gateway Agent 전체 매뉴얼
- [Gateway Quick Start (KR)](gateway/GATEWAY_QUICKSTART_KR.md) - 빠른 시작 가이드
- [Gateway Implementation Summary](docs/GATEWAY_IMPLEMENTATION_SUMMARY.md) - 기술적 구현 세부사항

### API & Integration
- [API Endpoints Comparison](../giipfaw/docs/API_ENDPOINTS_COMPARISON.md) - giipApi vs giipApiSk vs giipApiSk2 차이점

### Installation & Operation
- [Agent Installation Guide](../giipdb/docs/AGENT_INSTALLATION_GUIDE.md) - Linux/Windows 에이전트 설치
- [Test Server Installation](../giipdb/docs/TEST_SERVER_INSTALLATION.md) - 테스트 환경 구축

### Security
- [Security Checklist](../giipdb/docs/SECURITY_CHECKLIST.md) - 보안 점검 항목

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
# This controls how often the agent checks for new commands
giipagentdelay="60"

# API v2 (Recommended) - PowerShell-based, faster and stable
apiaddrv2="https://giipfaw.azurewebsites.net/api/giipApiSk2"
apiaddrcode="YOUR_AZURE_FUNCTION_KEY_HERE"

# API v1 (Legacy) - ASP Classic-based
# Only used if apiaddrv2 is not set
apiaddr="https://giipasp.azurewebsites.net"
```

**API Version Comparison:**
| Feature | v1 (Legacy) | v2 (Recommended) |
|---------|-------------|------------------|
| Engine | ASP Classic | PowerShell |
| Speed | Slower | Faster |
| Stability | Moderate | High |
| Auth | SK only | SK + Function Code |
| Endpoint | giipasp.azurewebsites.net | giipfaw.azurewebsites.net |

> **💡 TIP**: Always use `apiaddrv2` for better performance and reliability!

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
3. Installs required packages (dos2unix, wget, curl, jq)
4. Registers cron jobs:
   - **CQE Agent** (giipCQE.sh): Every 5 minutes - Command Queue Execution 🚀 **NEW**
   - Auto-Discovery: Every 5 minutes
   - Daily Recycle: 23:59 daily
5. Sets executable permissions for scripts

---

## 🚀 CQE (Command Queue Execution) System v2.0 **NEW**

### Overview

CQE는 중앙 서버에서 원격 서버로 스크립트를 배포하고 실행 결과를 자동 수집하는 시스템입니다.

**주요 기능**:
- ✅ 원격 스크립트 실행
- ✅ 실행 결과 자동 수집 (tKVS 저장)
- ✅ 타임아웃 제어 (기본 300초)
- ✅ 보안 검증 (위험한 명령어 차단)
- ✅ 에러 처리 및 재시도
- ✅ 상세 로깅

### Quick Start

**1. CQE Agent 실행**
```bash
# 자동 실행 (cron)
*/5 * * * * cd /home/giip/giipAgentLinux && bash giipCQE.sh

# 수동 실행
bash giipCQE.sh

# 테스트 모드
bash giipCQE.sh --test

# 한 번만 실행
bash giipCQE.sh --once
```

**2. 스크립트 등록 및 실행**

```sql
-- Step 1: 스크립트 마스터 등록 (tMgmtScript)
INSERT INTO tMgmtScript (usn, msName, msDetail, msBody, msRegdt, msType, category, enabled)
VALUES (
    1,
    'disk_check.sh',
    '디스크 사용량 체크',
    '#!/bin/bash
df -h
du -sh /var/log/*',
    GETDATE(),
    'bash',
    'monitoring',
    1
)
-- 반환된 msSn 기억 (예: 100)

-- Step 2: 서버에 스케줄 등록 (tMgmtScriptList)
INSERT INTO tMgmtScriptList (
    msSn, usn, csn, lssn, interval, active, repeat, regdate, script_type
)
VALUES (
    100,        -- msSn (위에서 생성한 스크립트)
    1,          -- usn (사용자)
    70324,      -- csn (회사)
    71028,      -- lssn (대상 서버)
    60,         -- interval (60분마다 실행)
    1,          -- active (활성화)
    2,          -- repeat (2=반복, 1=한번만)
    GETDATE(),
    'bash'
)

-- Step 3: 즉시 실행 (선택사항)
UPDATE tMgmtScriptList
SET q_flag = 1
WHERE mslSn = 12345  -- 위에서 생성된 mslSn
```

**3. 실행 결과 조회**

```bash
# CLI로 조회
./giipCQECtrl.sh result 71028

# 또는 SQL로 조회
SELECT TOP 10
    kRegdt,
    JSON_VALUE(kValue, '$.script_name') AS script_name,
    JSON_VALUE(kValue, '$.status') AS status,
    JSON_VALUE(kValue, '$.exit_code') AS exit_code,
    JSON_VALUE(kValue, '$.duration_seconds') AS duration,
    JSON_VALUE(kValue, '$.stdout') AS output
FROM tKVS
WHERE kType = 'lssn'
  AND kKey = '71028'
  AND kFactor = 'cqeresult'
ORDER BY kRegdt DESC
```

### CQE Control Utility

```bash
# 스케줄 목록 조회
./giipCQECtrl.sh list

# 서버 상태 확인
./giipCQECtrl.sh status 71028

# 즉시 실행
./giipCQECtrl.sh execute 12345

# 최근 결과 조회
./giipCQECtrl.sh result 71028

# 로그 조회
./giipCQECtrl.sh logs 71028
```

### Architecture

```
관리자 → tMgmtScript → tMgmtScriptList → tMgmtQue → giipCQE.sh → 실행 → tKVS
   (등록)     (마스터)      (스케줄)        (큐)      (Agent)    (결과저장)
```

**자세한 내용**: [CQE_ARCHITECTURE.md](../giipAgentAdmLinux/docs/CQE_ARCHITECTURE.md)

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
*/5 * * * * cd /opt/giipAgentLinux; bash --login -c 'sh /opt/giipAgentLinux/git-auto-sync.sh' >> /var/log/giip/git_auto_sync_cron.log 2>&1
```

### Check Git Auto-Sync
```bash
# Check git-auto-sync is registered
crontab -l | grep git-auto-sync

# Test manual execution
cd /opt/giipAgentLinux
bash git-auto-sync.sh

# Check log
tail -f /var/log/giip/git_auto_sync_$(date +%Y%m%d).log
```

**What git-auto-sync.sh does:**
1. Pulls latest agent code from GitHub (Pull-Only, no push)
2. If changes pulled → automatically runs `giip-auto-discover.sh`
3. Auto-discovery collects server info and sends to Azure Function
4. Network data saved to `tLSvrNIC` via `pApiAgentAutoRegisterbyAK`

**Benefits:**
- ✅ Agents automatically update to latest version
- ✅ Server inventory automatically updated after code changes
- ✅ No manual intervention required
- ✅ Pull-Only mode prevents accidental credential exposure

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

## 📊 Execution Tracking (v3.0)

### Overview

giipAgent3.sh automatically logs all execution activities to KVS (Key-Value Storage) with factor **"giipagent"** for complete audit trail and troubleshooting.

**Tracked Events**:
- Agent startup/shutdown
- Queue checks (every minute)
- Script executions (success/failure)
- Gateway initialization
- Heartbeat triggers
- Database queries
- Remote server executions
- All errors

### Query Execution History

**SQL Query**:
```sql
SELECT TOP 100
    kRegdt,
    JSON_VALUE(kValue, '$.event_type') AS event_type,
    JSON_VALUE(kValue, '$.timestamp') AS timestamp,
    JSON_VALUE(kValue, '$.lssn') AS lssn,
    JSON_VALUE(kValue, '$.hostname') AS hostname,
    JSON_VALUE(kValue, '$.mode') AS mode,
    JSON_VALUE(kValue, '$.version') AS version,
    kValue AS details
FROM tKVS
WHERE kType = 'lssn'
  AND kKey = '71174'  -- Your LSSN
  AND kFactor = 'giipagent'
ORDER BY kRegdt DESC
```

**Filter by Event Type**:
```sql
-- Queue checks only
WHERE kFactor = 'giipagent'
  AND JSON_VALUE(kValue, '$.event_type') = 'queue_check'

-- Errors only
WHERE kFactor = 'giipagent'
  AND JSON_VALUE(kValue, '$.event_type') = 'error'

-- Script executions only
WHERE kFactor = 'giipagent'
  AND JSON_VALUE(kValue, '$.event_type') = 'script_execution'
```

### Event Types

| Event Type | Description | Normal Mode | Gateway Mode |
|-----------|-------------|-------------|--------------|
| `startup` | Agent started | ✅ | ✅ |
| `shutdown` | Agent stopped | ✅ | ✅ |
| `queue_check` | Queue API call result | ✅ | ✅ |
| `script_execution` | Script executed | ✅ | ✅ |
| `gateway_init` | Gateway initialization | ❌ | ✅ |
| `heartbeat` | Heartbeat triggered | ❌ | ✅ |
| `db_query` | Database query executed | ❌ | ✅ |
| `remote_execution` | Remote server processed | ❌ | ✅ |
| `error` | Any error occurred | ✅ | ✅ |

### Example: Troubleshoot Failed Script

```sql
-- Step 1: Find failed script executions
SELECT 
    kRegdt,
    JSON_VALUE(kValue, '$.details.exit_code') AS exit_code,
    JSON_VALUE(kValue, '$.details.execution_time_seconds') AS duration,
    JSON_VALUE(kValue, '$.details.script_type') AS script_type
FROM tKVS
WHERE kFactor = 'giipagent'
  AND JSON_VALUE(kValue, '$.event_type') = 'script_execution'
  AND JSON_VALUE(kValue, '$.details.exit_code') != '0'
ORDER BY kRegdt DESC

-- Step 2: Check errors around that time
SELECT 
    kRegdt,
    JSON_VALUE(kValue, '$.details.error_type') AS error_type,
    JSON_VALUE(kValue, '$.details.error_message') AS error_message,
    JSON_VALUE(kValue, '$.details.context') AS context
FROM tKVS
WHERE kFactor = 'giipagent'
  AND JSON_VALUE(kValue, '$.event_type') = 'error'
  AND kRegdt >= '2025-11-08 16:00:00'
ORDER BY kRegdt DESC
```

For complete specification, see [docs/GIIPAGENT3_SPECIFICATION.md](docs/GIIPAGENT3_SPECIFICATION.md).

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

### Database Performance Monitoring (DPA)

The agent includes database performance monitoring scripts:

| Script | Purpose | Configuration |
|--------|---------|---------------|
| `dpa-put-mssql.sh` | MS SQL Server session/query monitoring | Reads from `giipAgent.cnf` |
| `dpa-put-mysql.sh` | MySQL/MariaDB monitoring | Reads from `giipAgent.cnf` |

**Important Configuration Mapping:**

```bash
# giipAgent.cnf - Database Monitoring Section
sk="your-secret-key"           # → USER_TOKEN (API authentication)
lssn="12345"                   # → K_KEY (server identifier)
apiaddrv2="https://..."        # → KVS_ENDPOINT
apiaddrcode="function-code"    # → FUNCTION_CODE
```

**Key Points:**
- ⚠️ **kKey = lssn** (서버 식별자는 항상 lssn 값을 사용)
- ⚠️ **K_TYPE = "lssn"** (기본값, 변경하지 말 것)
- These scripts collect active sessions, CPU usage, slow queries
- Data is uploaded to KVS (Key-Value Storage) every 5 minutes
- Failed uploads are logged to ErrorLogs table

**Schedule (crontab):**
```bash
# Every 5 minutes
*/5 * * * * /home/giip/giipAgentLinux/giipscripts/dpa-put-mssql.sh >> /var/log/giip/dpa_mssql.log 2>&1
```

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

## �️ Utility Scripts

### Performance Monitoring & Diagnostics

GIIP Agent includes several utility scripts for server monitoring and troubleshooting:

#### 1. collect-perfmon.sh
**Purpose**: Collect basic Linux server performance metrics and save to KVS

**Metrics Collected**:
- CPU usage percentage
- Memory usage (total/used/available)
- Disk usage (root partition)
- Network stats (RX/TX bytes)
- Load average (1/5/15 min)
- Process count (total/running/sleeping)
- System uptime

**Usage**:
```bash
bash collect-perfmon.sh

# Cron (every 5 minutes)
*/5 * * * * /path/to/giipAgentLinux/collect-perfmon.sh
```

**KVS Storage**: `kFactor: perfmon`

**Query Data**:
```powershell
pwsh query-kvs.ps1 -kType lssn -kKey 71174 -kFactor perfmon -Top 10
```

---

#### 2. collect-server-diagnostics.sh
**Purpose**: Comprehensive server diagnostics with health scoring (8 separate metrics)

**Metrics Collected** (saved as separate KVS entries):

| kFactor | Description |
|---------|-------------|
| `load_overview` | Load average, CPU usage, uptime |
| `top_cpu` | Top 5 CPU consuming processes |
| `top_memory` | Top 5 memory consuming processes |
| `memory_status` | RAM and swap usage details |
| `disk_usage` | Root partition usage |
| `network_status` | Connection states, interface stats |
| `process_info` | Process counts by state |
| `health_summary` | **Overall health score (0-100)** |

**Health Scoring System**:
- Starts at 100 points
- Deducts for high CPU/Memory/Disk usage
- Deducts for zombie processes
- Deducts for high load average
- **Status**: healthy (80+), warning (60-79), critical (<60)

**Usage**:
```bash
bash collect-server-diagnostics.sh

# Cron (every 10 minutes)
*/10 * * * * /path/to/giipAgentLinux/collect-server-diagnostics.sh
```

**Query Data**:
```powershell
# Check health score
pwsh query-kvs.ps1 -kType lssn -kKey 71174 -kFactor health_summary -Top 10

# Check top CPU processes
pwsh query-kvs.ps1 -kType lssn -kKey 71174 -kFactor top_cpu -Top 5

# Check memory status
pwsh query-kvs.ps1 -kType lssn -kKey 71174 -kFactor memory_status -Top 5
```

---

#### 3. diagnose-server-load.sh
**Purpose**: Quick diagnostic tool to identify high server load causes

**Diagnostic Sections**:
1. System load overview (Load avg, CPU, uptime)
2. Top 10 CPU consuming processes
3. Top 10 memory consuming processes
4. Memory status & swap usage
5. Disk I/O statistics
6. Network connections by state
7. Process count (total/running/zombie)
8. Multiple script instances detection
9. Recent system errors from logs
10. Quick recommendations & alerts

**Usage**:
```bash
# View on screen
bash diagnose-server-load.sh

# Save to file
bash diagnose-server-load.sh > load_report_$(date +%Y%m%d_%H%M%S).txt
```

**When to Use**:
- Server is slow or unresponsive
- Investigating performance issues
- Troubleshooting high load
- Identifying resource bottlenecks

---

#### 4. check-process-flood.sh
**Purpose**: Detect and auto-remediate process flooding (e.g., postfix, sendmail)

**Monitored Services**:
- postfix, sendmail
- apache2, httpd, nginx
- mysql, mariadb
- (customizable list)

**Thresholds**:
- **WARNING**: 50+ processes
- **CRITICAL**: 100+ processes

**Auto-Remediation** (for CRITICAL):
1. `systemctl stop <service>`
2. `pkill <service>` (SIGTERM)
3. `pkill -9 <service>` (SIGKILL if needed)
4. `systemctl disable <service>`
5. `systemctl mask <service>`

**Usage**:
```bash
bash check-process-flood.sh

# Cron (every 10 minutes)
*/10 * * * * /path/to/giipAgentLinux/check-process-flood.sh
```

**Exit Codes**:
- `0`: OK - No flooding detected
- `1`: WARNING - Manual action required
- `2`: CRITICAL - Auto-remediation performed

**KVS Storage**: `kFactor: process_flood_check`

**Real Case Example**:
```
🚨 CRITICAL: postfix has 8537 processes
🔧 AUTO-REMEDIATION: Starting automatic cleanup...
✅ SUCCESS: All postfix processes removed
```

---

## 📚 Additional Resources

- **GIIP Portal**: https://giipasp.azurewebsites.net
- **Documentation**: [AGENT_INSTALLATION_GUIDE](../giipdb/docs/AGENT_INSTALLATION_GUIDE.md)
- **Architecture**: [GIIP_ARCHITECTURE](../giipdb/docs/GIIP_ARCHITECTURE.md)
- **Auto-Discovery Design**: [AUTO_DISCOVERY_DESIGN](../giipdb/docs/AUTO_DISCOVERY_DESIGN.md)
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

