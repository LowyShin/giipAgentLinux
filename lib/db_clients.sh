#!/bin/bash
# giipAgent Database Clients Library
# Version: 2.00
# Date: 2025-01-10
# Purpose: Install and check database clients for Gateway mode

# ============================================================================
# Sudo Check Functions
# ============================================================================

# Check if user has sudo privileges
has_sudo() {
	if [ "$EUID" -eq 0 ]; then
		# Running as root
		return 0
	fi
	
	if sudo -n true 2>/dev/null; then
		# Has passwordless sudo
		return 0
	fi
	
	# No sudo access
	return 1
}

# Run command with sudo if available, otherwise try without
run_with_sudo() {
	if has_sudo; then
		sudo "$@"
	else
		"$@"
	fi
}

# ============================================================================
# SSH/Remote Access Functions
# ============================================================================

# Function: Check and install sshpass if needed
check_sshpass() {
	if command -v sshpass &> /dev/null; then
		echo "[Gateway] sshpass is already installed"
		return 0
	fi
	
	if ! has_sudo; then
		echo "[Gateway] ⚠️  sshpass not found and no sudo access"
		echo "[Gateway] Please install manually: apt-get install sshpass (Debian/Ubuntu) or yum install sshpass (RHEL/CentOS)"
		return 1
	fi
	
	echo "[Gateway] sshpass not found, installing automatically..."
	
	if [ -f /etc/debian_version ]; then
		# Debian/Ubuntu
		echo "[Gateway] Detected Debian/Ubuntu"
		run_with_sudo apt-get update -qq
		run_with_sudo apt-get install -y sshpass
	elif [ -f /etc/redhat-release ]; then
		# CentOS/RHEL
		echo "[Gateway] Detected CentOS/RHEL"
		if ! rpm -q epel-release &>/dev/null; then
			echo "[Gateway] Installing EPEL repository..."
			run_with_sudo yum install -y epel-release
		fi
		run_with_sudo yum install -y sshpass
	else
		echo "[Gateway] Error: Unsupported OS for auto-install"
		echo "[Gateway] Please install sshpass manually"
		return 1
	fi
	
	if command -v sshpass &> /dev/null; then
		echo "[Gateway] ✅ sshpass installed successfully"
		return 0
	else
		echo "[Gateway] ❌ Failed to install sshpass"
		return 1
	fi
}

# ============================================================================
# Python Environment Functions
# ============================================================================

# Function: Check Python environment and install if needed
check_python_environment() {
	echo "[Gateway-Python] Checking Python environment..."
	
	# Check Python3
	if ! command -v python3 &> /dev/null; then
		if ! has_sudo; then
			echo "[Gateway-Python] ⚠️  Python3 not found and no sudo access"
			echo "[Gateway-Python] Please install manually: apt-get install python3 python3-pip"
			return 1
		fi
		
		echo "[Gateway-Python] Python3 not found, installing..."
		if [ -f /etc/debian_version ]; then
			run_with_sudo apt-get update -qq
			run_with_sudo apt-get install -y python3 python3-pip
		elif [ -f /etc/redhat-release ]; then
			run_with_sudo yum install -y python3 python3-pip
		else
			echo "[Gateway-Python] ❌ Unsupported OS, please install Python3 manually"
			return 1
		fi
	fi
	
	# Check pip3
	if ! command -v pip3 &> /dev/null; then
		if ! has_sudo; then
			echo "[Gateway-Python] ⚠️  pip3 not found and no sudo access"
			echo "[Gateway-Python] Please install manually: apt-get install python3-pip"
			return 1
		fi
		
		echo "[Gateway-Python] pip3 not found, installing..."
		if [ -f /etc/debian_version ]; then
			run_with_sudo apt-get install -y python3-pip
		elif [ -f /etc/redhat-release ]; then
			run_with_sudo yum install -y python3-pip
		fi
	fi
	
	# Verify installation
	if command -v python3 &> /dev/null && command -v pip3 &> /dev/null; then
		local python_version=$(python3 --version 2>&1)
		echo "[Gateway-Python] ✅ Python environment ready: ${python_version}"
		return 0
	else
		echo "[Gateway-Python] ❌ Failed to setup Python environment"
		return 1
	fi
}

# ============================================================================
# MySQL/MariaDB Functions
# ============================================================================

# Function: Check and install mysql client if needed
check_mysql_client() {
	if command -v mysql &> /dev/null; then
		echo "[Gateway-MySQL] mysql client is already installed"
		return 0
	fi
	
	if ! has_sudo; then
		echo "[Gateway-MySQL] ⚠️  mysql client not found and no sudo access"
		echo "[Gateway-MySQL] Please install manually: apt-get install mysql-client (Debian/Ubuntu) or yum install mysql (RHEL/CentOS)"
		return 1
	fi
	
	echo "[Gateway-MySQL] mysql client not found, installing automatically..."
	
	if [ -f /etc/debian_version ]; then
		# Debian/Ubuntu
		echo "[Gateway-MySQL] Detected Debian/Ubuntu"
		run_with_sudo apt-get update -qq
		run_with_sudo apt-get install -y mysql-client
	elif [ -f /etc/redhat-release ]; then
		# CentOS/RHEL
		echo "[Gateway-MySQL] Detected CentOS/RHEL"
		run_with_sudo yum install -y mysql
	else
		echo "[Gateway-MySQL] Error: Unsupported OS for auto-install"
		echo "[Gateway-MySQL] Please install mysql-client manually"
		return 1
	fi
	
	if command -v mysql &> /dev/null; then
		echo "[Gateway-MySQL] ✅ mysql client installed successfully"
		return 0
	else
		echo "[Gateway-MySQL] ❌ Failed to install mysql client"
		return 1
	fi
}

# ============================================================================
# PostgreSQL Functions
# ============================================================================

# Function: Check and install PostgreSQL client if needed
check_psql_client() {
	if command -v psql &> /dev/null; then
		echo "[Gateway-PostgreSQL] psql client is already installed"
		return 0
	fi
	
	if ! has_sudo; then
		echo "[Gateway-PostgreSQL] ⚠️  psql client not found and no sudo access"
		echo "[Gateway-PostgreSQL] Please install manually: apt-get install postgresql-client (Debian/Ubuntu) or yum install postgresql (RHEL/CentOS)"
		return 1
	fi
	
	echo "[Gateway-PostgreSQL] psql client not found, installing automatically..."
	
	if [ -f /etc/debian_version ]; then
		# Debian/Ubuntu
		echo "[Gateway-PostgreSQL] Detected Debian/Ubuntu"
		run_with_sudo apt-get update -qq
		run_with_sudo apt-get install -y postgresql-client
	elif [ -f /etc/redhat-release ]; then
		# CentOS/RHEL
		echo "[Gateway-PostgreSQL] Detected CentOS/RHEL"
		run_with_sudo yum install -y postgresql
	else
		echo "[Gateway-PostgreSQL] Error: Unsupported OS for auto-install"
		return 1
	fi
	
	if command -v psql &> /dev/null; then
		echo "[Gateway-PostgreSQL] ✅ psql client installed successfully"
		return 0
	else
		echo "[Gateway-PostgreSQL] ❌ Failed to install psql client"
		return 1
	fi
}

# ============================================================================
# MSSQL Functions
# ============================================================================

# Function: Check and install MSSQL client (pyodbc)
check_mssql_client() {
	echo "[Gateway-MSSQL] Checking MSSQL client (Python pyodbc)..."
	
	# First ensure Python is available
	check_python_environment || return 1
	
	# Check if pyodbc is installed
	if python3 -c "import pyodbc" 2>/dev/null; then
		echo "[Gateway-MSSQL] ✅ pyodbc is already installed"
		return 0
	fi
	
	if ! has_sudo; then
		echo "[Gateway-MSSQL] ⚠️  pyodbc not found and no sudo access"
		echo "[Gateway-MSSQL] Please install manually:"
		echo "[Gateway-MSSQL]   1. Install ODBC driver: https://docs.microsoft.com/en-us/sql/connect/odbc/linux-mac/installing-the-microsoft-odbc-driver-for-sql-server"
		echo "[Gateway-MSSQL]   2. pip3 install --user pyodbc"
		# Try user-level install
		echo "[Gateway-MSSQL] Attempting user-level pyodbc install..."
		pip3 install --user pyodbc --quiet 2>/dev/null
		if python3 -c "import pyodbc" 2>/dev/null; then
			echo "[Gateway-MSSQL] ✅ pyodbc installed in user directory"
			return 0
		fi
		return 1
	fi
	
	echo "[Gateway-MSSQL] pyodbc not found, installing..."
	
	# Install ODBC driver first
	if [ -f /etc/debian_version ]; then
		echo "[Gateway-MSSQL] Installing Microsoft ODBC Driver for SQL Server (Ubuntu)..."
		# Add Microsoft repository
		curl -s https://packages.microsoft.com/keys/microsoft.asc | run_with_sudo apt-key add - 2>/dev/null
		local ubuntu_version=$(lsb_release -rs)
		curl -s https://packages.microsoft.com/config/ubuntu/${ubuntu_version}/prod.list | \
			run_with_sudo tee /etc/apt/sources.list.d/msprod.list > /dev/null
		
		run_with_sudo apt-get update -qq
		run_with_sudo sh -c "ACCEPT_EULA=Y apt-get install -y msodbcsql17 unixodbc-dev" 2>/dev/null
		
	elif [ -f /etc/redhat-release ]; then
		echo "[Gateway-MSSQL] Installing Microsoft ODBC Driver for SQL Server (CentOS/RHEL)..."
		curl -s https://packages.microsoft.com/config/rhel/8/prod.repo | \
			run_with_sudo tee /etc/yum.repos.d/msprod.repo > /dev/null
		run_with_sudo sh -c "ACCEPT_EULA=Y yum install -y msodbcsql17 unixODBC-devel" 2>/dev/null
	fi
	
	# Install Python pyodbc package
	echo "[Gateway-MSSQL] Installing pyodbc Python package..."
	
	# Upgrade pip and setuptools first to avoid build errors
	python3 -m pip install --upgrade pip setuptools --quiet 2>/dev/null || true
	
	# Install pyodbc with compiler flags
	pip3 install pyodbc --quiet 2>/dev/null
	
	# Verify installation
	if python3 -c "import pyodbc" 2>/dev/null; then
		echo "[Gateway-MSSQL] ✅ pyodbc installed successfully"
		return 0
	else
		echo "[Gateway-MSSQL] ⚠️  pyodbc installation may have failed, but will try at query time"
		return 0  # Don't fail completely
	fi
}

# ============================================================================
# Oracle Functions
# ============================================================================

# Function: Check and install Oracle client (cx_Oracle)
check_oracle_client() {
	echo "[Gateway-Oracle] Checking Oracle client (Python cx_Oracle)..."
	
	# First ensure Python is available
	check_python_environment || return 1
	
	# Check if cx_Oracle is installed
	if python3 -c "import cx_Oracle" 2>/dev/null; then
		echo "[Gateway-Oracle] ✅ cx_Oracle is already installed"
		return 0
	fi
	
	echo "[Gateway-Oracle] cx_Oracle not found, installing..."
	
	# Install Python cx_Oracle package
	echo "[Gateway-Oracle] Installing cx_Oracle Python package..."
	pip3 install cx_Oracle --quiet
	
	# Verify installation
	if python3 -c "import cx_Oracle" 2>/dev/null; then
		echo "[Gateway-Oracle] ✅ cx_Oracle installed successfully"
		echo "[Gateway-Oracle] ⚠️  Note: Oracle Instant Client is still required"
		echo "[Gateway-Oracle]    Download from: https://www.oracle.com/database/technologies/instant-client/downloads.html"
		return 0
	else
		echo "[Gateway-Oracle] ⚠️  cx_Oracle installation may have failed"
		echo "[Gateway-Oracle] ⚠️  Oracle Instant Client is required for Oracle connections"
		echo "[Gateway-Oracle]    Download from: https://www.oracle.com/database/technologies/instant-client/downloads.html"
		return 0  # Don't fail completely
	fi
}

# ============================================================================
# Main Check Function
# ============================================================================

# Function: Check all DB clients
check_db_clients() {
	echo "[Gateway-DB] Checking database clients..."
	
	local mysql_ok=0
	local psql_ok=0
	local mssql_ok=0
	local oracle_ok=0
	
	# Python environment (required for MSSQL and Oracle)
	check_python_environment
	
	# MySQL/MariaDB
	check_mysql_client && mysql_ok=1
	
	# PostgreSQL
	check_psql_client && psql_ok=1
	
	# MSSQL (using Python pyodbc)
	check_mssql_client && mssql_ok=1
	
	# Oracle (using Python cx_Oracle)
	check_oracle_client && oracle_ok=1
	
	echo "[Gateway-DB] ================================================"
	echo "[Gateway-DB] Client availability summary:"
	echo "[Gateway-DB]   MySQL/MariaDB: $([ $mysql_ok -eq 1 ] && echo '✅ Available' || echo '❌ Not available')"
	echo "[Gateway-DB]   PostgreSQL:    $([ $psql_ok -eq 1 ] && echo '✅ Available' || echo '❌ Not available')"
	echo "[Gateway-DB]   MSSQL:         $([ $mssql_ok -eq 1 ] && echo '✅ Available (pyodbc)' || echo '⚠️  Install pyodbc')"
	echo "[Gateway-DB]   Oracle:        $([ $oracle_ok -eq 1 ] && echo '✅ Available (cx_Oracle)' || echo '⚠️  Install cx_Oracle + Instant Client')"
	echo "[Gateway-DB] ================================================"
	
	return 0
}

# ============================================================================
# Export Functions
# ============================================================================

export -f check_sshpass
export -f check_python_environment
export -f check_mysql_client
export -f check_psql_client
export -f check_mssql_client
export -f check_oracle_client
export -f check_db_clients
