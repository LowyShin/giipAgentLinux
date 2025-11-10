#!/bin/bash
# giipAgent Ver. 2.0
sv="2.00"
# Written by Lowy Shin at 20140922
# Updated to use giipApiSk2 (PowerShell API) at 20250104
# Supported OS : MacOS, CentOS, Ubuntu, Some Linux
# 190611 Lowy, Change agent download method to git repository.
# 20251104 Lowy, Add Gateway mode support with auto-dependency installation
# 20250104 Lowy, Migrate to giipApiSk2 (PowerShell-based, faster and more stable)

# Usable giip variables =========
# {{today}} : Replace today to "YYYYMMDD"

# User Variables ===============================================
. ../giipAgent.cnf

if [ "${giipagentdelay}" = "" ];then
	giipagentdelay="60"
fi

# Gateway mode - AUTO-DETECTED from DB (DO NOT SET MANUALLY!)
# Will be fetched from tLSvr.is_gateway via API
gateway_mode=""  # Empty = not yet fetched

# Self Check - Skip for single execution mode (no loop)
# cntgiip=`ps aux | grep giipAgent2.sh | grep -v grep | wc -l`
cntgiip=1  # Always assume single process

# ============================================================================
# Gateway Mode Functions
# ============================================================================

# Function: Check and install sshpass if needed
check_sshpass() {
	if command -v sshpass &> /dev/null; then
		echo "[Gateway] sshpass is already installed"
		return 0
	fi
	
	echo "[Gateway] sshpass not found, installing automatically..."
	
	if [ -f /etc/debian_version ]; then
		# Debian/Ubuntu
		echo "[Gateway] Detected Debian/Ubuntu"
		apt-get update -qq
		apt-get install -y sshpass
	elif [ -f /etc/redhat-release ]; then
		# CentOS/RHEL
		echo "[Gateway] Detected CentOS/RHEL"
		if ! rpm -q epel-release &>/dev/null; then
			echo "[Gateway] Installing EPEL repository..."
			yum install -y epel-release
		fi
		yum install -y sshpass
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

# Function: Check Python environment and install if needed
check_python_environment() {
	echo "[Gateway-Python] Checking Python environment..."
	
	# Check Python3
	if ! command -v python3 &> /dev/null; then
		echo "[Gateway-Python] Python3 not found, installing..."
		if [ -f /etc/debian_version ]; then
			sudo apt-get update -qq
			sudo apt-get install -y python3 python3-pip
		elif [ -f /etc/redhat-release ]; then
			sudo yum install -y python3 python3-pip
		else
			echo "[Gateway-Python] ❌ Unsupported OS, please install Python3 manually"
			return 1
		fi
	fi
	
	# Check pip3
	if ! command -v pip3 &> /dev/null; then
		echo "[Gateway-Python] pip3 not found, installing..."
		if [ -f /etc/debian_version ]; then
			sudo apt-get install -y python3-pip
		elif [ -f /etc/redhat-release ]; then
			sudo yum install -y python3-pip
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

# Function: Check and install mysql client if needed
check_mysql_client() {
	if command -v mysql &> /dev/null; then
		echo "[Gateway-MySQL] mysql client is already installed"
		return 0
	fi
	
	echo "[Gateway-MySQL] mysql client not found, installing automatically..."
	
	if [ -f /etc/debian_version ]; then
		# Debian/Ubuntu
		echo "[Gateway-MySQL] Detected Debian/Ubuntu"
		apt-get update -qq
		apt-get install -y mysql-client
	elif [ -f /etc/redhat-release ]; then
		# CentOS/RHEL
		echo "[Gateway-MySQL] Detected CentOS/RHEL"
		yum install -y mysql
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

# Function: Check and install PostgreSQL client if needed
check_psql_client() {
	if command -v psql &> /dev/null; then
		echo "[Gateway-PostgreSQL] psql client is already installed"
		return 0
	fi
	
	echo "[Gateway-PostgreSQL] psql client not found, installing automatically..."
	
	if [ -f /etc/debian_version ]; then
		# Debian/Ubuntu
		echo "[Gateway-PostgreSQL] Detected Debian/Ubuntu"
		apt-get update -qq
		apt-get install -y postgresql-client
	elif [ -f /etc/redhat-release ]; then
		# CentOS/RHEL
		echo "[Gateway-PostgreSQL] Detected CentOS/RHEL"
		yum install -y postgresql
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
	
	echo "[Gateway-MSSQL] pyodbc not found, installing..."
	
	# Install ODBC driver first
	if [ -f /etc/debian_version ]; then
		echo "[Gateway-MSSQL] Installing Microsoft ODBC Driver for SQL Server (Ubuntu)..."
		# Add Microsoft repository
		curl -s https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add - 2>/dev/null
		local ubuntu_version=$(lsb_release -rs)
		curl -s https://packages.microsoft.com/config/ubuntu/${ubuntu_version}/prod.list | \
			sudo tee /etc/apt/sources.list.d/msprod.list > /dev/null
		
		sudo apt-get update -qq
		sudo ACCEPT_EULA=Y apt-get install -y msodbcsql17 unixodbc-dev 2>/dev/null
		
	elif [ -f /etc/redhat-release ]; then
		echo "[Gateway-MSSQL] Installing Microsoft ODBC Driver for SQL Server (CentOS/RHEL)..."
		sudo curl -s https://packages.microsoft.com/config/rhel/8/prod.repo | \
			sudo tee /etc/yum.repos.d/msprod.repo > /dev/null
		sudo ACCEPT_EULA=Y yum install -y msodbcsql17 unixODBC-devel 2>/dev/null
	fi
	
	# Install Python pyodbc package
	echo "[Gateway-MSSQL] Installing pyodbc Python package..."
	pip3 install pyodbc --quiet
	
	# Verify installation
	if python3 -c "import pyodbc" 2>/dev/null; then
		echo "[Gateway-MSSQL] ✅ pyodbc installed successfully"
		return 0
	else
		echo "[Gateway-MSSQL] ⚠️  pyodbc installation may have failed, but will try at query time"
		return 0  # Don't fail completely
	fi
}

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

# Function: Sync servers from database
sync_gateway_servers() {
	local output_file="${gateway_serverlist}"
	
	echo "[Gateway] Fetching server list from GIIP API..."
	
	# Use GIIP API to get server list (using giipApiSk2 - PowerShell-based)
	local temp_file="/tmp/gateway_servers_$$.json"
	
	# Build API request (using giipApiSk2 endpoint with text parameter)
	local api_url="${apiaddrv2}"
	if [ -n "$apiaddrcode" ]; then
		api_url="${api_url}?code=${apiaddrcode}"
	fi
	
	local text="GatewayRemoteServerListForAgent ${lssn}"
	
	# Fetch from API
	wget -O "$temp_file" \
		--post-data="text=${text}&token=${sk}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"$api_url" \
		--no-check-certificate -q 2>&1
	
	if [ ! -s "$temp_file" ]; then
		echo "[Gateway] ⚠️  Failed to fetch from API, using existing CSV"
		rm -f "$temp_file"
		return 0
	fi
	
	# Check for error response
	local err_check=$(cat "$temp_file" | grep -i "rstval.*40[0-9]")
	if [ -n "$err_check" ]; then
		echo "[Gateway] ⚠️  API error response, using existing CSV"
		cat "$temp_file" | head -5
		rm -f "$temp_file"
		return 0
	fi
	
	# Parse JSON and create CSV
	# Expected JSON format: [{"hostname":"server01","lssn":1001,"ssh_host":"192.168.1.10",...}]
	
	# Create CSV header
	cat > "$output_file" << EOF
# Auto-generated from GIIP API at $(date '+%Y-%m-%d %H:%M:%S')
# Gateway LSSN: ${lssn}
# DO NOT EDIT - This file is regenerated from Web UI settings
# hostname,lssn,ssh_host,ssh_user,ssh_port,ssh_key_path,ssh_password,os_info,enabled
EOF
	
	# Simple JSON parsing (for arrays of objects)
	# Extract each server object and convert to CSV
	cat "$temp_file" | \
		grep -o '{[^}]*}' | \
		while read -r server_json; do
			# Extract fields using grep/sed
			hostname=$(echo "$server_json" | grep -o '"hostname"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			lssn=$(echo "$server_json" | grep -o '"lssn"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
			ssh_host=$(echo "$server_json" | grep -o '"ssh_host"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			ssh_user=$(echo "$server_json" | grep -o '"ssh_user"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			ssh_port=$(echo "$server_json" | grep -o '"ssh_port"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
			ssh_key_path=$(echo "$server_json" | grep -o '"ssh_key_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			ssh_password=$(echo "$server_json" | grep -o '"ssh_password"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			os_info=$(echo "$server_json" | grep -o '"os_info"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			enabled=$(echo "$server_json" | grep -o '"enabled"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
			
			# Write to CSV (skip if hostname is empty)
			if [ -n "$hostname" ] && [ -n "$ssh_host" ]; then
				echo "${hostname},${lssn},${ssh_host},${ssh_user},${ssh_port},${ssh_key_path},${ssh_password},${os_info},${enabled}" >> "$output_file"
			fi
		done
	
	rm -f "$temp_file"
	
	# Set restrictive permissions (contains passwords!)
	chmod 600 "$output_file"
	
	# Count servers
	local server_count=$(grep -v "^#" "$output_file" | grep -v "^$" | wc -l)
	
	if [ $server_count -gt 0 ]; then
		echo "[Gateway] ✅ Fetched $server_count servers from API"
	else
		echo "[Gateway] ⚠️  No servers found in API response"
	fi
	
	return 0
}

# Function: Sync DB queries from API
sync_db_queries() {
	local output_file="${gateway_db_querylist:-/tmp/gateway_db_queries.csv}"
	
	echo "[Gateway-DB] Fetching database query list from GIIP API..."
	
	local temp_file="/tmp/gateway_db_queries_$$.json"
	
	# Build API request (using giipApiSk2)
	local api_url="${apiaddrv2}"
	if [ -n "$apiaddrcode" ]; then
		api_url="${api_url}?code=${apiaddrcode}"
	fi
	
	local text="GatewayDBQueryList ${lssn}"
	
	# Fetch from API
	wget -O "$temp_file" \
		--post-data="text=${text}&token=${sk}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"$api_url" \
		--no-check-certificate -q 2>&1
	
	if [ ! -s "$temp_file" ]; then
		echo "[Gateway-DB] ⚠️  Failed to fetch DB queries from API"
		rm -f "$temp_file"
		return 0
	fi
	
	# Check for error response
	local err_check=$(cat "$temp_file" | grep -i "rstval.*40[0-9]")
	if [ -n "$err_check" ]; then
		echo "[Gateway-DB] ⚠️  API error response"
		rm -f "$temp_file"
		return 0
	fi
	
	# Create CSV header
	cat > "$output_file" << EOF
# Auto-generated DB queries from GIIP API at $(date '+%Y-%m-%d %H:%M:%S')
# Gateway LSSN: ${lssn}
# gmq_sn,target_lssn,target_hostname,db_type,db_host,db_port,db_user,db_password,db_database,db_instance,query_name,query_text,kvs_key_prefix,kvs_value_format,timeout_seconds,should_execute
EOF
	
	# Parse JSON
	cat "$temp_file" | \
		grep -o '{[^}]*}' | \
		while read -r query_json; do
			gmq_sn=$(echo "$query_json" | grep -o '"gmq_sn"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
			target_lssn=$(echo "$query_json" | grep -o '"target_lssn"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
			target_hostname=$(echo "$query_json" | grep -o '"target_hostname"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			db_type=$(echo "$query_json" | grep -o '"db_type"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			db_host=$(echo "$query_json" | grep -o '"db_host"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			db_port=$(echo "$query_json" | grep -o '"db_port"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
			db_user=$(echo "$query_json" | grep -o '"db_user"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			db_password=$(echo "$query_json" | grep -o '"db_password"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			db_database=$(echo "$query_json" | grep -o '"db_database"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			db_instance=$(echo "$query_json" | grep -o '"db_instance"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			query_name=$(echo "$query_json" | grep -o '"query_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			query_text=$(echo "$query_json" | grep -o '"query_text"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			kvs_key_prefix=$(echo "$query_json" | grep -o '"kvs_key_prefix"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			kvs_value_format=$(echo "$query_json" | grep -o '"kvs_value_format"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
			timeout_seconds=$(echo "$query_json" | grep -o '"timeout_seconds"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
			should_execute=$(echo "$query_json" | grep -o '"should_execute"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
			
			# Write to CSV (skip if essential fields are empty)
			if [ -n "$gmq_sn" ] && [ -n "$target_lssn" ] && [ -n "$db_type" ] && [ -n "$db_host" ] && [ -n "$query_text" ]; then
				# Escape commas and quotes in query_text
				query_text=$(echo "$query_text" | sed 's/,/\\,/g' | sed 's/"/\\"/g')
				echo "${gmq_sn},${target_lssn},${target_hostname},${db_type},${db_host},${db_port},${db_user},${db_password},${db_database},${db_instance},${query_name},\"${query_text}\",${kvs_key_prefix},${kvs_value_format},${timeout_seconds},${should_execute}" >> "$output_file"
			fi
		done
	
	rm -f "$temp_file"
	chmod 600 "$output_file"
	
	local query_count=$(grep -v "^#" "$output_file" | grep -v "^$" | wc -l)
	echo "[Gateway-DB] ✅ Fetched ${query_count} database queries from API"
	
	return 0
}

# Function: Execute database query and save to KVS
execute_db_query() {
	local gmq_sn=$1
	local target_lssn=$2
	local db_type=$3
	local db_host=$4
	local db_port=$5
	local db_user=$6
	local db_password=$7
	local db_database=$8
	local db_instance=$9
	local query_text=${10}
	local kvs_key_prefix=${11}
	local kvs_value_format=${12}
	local timeout_seconds=${13}
	
	echo "[Gateway-DB] Executing ${db_type} query for target_lssn=${target_lssn} on ${db_host}:${db_port}"
	echo "[Gateway-DB] Query: ${query_text}"
	
	local result_file="/tmp/db_result_${gmq_sn}_$$.tmp"
	local exit_code=0
	
	# Execute query based on DB type
	case "${db_type}" in
		MySQL|MariaDB)
			if ! command -v mysql &> /dev/null; then
				echo "[Gateway-DB] ❌ MySQL client not available"
				return 1
			fi
			
			local mysql_cmd="mysql -h ${db_host} -P ${db_port} -u ${db_user}"
			[ -n "${db_password}" ] && mysql_cmd="${mysql_cmd} -p${db_password}"
			[ -n "${db_database}" ] && mysql_cmd="${mysql_cmd} ${db_database}"
			
			timeout ${timeout_seconds}s ${mysql_cmd} -e "${query_text}" > "${result_file}" 2>&1
			exit_code=$?
			;;
			
		PostgreSQL)
			if ! command -v psql &> /dev/null; then
				echo "[Gateway-DB] ❌ PostgreSQL client not available"
				return 1
			fi
			
			export PGPASSWORD="${db_password}"
			local psql_cmd="psql -h ${db_host} -p ${db_port} -U ${db_user}"
			[ -n "${db_database}" ] && psql_cmd="${psql_cmd} -d ${db_database}"
			
			timeout ${timeout_seconds}s ${psql_cmd} -c "${query_text}" > "${result_file}" 2>&1
			exit_code=$?
			unset PGPASSWORD
			;;
			
		MSSQL)
			# Use Python helper script for MSSQL
			if ! command -v python3 &> /dev/null; then
				echo "[Gateway-DB] ❌ Python3 not available"
				return 1
			fi
			
			local python_helper="${GIIP_HOME}/giipscripts/db_query_helper.py"
			if [ ! -f "${python_helper}" ]; then
				echo "[Gateway-DB] ❌ Python helper script not found: ${python_helper}"
				return 1
			fi
			
			timeout ${timeout_seconds}s python3 "${python_helper}" \
				--type mssql \
				--host "${db_host}" \
				--port "${db_port}" \
				--user "${db_user}" \
				--password "${db_password}" \
				--database "${db_database}" \
				--query "${query_text}" \
				--output "${result_file}" \
				--timeout ${timeout_seconds}
			exit_code=$?
			;;
			
		Oracle)
			# Use Python helper script for Oracle
			if ! command -v python3 &> /dev/null; then
				echo "[Gateway-DB] ❌ Python3 not available"
				return 1
			fi
			
			local python_helper="${GIIP_HOME}/giipscripts/db_query_helper.py"
			if [ ! -f "${python_helper}" ]; then
				echo "[Gateway-DB] ❌ Python helper script not found: ${python_helper}"
				return 1
			fi
			
			timeout ${timeout_seconds}s python3 "${python_helper}" \
				--type oracle \
				--host "${db_host}" \
				--port "${db_port}" \
				--user "${db_user}" \
				--password "${db_password}" \
				--instance "${db_instance}" \
				--query "${query_text}" \
				--output "${result_file}" \
				--timeout ${timeout_seconds}
			exit_code=$?
			;;
			
		*)
			echo "[Gateway-DB] ❌ Unsupported DB type: ${db_type}"
			return 1
			;;
	esac
	
	# Process result
	if [ ${exit_code} -eq 0 ]; then
		echo "[Gateway-DB] ✅ Query executed successfully"
		
		# Read result
		local result_data=$(cat "${result_file}")
		
		# Format based on kvs_value_format
		local kvs_value=""
		if [ "${kvs_value_format}" = "JSON" ]; then
			# Convert table output to JSON (simple approach)
			kvs_value=$(echo "${result_data}" | awk 'BEGIN{print "["} NR>1{if(NR>2)printf","; printf "{\"data\":\"%s\"}", $0} END{print "]"}')
		else
			# RAW or CSV
			kvs_value="${result_data}"
		fi
		
		# Save to KVS using GIIP API
		local kvs_key="${kvs_key_prefix}${target_lssn}"
		local kvs_type="db_query_result"
		
		echo "[Gateway-DB] Saving to KVS: key=${kvs_key}"
		
		# Call KVS API (using giipApiSk2)
		local api_url="${apiaddrv2}"
		if [ -n "$apiaddrcode" ]; then
			api_url="${api_url}?code=${apiaddrcode}"
		fi
		
		local text="KVSPut kType kKey kFactor"
		local jsondata="{\"kType\":\"${kvs_type}\",\"kKey\":\"${kvs_key}\",\"kFactor\":$(echo "${kvs_value}" | jq -Rs .)}"
		
		wget -O /dev/null \
			--post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
			--header="Content-Type: application/x-www-form-urlencoded" \
			"${api_url}" \
			--no-check-certificate -q 2>&1
		
		if [ $? -eq 0 ]; then
			echo "[Gateway-DB] ✅ Saved to KVS successfully"
		else
			echo "[Gateway-DB] ⚠️  Failed to save to KVS"
		fi
	else
		echo "[Gateway-DB] ❌ Query failed with exit code ${exit_code}"
		cat "${result_file}" | head -10
	fi
	
	rm -f "${result_file}"
	
	return ${exit_code}
}

# Function: Process database queries
process_db_queries() {
	local query_file="${gateway_db_querylist:-/tmp/gateway_db_queries.csv}"
	
	if [ ! -f "${query_file}" ]; then
		echo "[Gateway-DB] No database query file found, skipping"
		return 0
	fi
	
	echo "[Gateway-DB] Processing database queries..."
	
	local processed=0
	local succeeded=0
	local failed=0
	
	# Read CSV (skip comments and header)
	grep -v "^#" "${query_file}" | tail -n +2 | while IFS=',' read -r gmq_sn target_lssn target_hostname db_type db_host db_port db_user db_password db_database db_instance query_name query_text kvs_key_prefix kvs_value_format timeout_seconds should_execute; do
		
		# Skip if should_execute is not 1
		if [ "${should_execute}" != "1" ]; then
			echo "[Gateway-DB] Skipping gmq_sn=${gmq_sn} (not scheduled)"
			# Exit instead of continue (no loop)
		fi
		
		processed=$((processed + 1))
		
		# Remove quotes from query_text
		query_text=$(echo "${query_text}" | sed 's/^"//; s/"$//' | sed 's/\\,/,/g; s/\\"/"/g')
		
		echo ""
		echo "[Gateway-DB] ==== Query ${processed}: ${query_name} (${db_type}) ===="
		
		execute_db_query "${gmq_sn}" "${target_lssn}" "${db_type}" "${db_host}" "${db_port}" "${db_user}" "${db_password}" "${db_database}" "${db_instance}" "${query_text}" "${kvs_key_prefix}" "${kvs_value_format}" "${timeout_seconds}"
		
		if [ $? -eq 0 ]; then
			succeeded=$((succeeded + 1))
		else
			failed=$((failed + 1))
		fi
		
		# Small delay between queries
		sleep 1
	done
	
	echo ""
	echo "[Gateway-DB] ====================================="
	echo "[Gateway-DB] Summary: ${processed} queries processed"
	echo "[Gateway-DB]   Succeeded: ${succeeded}"
	echo "[Gateway-DB]   Failed: ${failed}"
	echo "[Gateway-DB] ====================================="
	
	return 0
}

# Function: Execute command on remote server
execute_remote_command() {
	local remote_host=$1
	local remote_user=$2
	local remote_port=$3
	local ssh_key=$4
	local ssh_password=$5
	local script_file=$6
	
	local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
	
	# Determine authentication method
	if [ -n "${ssh_password}" ]; then
		# Password authentication
		if ! command -v sshpass &> /dev/null; then
			echo "  ❌ sshpass not available"
			return 1
		fi
		
		# Use sshpass
		sshpass -p "${ssh_password}" scp ${ssh_opts} -P ${remote_port} \
		    ${script_file} ${remote_user}@${remote_host}:/tmp/giipTmpScript.sh 2>&1 | head -5
		
		if [ $? -ne 0 ]; then
			echo "  ❌ Failed to copy script (password auth)"
			return 1
		fi
		
		sshpass -p "${ssh_password}" ssh ${ssh_opts} -p ${remote_port} \
		    ${remote_user}@${remote_host} \
		    "chmod +x /tmp/giipTmpScript.sh && /tmp/giipTmpScript.sh && rm -f /tmp/giipTmpScript.sh" 2>&1 | head -20
	elif [ -n "${ssh_key}" ] && [ -f "${ssh_key}" ]; then
		# Key authentication
		scp ${ssh_opts} -i ${ssh_key} -P ${remote_port} \
		    ${script_file} ${remote_user}@${remote_host}:/tmp/giipTmpScript.sh 2>&1 | head -5
		
		if [ $? -ne 0 ]; then
			echo "  ❌ Failed to copy script (key auth)"
			return 1
		fi
		
		ssh ${ssh_opts} -i ${ssh_key} -p ${remote_port} \
		    ${remote_user}@${remote_host} \
		    "chmod +x /tmp/giipTmpScript.sh && /tmp/giipTmpScript.sh && rm -f /tmp/giipTmpScript.sh" 2>&1 | head -20
	else
		echo "  ❌ No authentication method available"
		return 1
	fi
	
	return $?
}

# Function: Get script by mssn (from repository)
get_script_by_mssn() {
	local mssn=$1
	local output_file=$2
	
	echo "[CQE] Fetching script from repository: mssn=$mssn"
	
	local api_url="${apiaddrv2}"
	if [ -n "$apiaddrcode" ]; then
		api_url="${api_url}?code=${apiaddrcode}"
	fi
	
	local text="CQERepoScript ${mssn}"
	
	wget -O "$output_file" \
		--post-data="text=${text}&token=${sk}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"$api_url" \
		--no-check-certificate -q 2>&1
	
	if [ -s "$output_file" ]; then
		dos2unix "$output_file" 2>/dev/null
		echo "[CQE] ✅ Script fetched from repository (mssn=$mssn)"
		return 0
	else
		echo "[CQE] ❌ Failed to fetch script from repository (mssn=$mssn)"
		return 1
	fi
}

# Function: Get queue for specific server
get_remote_queue() {
	local lssn=$1
	local hostname=$2
	local os=$3
	local output_file=$4
	
	# Use giipApiSk2 with POST method (calling pApiCQEQueueGetbySK SP)
	local api_url="${apiaddrv2}"
	if [ -n "$apiaddrcode" ]; then
		api_url="${api_url}?code=${apiaddrcode}"
	fi
	
	# Build command text for SP call
	local text="CQEQueueGet ${lssn} ${hostname} ${os} op"
	
	# POST request to giipApiSk2
	wget -O "$output_file" \
		--post-data="text=${text}&token=${sk}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"$api_url" \
		--no-check-certificate -q 2>&1
	
	if [ -s "$output_file" ]; then
		# Check for JSON response (giipApiSk2 returns JSON)
		local is_json=$(cat "$output_file" | grep -o '^{.*}$')
		if [ -n "$is_json" ]; then
			# Extract fields from JSON response
			# Expected format: {"data":[{"RstVal":"200","ms_body":"script content","mssn":123,...}]}
			local rstval=$(cat "$output_file" | grep -o '"RstVal":"[^"]*"' | sed 's/"RstVal":"//; s/"$//' | head -1)
			local script_body=$(cat "$output_file" | grep -o '"ms_body":"[^"]*"' | sed 's/"ms_body":"//; s/"$//' | sed 's/\\n/\n/g')
			local mssn=$(cat "$output_file" | grep -o '"mssn":[0-9]*' | sed 's/"mssn"://' | head -1)
			
			# Check result
			if [ "$rstval" = "404" ]; then
				# No queue available
				return 1
			elif [ "$rstval" = "200" ]; then
				# Success - check if we have script body
				if [ -n "$script_body" ] && [ "$script_body" != "null" ]; then
					# ms_body is available, use it
					echo "$script_body" > "$output_file"
					dos2unix "$output_file" 2>/dev/null
					return 0
				elif [ -n "$mssn" ] && [ "$mssn" != "null" ] && [ "$mssn" != "0" ]; then
					# ms_body is empty but mssn is available, fetch from repository
					echo "[CQE] ms_body empty, fetching from repository (mssn=$mssn)"
					get_script_by_mssn "$mssn" "$output_file"
					return $?
				else
					# No script available
					echo "[CQE] ⚠️  No ms_body and no valid mssn"
					return 1
				fi
			else
				# Other error
				echo "[CQE] ⚠️  API returned RstVal=$rstval"
				return 1
			fi
		else
			# Not JSON, might be raw script (backward compatibility)
			dos2unix "$output_file" 2>/dev/null
			return 0
		fi
	else
		return 1
	fi
}

# Function: Process gateway servers
# Function: Process gateway servers (fetches from DB, not CSV!)
process_gateway_servers() {
	local tmpdir="/tmp/giipAgent_gateway_$$"
	mkdir -p "$tmpdir"
	
	local logdt=$(date '+%Y%m%d%H%M%S')
	echo "[${logdt}] [Gateway] Starting server processing cycle..." >> $LogFileName
	
	# Fetch server list from DB
	local server_json=""
	get_gateway_servers server_json
	
	if [ $? -ne 0 ] || [ -z "$server_json" ]; then
		echo "[${logdt}] [Gateway] ⚠️  Failed to fetch server list from DB" >> $LogFileName
		
		# Save error to KVS (giipagent factor)
		local error_details="{\"error_type\":\"gateway_fetch_failed\",\"error_message\":\"Failed to fetch server list from DB\"}"
		save_execution_log "gateway_error" "$error_details"
		
		rm -rf "$tmpdir"
		return 1
	fi
	
	# Count servers
	local server_count=$(echo "$server_json" | jq '. | length' 2>/dev/null || echo 0)
	
	# Save gateway cycle start to KVS (giipagent factor)
	local cycle_start_details="{\"action\":\"cycle_start\",\"server_count\":${server_count},\"data_source\":\"DB\"}"
	save_execution_log "gateway_cycle" "$cycle_start_details"
	
	local processed_count=0
	local success_count=0
	local failed_count=0
	local no_queue_count=0
	
	# Process each server from JSON
	echo "$server_json" | jq -c '.[]' 2>/dev/null | while read -r server_obj; do
		# Extract server details
		hostname=$(echo "$server_obj" | jq -r '.hostname // empty')
		lssn=$(echo "$server_obj" | jq -r '.lssn // 0')
		ssh_host=$(echo "$server_obj" | jq -r '.ssh_host // empty')
		ssh_user=$(echo "$server_obj" | jq -r '.ssh_user // "root"')
		ssh_port=$(echo "$server_obj" | jq -r '.ssh_port // 22')
		ssh_key=$(echo "$server_obj" | jq -r '.ssh_key_path // empty')
		ssh_password=$(echo "$server_obj" | jq -r '.ssh_password // empty')
		os_info=$(echo "$server_obj" | jq -r '.os_info // "Linux"')
		enabled=$(echo "$server_obj" | jq -r '.enabled // 1')
		
		# Skip disabled servers
		[ "$enabled" != "1" ] && continue
		
		# Skip if missing required fields
		if [ -z "$hostname" ] || [ -z "$ssh_host" ] || [ "$lssn" = "0" ]; then
			echo "[${logdt}] [Gateway] ⚠️  Skipping invalid server config: hostname=$hostname, lssn=$lssn" >> $LogFileName
			continue
		fi
		
		processed_count=$((processed_count + 1))
		
		logdt=$(date '+%Y%m%d%H%M%S')
		echo "[${logdt}] [Gateway] Processing: $hostname (LSSN:$lssn, ${ssh_user}@${ssh_host}:${ssh_port})" >> $LogFileName
		
		# Get queue
		local tmpfile="${tmpdir}/script_${lssn}.sh"
		get_remote_queue "$lssn" "$hostname" "$os_info" "$tmpfile"
		
		if [ -s "$tmpfile" ]; then
			# Check for errors
			local err_check=$(cat "$tmpfile" | grep "HTTP Error")
			if [ -n "$err_check" ]; then
				echo "[${logdt}] [Gateway]   ⚠️  Error: $err_check" >> $LogFileName
				rm -f "$tmpfile"
				
				# Save error to KVS (giipagent factor)
				local server_error_details="{\"action\":\"queue_fetch_error\",\"hostname\":\"${hostname}\",\"lssn\":${lssn},\"error\":\"${err_check}\"}"
				save_execution_log "gateway_server_error" "$server_error_details"
				
				failed_count=$((failed_count + 1))
				continue
			fi
			
			echo "[${logdt}] [Gateway]   📥 Queue received, executing..." >> $LogFileName
			
			# Execute on remote server
			execute_remote_command "$ssh_host" "$ssh_user" "$ssh_port" "$ssh_key" "$ssh_password" "$tmpfile" >> $LogFileName
			
			if [ $? -eq 0 ]; then
				echo "[${logdt}] [Gateway]   ✅ Success" >> $LogFileName
				success_count=$((success_count + 1))
				
				# Save success to KVS (giipagent factor)
				local server_success_details="{\"action\":\"command_executed\",\"hostname\":\"${hostname}\",\"lssn\":${lssn},\"ssh_host\":\"${ssh_host}\",\"result\":\"success\"}"
				save_execution_log "gateway_server_execution" "$server_success_details"
			else
				echo "[${logdt}] [Gateway]   ❌ Failed" >> $LogFileName
				failed_count=$((failed_count + 1))
				
				# Save failure to KVS (giipagent factor)
				local server_fail_details="{\"action\":\"command_failed\",\"hostname\":\"${hostname}\",\"lssn\":${lssn},\"ssh_host\":\"${ssh_host}\",\"result\":\"failed\"}"
				save_execution_log "gateway_server_error" "$server_fail_details"
			fi
			
			rm -f "$tmpfile"
		else
			echo "[${logdt}] [Gateway]   ⏸️  No queue" >> $LogFileName
			no_queue_count=$((no_queue_count + 1))
		fi
	done
	
	rm -rf "$tmpdir"
	logdt=$(date '+%Y%m%d%H%M%S')
	echo "[${logdt}] [Gateway] Cycle completed (data from DB, ${processed_count} servers processed)" >> $LogFileName
	
	# Save cycle summary to KVS (giipagent factor)
	local cycle_summary_details="{\"action\":\"cycle_completed\",\"total_servers\":${server_count},\"processed\":${processed_count},\"success\":${success_count},\"failed\":${failed_count},\"no_queue\":${no_queue_count},\"data_source\":\"DB\"}"
	save_execution_log "gateway_cycle" "$cycle_summary_details"
}

# ============================================================================
# End of Gateway Mode Functions
# ============================================================================

# ============================================================================
# KVS Execution Logging Functions
# ============================================================================

# Function: Save execution log to KVS (giipagent factor)
save_execution_log() {
	local event_type=$1
	local details_json=$2
	
	# Check if kvsput.sh is available
	local kvsput_script="./giipscripts/kvsput.sh"
	if [ ! -f "$kvsput_script" ]; then
		echo "[KVS-Log] ⚠️  kvsput.sh not found, skipping: ${event_type}" >> $LogFileName 2>/dev/null
		return 1
	fi
	
	# Create temp JSON file
	local tmp_json="/tmp/giip_kvs_log_$$.json"
	
	local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	local hostname=$(hostname)
	local mode="${gateway_mode}"
	[ "$mode" = "1" ] && mode="gateway" || mode="normal"
	
	# Build JSON using cat (no jq dependency in giipAgent2.sh)
	cat > "$tmp_json" <<EOF
{
  "event_type": "${event_type}",
  "timestamp": "${timestamp}",
  "lssn": ${lssn},
  "hostname": "${hostname}",
  "mode": "${mode}",
  "version": "${sv}",
  "details": ${details_json}
}
EOF
	
	# Call kvsput.sh with giipagent factor
	if bash "$kvsput_script" "$tmp_json" "giipagent" >> $LogFileName 2>&1; then
		echo "[KVS-Log] ✅ Saved: ${event_type}" >> $LogFileName 2>/dev/null
		rm -f "$tmp_json"
		return 0
	else
		echo "[KVS-Log] ⚠️  Failed to save: ${event_type}" >> $LogFileName 2>/dev/null
		rm -f "$tmp_json"
		return 1
	fi
}

# ============================================================================
# End of KVS Execution Logging Functions
# ============================================================================

# ============================================================================
# Gateway Server Status Collection Function
# ============================================================================
# Function: Get remote server list from DB (no CSV file needed!)
get_gateway_servers() {
	local output_var=$1  # Variable name to store JSON result
	
	local logdt=$(date '+%Y%m%d%H%M%S')
	
	# Use giipApiSk2 API
	local api_url="${apiaddrv2}"
	if [ -n "$apiaddrcode" ]; then
		api_url="${api_url}?code=${apiaddrcode}"
	fi
	
	# Call pApiGatewayRemoteServerListForAgentbySK
	local text="GatewayRemoteServerList ${lssn}"
	local temp_file="/tmp/gateway_servers_${lssn}_$$.json"
	
	wget -O "$temp_file" \
		--post-data="text=${text}&token=${sk}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"$api_url" \
		--no-check-certificate -q 2>&1
	
	if [ ! -s "$temp_file" ]; then
		echo "[$logdt] [Gateway] ⚠️  Failed to fetch server list from DB" >> $LogFileName
		rm -f "$temp_file"
		eval "$output_var=''"
		return 1
	fi
	
	# Check for error response
	local rstval=$(cat "$temp_file" | grep -o '"RstVal":"[^"]*"' | sed 's/"RstVal":"//; s/"$//' | head -1)
	if [ "$rstval" != "200" ] && [ -n "$rstval" ]; then
		echo "[$logdt] [Gateway] ⚠️  API error (RstVal=$rstval)" >> $LogFileName
		cat "$temp_file" | head -5 >> $LogFileName
		rm -f "$temp_file"
		eval "$output_var=''"
		return 1
	fi
	
	# Extract data array from JSON response
	# Expected format: {"data":[{server1},{server2},...]}
	local server_list=$(cat "$temp_file" | grep -o '"data":\[.*\]' | sed 's/"data"://; s/^{//; s/}$//')
	
	if [ -z "$server_list" ]; then
		# Fallback: maybe it's already an array
		server_list=$(cat "$temp_file")
	fi
	
	echo "[$logdt] [Gateway] ✅ Fetched server list from DB (no CSV needed)" >> $LogFileName
	rm -f "$temp_file"
	
	eval "$output_var='$server_list'"
	return 0
}

# Function: Collect server status (using DB, not CSV!)
collect_gateway_server_status() {
	local logdt=$(date '+%Y%m%d%H%M%S')
	echo "[$logdt] [Gateway] Starting server status collection..." >> $LogFileName
	
	# Fetch server list from DB
	local server_json=""
	get_gateway_servers server_json
	if [ $? -ne 0 ] || [ -z "$server_json" ]; then
		echo "[$logdt] [Gateway] No servers to check (DB query failed)" >> $LogFileName
		
		# Save error to KVS (giipagent factor)
		local error_details="{\"error_type\":\"status_fetch_failed\",\"error_message\":\"DB query failed\"}"
		save_execution_log "gateway_error" "$error_details"
		
		return 1
	fi
	
	# Count servers (JSON array parsing)
	local server_count=$(echo "$server_json" | grep -o "hostname" | wc -l)
	if [ $server_count -eq 0 ]; then
		echo "[$logdt] [Gateway] No servers to check" >> $LogFileName
		return 0
	fi
	
	echo "[$logdt] [Gateway] Checking status of ${server_count} servers..." >> $LogFileName
	
	# Save status check start to KVS (giipagent factor)
	local check_start_details="{\"action\":\"status_check_start\",\"server_count\":${server_count},\"data_source\":\"DB\"}"
	save_execution_log "gateway_status" "$check_start_details"
	
	# Prepare JSON array for bulk status upload
	local status_json="["
	local first_server=1
	local checked_count=0
	local accessible_count=0
	local failed_count=0
	
	# Parse JSON array and process each server
	echo "$server_json" | jq -c '.[]' 2>/dev/null | while read -r server_obj; do
		# Extract server details from JSON
		hostname=$(echo "$server_obj" | jq -r '.hostname // empty')
		remote_lssn=$(echo "$server_obj" | jq -r '.lssn // 0')
		ssh_host=$(echo "$server_obj" | jq -r '.ssh_host // empty')
		ssh_user=$(echo "$server_obj" | jq -r '.ssh_user // "root"')
		ssh_port=$(echo "$server_obj" | jq -r '.ssh_port // 22')
		ssh_key_path=$(echo "$server_obj" | jq -r '.ssh_key_path // empty')
		ssh_password=$(echo "$server_obj" | jq -r '.ssh_password // empty')
		os_info=$(echo "$server_obj" | jq -r '.os_info // "Linux"')
		enabled=$(echo "$server_obj" | jq -r '.enabled // 1')
		
		# Skip disabled servers
		[ "$enabled" != "1" ] && continue
		
		# Skip if missing required fields
		[ -z "$hostname" ] || [ -z "$ssh_host" ] || [ "$remote_lssn" = "0" ] && continue
		if [ "$enabled" != "1" ]; then
			continue
		fi
		
		# Clean up fields (remove quotes and spaces)
		hostname=$(echo "$hostname" | tr -d '"' | tr -d ' ')
		remote_lssn=$(echo "$remote_lssn" | tr -d '"' | tr -d ' ')
		ssh_host=$(echo "$ssh_host" | tr -d '"' | tr -d ' ')
		ssh_user=$(echo "$ssh_user" | tr -d '"' | tr -d ' ')
		ssh_port=$(echo "$ssh_port" | tr -d '"' | tr -d ' ')
		ssh_key_path=$(echo "$ssh_key_path" | tr -d '"' | tr -d ' ')
		ssh_password=$(echo "$ssh_password" | tr -d '"' | tr -d ' ')
		
		# Default port
		if [ -z "$ssh_port" ]; then
			ssh_port=22
		fi
		
		echo "[$logdt] [Gateway] Checking: $hostname ($ssh_host:$ssh_port)" >> $LogFileName
		
		# Measure SSH connection time
		local start_time=$(date +%s%3N)  # milliseconds
		local ssh_accessible=0
		local connection_status="unknown"
		local status_message=""
		local error_message=""
		local response_time_ms=0
		
		# Build SSH command
		local ssh_cmd="ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes"
		
		if [ -n "$ssh_key_path" ] && [ -f "$ssh_key_path" ]; then
			# SSH key authentication
			ssh_cmd="$ssh_cmd -i $ssh_key_path"
		elif [ -n "$ssh_password" ]; then
			# Password authentication (requires sshpass)
			if command -v sshpass &> /dev/null; then
				ssh_cmd="sshpass -p '$ssh_password' $ssh_cmd"
			else
				error_message="sshpass not installed for password auth"
				connection_status="config_error"
				echo "[$logdt] [Gateway] ⚠️  $hostname: $error_message" >> $LogFileName
			fi
		fi
		
		# Try SSH connection and collect system info
		if [ "$connection_status" != "config_error" ]; then
			local ssh_result=$($ssh_cmd -p $ssh_port ${ssh_user}@${ssh_host} "echo 'SSH_OK'; uptime; cat /proc/cpuinfo | grep 'model name' | head -1; free -m; df -h /" 2>&1)
			local ssh_exit=$?
			
			local end_time=$(date +%s%3N)
			response_time_ms=$((end_time - start_time))
			
			if [ $ssh_exit -eq 0 ] && echo "$ssh_result" | grep -q "SSH_OK"; then
				ssh_accessible=1
				connection_status="success"
				status_message="SSH connection successful"
				accessible_count=$((accessible_count + 1))
				
				# Parse system info (simplified)
				local uptime_line=$(echo "$ssh_result" | grep "up" | head -1)
				local uptime_seconds=0
				if echo "$uptime_line" | grep -q "day"; then
					local days=$(echo "$uptime_line" | grep -o "[0-9]* day" | awk '{print $1}')
					uptime_seconds=$((days * 86400))
				fi
				
				echo "[$logdt] [Gateway] ✅ $hostname: Connected ($response_time_ms ms)" >> $LogFileName
				
				# Save success to KVS (giipagent factor)
				local ssh_success_details="{\"action\":\"ssh_check\",\"hostname\":\"${hostname}\",\"lssn\":${remote_lssn},\"ssh_host\":\"${ssh_host}\",\"accessible\":true,\"response_ms\":${response_time_ms}}"
				save_execution_log "gateway_ssh_check" "$ssh_success_details"
			else
				ssh_accessible=0
				failed_count=$((failed_count + 1))
				
				if echo "$ssh_result" | grep -qi "timeout"; then
					connection_status="timeout"
					error_message="Connection timeout"
				elif echo "$ssh_result" | grep -qi "refused"; then
					connection_status="refused"
					error_message="Connection refused"
				elif echo "$ssh_result" | grep -qi "permission denied"; then
					connection_status="auth_failed"
					error_message="Authentication failed"
				else
					connection_status="failed"
					error_message=$(echo "$ssh_result" | head -1 | tr -d '\n' | head -c 200)
				fi
				echo "[$logdt] [Gateway] ❌ $hostname: $connection_status - $error_message" >> $LogFileName
				
				# Save failure to KVS (giipagent factor)
				local ssh_fail_details="{\"action\":\"ssh_check\",\"hostname\":\"${hostname}\",\"lssn\":${remote_lssn},\"ssh_host\":\"${ssh_host}\",\"accessible\":false,\"response_ms\":${response_time_ms},\"error\":\"${connection_status}\"}"
				save_execution_log "gateway_ssh_check" "$ssh_fail_details"
			fi
		fi
		
		# Build JSON for this server
		local server_json=$(cat <<EOF
{
  "remote_lssn": ${remote_lssn},
  "ssh_accessible": $([ $ssh_accessible -eq 1 ] && echo 'true' || echo 'false'),
  "response_time_ms": ${response_time_ms},
  "connection_status": "${connection_status}",
  "status_message": "${status_message}",
  "error_message": "${error_message}",
  "os_info": "${os_info}",
  "uptime_seconds": null,
  "cpu_usage_percent": null,
  "memory_usage_percent": null,
  "disk_usage_percent": null
}
EOF
)
		
		# Add to array
		if [ $first_server -eq 1 ]; then
			status_json="${status_json}${server_json}"
			first_server=0
		else
			status_json="${status_json},${server_json}"
		fi
		
		checked_count=$((checked_count + 1))
		
	done < "${gateway_serverlist}"
	
	status_json="${status_json}]"
	
	if [ $checked_count -eq 0 ]; then
		echo "[$logdt] [Gateway] No servers checked" >> $LogFileName
		return 0
	fi
	
	echo "[$logdt] [Gateway] Checked ${checked_count} servers, uploading status..." >> $LogFileName
	
	# Save to temp file for debugging
	local status_file="/tmp/gateway_status_${lssn}_$$.json"
	echo "$status_json" > "$status_file"
	
	# Upload status via API (pApiGatewayStatusPutbySk)
	local api_url="${apiaddrv2}"
	if [ -n "$apiaddrcode" ]; then
		api_url="${api_url}?code=${apiaddrcode}"
	fi
	
	local api_text="GatewayStatusPut gateway_lssn status_data"
	local api_jsondata="{\"gateway_lssn\":${lssn},\"status_data\":${status_json}}"
	
	local api_response=$(wget -q -O - \
		--post-data="text=${api_text}&token=${sk}&jsondata=$(echo ${api_jsondata} | jq -sRr @uri 2>/dev/null || echo ${api_jsondata} | sed 's/ /%20/g')" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"${api_url}" \
		--no-check-certificate 2>&1)
	
	local api_exit=$?
	
	if [ $api_exit -eq 0 ]; then
		local rstval=$(echo "$api_response" | jq -r '.data[0].RstVal // "0"' 2>/dev/null || echo "0")
		if [ "$rstval" = "200" ]; then
			echo "[$logdt] [Gateway] ✅ Status uploaded successfully" >> $LogFileName
			rm -f "$status_file"
			
			# Save status check summary to KVS (giipagent factor)
			local check_summary_details="{\"action\":\"status_check_completed\",\"total_servers\":${server_count},\"checked\":${checked_count},\"accessible\":${accessible_count},\"failed\":${failed_count},\"data_source\":\"DB\"}"
			save_execution_log "gateway_status" "$check_summary_details"
			
			return 0
		else
			local rstmsg=$(echo "$api_response" | jq -r '.data[0].RstMsg // "Unknown error"' 2>/dev/null || echo "Unknown error")
			echo "[$logdt] [Gateway] ⚠️  API returned error: RstVal=$rstval, Msg=$rstmsg" >> $LogFileName
			echo "[$logdt] [Gateway] Status file saved: $status_file" >> $LogFileName
			
			# Save API error to KVS (giipagent factor)
			local api_error_details="{\"error_type\":\"status_upload_failed\",\"rstval\":\"${rstval}\",\"rstmsg\":\"${rstmsg}\"}"
			save_execution_log "gateway_error" "$api_error_details"
			
			return 1
		fi
	else
		echo "[$logdt] [Gateway] ❌ Failed to upload status (exit=$api_exit)" >> $LogFileName
		echo "[$logdt] [Gateway] Status file saved: $status_file" >> $LogFileName
		
		# Save upload error to KVS (giipagent factor)
		local upload_error_details="{\"error_type\":\"status_upload_failed\",\"exit_code\":${api_exit}}"
		save_execution_log "gateway_error" "$upload_error_details"
		
		return 1
	fi
}

# ============================================================================
# End of Gateway Server Status Collection Function
# ============================================================================

# Check dos2unix
CHECK_Converter=`which dos2unix`
RESULT=`echo $?`

#OS Check
# Check MacOS
uname=`uname -a | awk '{print $1}'`
if [ "${uname}" = "Darwin" ];then
	osname=`sw_vers -productName`
	osver=`sw_vers -productVersion`
	os="${osname} ${osver}"
	os=`echo "$os" | sed 's/^ *\| *$//'`
	os=`echo "$os" | sed -e "s/ /%20/g"`
	if [ ${RESULT} -ne 0 ];then
		brew install dos2unix
	fi
else
	ostype=`head -n 1 /etc/issue | awk '{print $1}'`
	if [ "${ostype}" = "Ubuntu" ];then
		os=`lsb_release -d`
		os=`echo "$os" | sed 's/^ *\| *$//'`
		os=`echo "$os" | sed -e "s/Description\://g"`

		if [ ${RESULT} -ne 0 ];then
			apt-get install -y dos2unix
		fi
	else
		os=`cat /etc/redhat-release`

		if [ ${RESULT} -ne 0 ];then
			yum install -y dos2unix
		fi
	fi
fi

hn=`hostname`
tmpFileName="giipTmpScript.sh"
logdt=`date '+%Y%m%d%H%M%S'`
Today=`date '+%Y%m%d'`

# Create log directory in script location
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOG_DIR="${SCRIPT_DIR}/log"
mkdir -p "$LOG_DIR"

LogFileName="${LOG_DIR}/giipAgent2_$Today.log"

# Use giipApiSk2 with POST method for normal queue download
# Build API URL
lwAPIURL="${apiaddrv2}"
if [ -n "$apiaddrcode" ]; then
	lwAPIURL="${lwAPIURL}?code=${apiaddrcode}"
fi

# Build command text for SP call
lwDownloadText="CQEQueueGet ${lssn} ${hn} ${os} op"

echo "API URL: $lwAPIURL"
echo "Command: $lwDownloadText"

# Add Server
if [ "${lssn}" = "0" ];then
	# Use POST method for new server registration
	wget -O $tmpFileName \
		--post-data="text=${lwDownloadText}&token=${sk}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"${lwAPIURL}" \
		--no-check-certificate -q
	
	lssn=`cat ${tmpFileName}`
	cnfdmp=`cat ./giipAgent.cnf | sed -e "s|lssn=\"0\"|lssn=\"${lssn}\"|g"`
	echo "${cnfdmp}" >giipAgent.cnf
	rm -f $tmpFileName
	
	# Rebuild command with new lssn
	lwDownloadText="CQEQueueGet ${lssn} ${hn} ${os} op"
fi

# ============================================================================
# Fetch Gateway Mode from DB (Single Source of Truth)
# ============================================================================
if [ -z "$gateway_mode" ] && [ "${lssn}" != "0" ]; then
	logdt=`date '+%Y%m%d%H%M%S'`
	echo "[$logdt] [Init] Fetching server configuration from DB..." >> $LogFileName
	
	# Use giipApiSk2 API
	local config_url="${apiaddrv2}"
	if [ -n "$apiaddrcode" ]; then
		config_url="${config_url}?code=${apiaddrcode}"
	fi
	
	# Call pApiLSvrGetConfigbySK
	local config_text="LSvrGetConfig ${lssn} ${hn}"
	local config_file="/tmp/giip_config_${lssn}.json"
	
	wget -O "$config_file" \
		--post-data="text=${config_text}&token=${sk}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"${config_url}" \
		--no-check-certificate -q 2>&1
	
	if [ -s "$config_file" ]; then
		# Parse JSON response
		local rstval=$(cat "$config_file" | grep -o '"RstVal":"[^"]*"' | sed 's/"RstVal":"//; s/"$//' | head -1)
		
		if [ "$rstval" = "200" ]; then
			# Extract is_gateway value
			local is_gateway=$(cat "$config_file" | grep -o '"is_gateway":[0-9]*' | sed 's/"is_gateway"://' | head -1)
			
			if [ "$is_gateway" = "1" ]; then
				gateway_mode="1"
				echo "[$logdt] [Init] ✅ Gateway mode ENABLED (is_gateway=1 in DB)" >> $LogFileName
			else
				gateway_mode="0"
				echo "[$logdt] [Init] ℹ️  Normal agent mode (is_gateway=0 in DB)" >> $LogFileName
			fi
		else
			# Default to normal mode if API call fails
			gateway_mode="0"
			echo "[$logdt] [Init] ⚠️  Failed to fetch config (RstVal=$rstval), defaulting to normal mode" >> $LogFileName
		fi
	else
		gateway_mode="0"
		echo "[$logdt] [Init] ⚠️  API call failed, defaulting to normal mode" >> $LogFileName
	fi
	
	rm -f "$config_file"
fi

# Default to normal mode if still empty
if [ -z "$gateway_mode" ]; then
	gateway_mode="0"
fi

# ============================================================================
# Gateway Mode: Check and initialize
# ============================================================================
if [ "${gateway_mode}" = "1" ]; then
	logdt=`date '+%Y%m%d%H%M%S'`
	echo "[$logdt] ========================================" >> $LogFileName
	echo "[$logdt] Starting GIIP Agent V2.0 in GATEWAY MODE" >> $LogFileName
	echo "[$logdt] Using giipApiSk2 (PowerShell-based)" >> $LogFileName
	echo "[$logdt] Version: ${sv}" >> $LogFileName
	echo "[$logdt] Gateway LSSN: ${lssn}" >> $LogFileName
	echo "[$logdt] ========================================" >> $LogFileName
	
	# Save gateway startup status to KVS (using giipApiSk2)
	startup_status="{\"status\":\"started\",\"version\":\"${sv}\",\"lssn\":${lssn},\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"mode\":\"gateway\",\"api\":\"giipApiSk2\"}"
	
	local kvs_url="${apiaddrv2}"
	if [ -n "$apiaddrcode" ]; then
		kvs_url="${kvs_url}?code=${apiaddrcode}"
	fi
	
	kvs_text="KVSPut kType kKey kFactor"
	kvs_data="{\"kType\":\"gateway_status\",\"kKey\":\"gateway_${lssn}_startup\",\"kFactor\":${startup_status}}"
	wget -O /dev/null --post-data="text=${kvs_text}&token=${sk}&jsondata=$(echo ${kvs_data} | sed 's/ /%20/g')" "${kvs_url}" --no-check-certificate -q 2>&1
	
	# Save gateway initialization to KVS (giipagent factor)
	init_details="{\"config_file\":\"giipAgent.cnf\",\"api_endpoint\":\"${apiaddrv2}\",\"pid\":$$}"
	save_execution_log "startup" "$init_details"
	
	# Check and install sshpass
	check_sshpass
	if [ $? -ne 0 ]; then
		echo "[$logdt] Error: Failed to setup sshpass" >> $LogFileName
		
		# Save error to KVS (giipagent factor)
		error_details="{\"error_type\":\"config_error\",\"error_message\":\"Failed to setup sshpass\",\"error_code\":1,\"context\":\"gateway_init\"}"
		save_execution_log "error" "$error_details"
		
		# Save error to KVS (backward compatibility)
		error_status="{\"status\":\"error\",\"error\":\"Failed to setup sshpass\",\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}"
		kvs_data="{\"kType\":\"gateway_status\",\"kKey\":\"gateway_${lssn}_error\",\"kFactor\":${error_status}}"
		wget -O /dev/null --post-data="text=${kvs_text}&token=${sk}&jsondata=$(echo ${kvs_data} | sed 's/ /%20/g')" "${kvs_url}" --no-check-certificate -q 2>&1
		
		exit 1
	fi
	
	# Check and install database clients
	check_db_clients
	
	# Test DB connection - fetch server list
	echo "[$logdt] [Gateway] Fetching server list from DB..." >> $LogFileName
	local test_servers=""
	get_gateway_servers test_servers
	
	# Check if we got any servers
	local server_count=0
	if [ -z "$test_servers" ]; then
		echo "[$logdt] [Gateway] Warning: No servers found in DB" >> $LogFileName
		echo "[$logdt] [Gateway] Please configure remote servers via Web UI" >> $LogFileName
		echo "[$logdt] [Gateway] Go to: lsvrdetail page > Gateway Settings > Add Remote Servers" >> $LogFileName
	else
		server_count=$(echo "$test_servers" | grep -o "hostname" | wc -l)
		echo "[$logdt] [Gateway] ✅ Found ${server_count} servers to manage (from DB)" >> $LogFileName
	fi
	
	# Collect DB client status
	sshpass_ok=0
	command -v sshpass &> /dev/null && sshpass_ok=1
	
	mysql_ok=0
	command -v mysql &> /dev/null && mysql_ok=1
	
	psql_ok=0
	command -v psql &> /dev/null && psql_ok=1
	
	mssql_ok=0
	python3 -c "import pyodbc" 2>/dev/null && mssql_ok=1
	
	oracle_ok=0
	python3 -c "import cx_Oracle" 2>/dev/null && oracle_ok=1
	
	python_version=$(python3 --version 2>&1 | awk '{print $2}')
	
	# Save Gateway initialization complete to KVS (giipagent factor)
	init_complete_details="{\"sshpass_installed\":$([ $sshpass_ok -eq 1 ] && echo 'true' || echo 'false'),\"python_version\":\"${python_version}\",\"db_clients\":{\"mysql\":$([ $mysql_ok -eq 1 ] && echo 'true' || echo 'false'),\"postgresql\":$([ $psql_ok -eq 1 ] && echo 'true' || echo 'false'),\"mssql\":$([ $mssql_ok -eq 1 ] && echo 'true' || echo 'false'),\"oracle\":$([ $oracle_ok -eq 1 ] && echo 'true' || echo 'false')},\"server_sync_status\":\"success\",\"server_count\":${server_count}}"
	save_execution_log "gateway_init" "$init_complete_details"
	
	# Save initial sync status to KVS
	sync_status="{\"status\":\"synced\",\"server_count\":${server_count},\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"api\":\"giipApiSk2\"}"
	kvs_data="{\"kType\":\"gateway_status\",\"kKey\":\"gateway_${lssn}_sync\",\"kFactor\":${sync_status}}"
	wget -O /dev/null --post-data="text=${kvs_text}&token=${sk}&jsondata=$(echo ${kvs_data} | sed 's/ /%20/g')" "${kvs_url}" --no-check-certificate -q 2>&1
	
	# Track last sync time
	last_sync_time=$(date +%s)
	
	# Track last heartbeat time
	last_heartbeat_time=0
	
	# Gateway main loop
	while [ ${cntgiip} -le 3 ]; do
		logdt=`date '+%Y%m%d%H%M%S'`
		
		# Check if we need to re-sync from API
		if [ "${gateway_sync_interval}" != "0" ]; then
			current_time=$(date +%s)
			time_diff=$((current_time - last_sync_time))
			
			if [ $time_diff -ge ${gateway_sync_interval} ]; then
				echo "[$logdt] [Gateway] Auto-refreshing server list from Web UI..." >> $LogFileName
				sync_gateway_servers
				
				# Also refresh DB queries
				echo "[$logdt] [Gateway-DB] Auto-refreshing database query list..." >> $LogFileName
				sync_db_queries
				
				last_sync_time=$current_time
			fi
		fi
		
		# Check if we need to run heartbeat (collect remote server info)
		current_time=$(date +%s)
		heartbeat_diff=$((current_time - last_heartbeat_time))
		
		if [ $heartbeat_diff -ge ${gateway_heartbeat_interval} ]; then
			echo "[$logdt] [Gateway-Heartbeat] Running heartbeat to collect remote server info..." >> $LogFileName
			
			# Collect server status (NEW!)
			collect_gateway_server_status
			
			# Save heartbeat trigger to KVS (giipagent factor)
			heartbeat_details="{\"interval_seconds\":${gateway_heartbeat_interval},\"status_collection\":\"enabled\"}"
			
			# Save heartbeat trigger to KVS (backward compatibility)
			heartbeat_trigger="{\"status\":\"triggered\",\"interval\":${gateway_heartbeat_interval},\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}"
			kvs_data="{\"kType\":\"gateway_heartbeat\",\"kKey\":\"gateway_${lssn}_heartbeat_trigger\",\"kFactor\":${heartbeat_trigger}}"
			wget -O /dev/null --post-data="text=${kvs_text}&token=${sk}&jsondata=$(echo ${kvs_data} | sed 's/ /%20/g')" "${kvs_url}" --no-check-certificate -q 2>&1
			
			# Check if heartbeat script exists
			heartbeat_script="./giipAgentGateway-heartbeat.sh"
			if [ -f "$heartbeat_script" ]; then
				# Execute heartbeat script in background (non-blocking)
				bash "$heartbeat_script" >> $LogFileName 2>&1 &
				heartbeat_pid=$!
				echo "[$logdt] [Gateway-Heartbeat] Started (PID: $heartbeat_pid)" >> $LogFileName
				
				# Update heartbeat details with PID
				heartbeat_details="{\"interval_seconds\":${gateway_heartbeat_interval},\"script_path\":\"./giipAgentGateway-heartbeat.sh\",\"background_pid\":${heartbeat_pid}}"
				save_execution_log "heartbeat" "$heartbeat_details"
				
				# Save heartbeat start to KVS (backward compatibility)
				heartbeat_start="{\"status\":\"running\",\"pid\":${heartbeat_pid},\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}"
				kvs_data="{\"kType\":\"gateway_heartbeat\",\"kKey\":\"gateway_${lssn}_heartbeat_status\",\"kFactor\":${heartbeat_start}}"
				wget -O /dev/null --post-data="text=${kvs_text}&token=${sk}&jsondata=$(echo ${kvs_data} | sed 's/ /%20/g')" "${kvs_url}" --no-check-certificate -q 2>&1
			else
				echo "[$logdt] [Gateway-Heartbeat] ⚠️  Script not found: $heartbeat_script" >> $LogFileName
				echo "[$logdt] [Gateway-Heartbeat] Remote server info collection will be skipped" >> $LogFileName
				
				# Save error to KVS
				heartbeat_error="{\"status\":\"error\",\"error\":\"Script not found: ${heartbeat_script}\",\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}"
				kvs_data="{\"kType\":\"gateway_heartbeat\",\"kKey\":\"gateway_${lssn}_heartbeat_error\",\"kFactor\":${heartbeat_error}}"
				wget -O /dev/null --post-data="text=${kvs_text}&token=${sk}&jsondata=$(echo ${kvs_data} | sed 's/ /%20/g')" "${kvs_url}" --no-check-certificate -q 2>&1
			fi
			
			last_heartbeat_time=$current_time
		fi
		
		# Process database queries first
		process_db_queries
		
		# Process all gateway servers
		if [ -f "${gateway_serverlist}" ]; then
			process_gateway_servers
		else
			echo "[$logdt] [Gateway] No server list available, skipping cycle" >> $LogFileName
		fi
		
		# Sleep before next cycle
		logdt=`date '+%Y%m%d%H%M%S'`
		echo "[$logdt] [Gateway] Sleeping ${giipagentdelay} seconds..." >> $LogFileName
		sleep $giipagentdelay
		
		# Re-check process count
		cntgiip=`ps aux | grep giipAgent2.sh | grep -v grep | wc -l`
	done
	
	logdt=`date '+%Y%m%d%H%M%S'`
	if [ ${cntgiip} -ge 4 ]; then
		echo "[$logdt] [Gateway] Terminated by process count $cntgiip" >> $LogFileName
		ret=`ps aux | grep giipAgent2.sh | grep -v grep`
		echo "$ret" >> $LogFileName
	fi
	
	exit 0
fi

# ============================================================================
# Normal Mode: Local agent execution
# ============================================================================

# Save Agent startup to KVS (Normal mode)
logdt=`date '+%Y%m%d%H%M%S'`
echo "[$logdt] Starting GIIP Agent V2.0 in NORMAL MODE" >> $LogFileName
echo "[$logdt] Version: ${sv}, LSSN: ${lssn}, Hostname: ${hn}" >> $LogFileName

startup_details="{\"pid\":$$,\"config_file\":\"giipAgent.cnf\",\"api_endpoint\":\"${lwAPIURL}\"}"
save_execution_log "startup" "$startup_details"

# Run once and exit (no loop)
cntgiip=999  # Force single execution

	#curl -o $tmpFileName "$lwDownloadURL"
	# Use POST method for giipApiSk2
	wget -O $tmpFileName \
		--post-data="text=${lwDownloadText}&token=${sk}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"${lwAPIURL}" \
		--no-check-certificate -q

	if [ -s ${tmpFileName} ];then
		# Debug: Log full response (limited to 500 chars)
		echo "[$logdt] [DEBUG] Response: $(head -c 500 $tmpFileName | tr '\n' ' ')" >> $LogFileName
		
		# Check if response contains JSON (even error JSON)
		# Look for opening brace - if it's JSON, DON'T execute it as script
		is_json=$(head -c 10 "$tmpFileName" | grep -E '^\s*\{')
		
		if [ -n "$is_json" ]; then
			# It's JSON - check if it's error or success
			if grep -q '"error"' "$tmpFileName"; then
				# Error response
				error_msg=$(cat "$tmpFileName" | grep -o '"error"\s*:\s*"[^"]*"' | sed 's/"error"\s*:\s*"//; s/"$//' | head -1)
				echo "[$logdt] ❌ API Error: $error_msg" >> $LogFileName
				
				# Save error to KVS
				error_details="{\"error_type\":\"api_error\",\"error_message\":\"${error_msg}\",\"error_code\":1,\"context\":\"queue_fetch\"}"
				save_execution_log "error" "$error_details"
				
				rm -f $tmpFileName
				cntgiip=999
				# Exit instead of continue (no loop)
			fi
			
			# Try to extract RstVal and other fields
			# Log raw response for debugging
			echo "[$logdt] [DEBUG] Raw API response:" >> $LogFileName
			cat "$tmpFileName" | head -20 >> $LogFileName
			
			# Extract fields from JSON
			rstval=$(cat "$tmpFileName" | grep -o '"RstVal"\s*:\s*"[^"]*"' | sed 's/"RstVal"\s*:\s*"//; s/"$//' | head -1)
			script_body=$(cat "$tmpFileName" | grep -o '"ms_body"\s*:\s*"[^"]*"' | sed 's/"ms_body"\s*:\s*"//; s/"$//' | sed 's/\\n/\n/g')
			mssn=$(cat "$tmpFileName" | grep -o '"mssn"\s*:\s*[0-9]*' | sed 's/"mssn"\s*:\s*//' | head -1)
			
			echo "[$logdt] [DEBUG] JSON parsed - RstVal='$rstval', mssn='$mssn', script_body_len=${#script_body}" >> $LogFileName
			
			# Check if parsing failed (empty rstval could mean empty response or parsing error)
			if [ -z "$rstval" ]; then
				# Check if response is actually empty or just malformed
				RESPONSE_SIZE=$(wc -c < "$tmpFileName")
				if [ "$RESPONSE_SIZE" -lt 10 ]; then
					# Response is too small, treat as empty
					echo "[$logdt] API response too small (${RESPONSE_SIZE} bytes), treating as empty queue" >> $LogFileName
					queue_check_details="{\"api_response\":\"empty_or_malformed\",\"has_queue\":false,\"response_size\":${RESPONSE_SIZE},\"script_source\":\"none\"}"
					save_execution_log "queue_check" "$queue_check_details"
					rm -f $tmpFileName
					cntgiip=999
					# Exit instead of continue (no loop)
				else
					# Response has content but parsing failed
					echo "[$logdt] [WARN] Failed to parse RstVal from response (${RESPONSE_SIZE} bytes)" >> $LogFileName
					
					# Save response for debugging
					RESPONSE_DEBUG="/tmp/giip_parse_failed_$(date +%Y%m%d_%H%M%S).json"
					cp "$tmpFileName" "$RESPONSE_DEBUG" 2>/dev/null
					echo "[$logdt] [DEBUG] Response saved to: $RESPONSE_DEBUG" >> $LogFileName
					
					# Try alternative parsing (maybe different JSON structure)
					# Check if it's a simple success response without data
					if grep -q '"success"' "$tmpFileName" || grep -q '"status".*200' "$tmpFileName"; then
						echo "[$logdt] Detected success response without queue data" >> $LogFileName
						queue_check_details="{\"api_response\":\"success_no_data\",\"has_queue\":false,\"response_file\":\"$RESPONSE_DEBUG\",\"script_source\":\"none\"}"
						save_execution_log "queue_check" "$queue_check_details"
					else
						# Unknown response format
						error_details="{\"error_type\":\"parse_error\",\"error_message\":\"Failed to parse API response\",\"response_size\":${RESPONSE_SIZE},\"response_file\":\"$RESPONSE_DEBUG\",\"context\":\"json_parsing\"}"
						save_execution_log "error" "$error_details"
					fi
					
					rm -f $tmpFileName
					cntgiip=999
					# Exit instead of continue (no loop)
				fi
			elif [ "$rstval" = "404" ]; then
				# No queue available
				rm -f $tmpFileName
				echo "[$logdt] No queue (404)" >> $LogFileName
				
				# Save queue check to KVS
				queue_check_details="{\"api_response\":\"404\",\"has_queue\":false,\"mssn\":0,\"script_source\":\"none\"}"
				save_execution_log "queue_check" "$queue_check_details"
				
				cntgiip=999
				# Exit instead of continue (no loop)
			elif [ "$rstval" = "200" ]; then
				# Success - check if we have script body
				if [ -n "$script_body" ] && [ "$script_body" != "null" ]; then
					# ms_body is available
					echo "$script_body" > "$tmpFileName"
					echo "[$logdt] Queue received (ms_body)" >> $LogFileName
					
					# Save queue check to KVS
					queue_check_details="{\"api_response\":\"200\",\"has_queue\":true,\"mssn\":${mssn:-0},\"script_source\":\"ms_body\"}"
					save_execution_log "queue_check" "$queue_check_details"
				elif [ -n "$mssn" ] && [ "$mssn" != "null" ] && [ "$mssn" != "0" ]; then
					# ms_body is empty, fetch from repository
					echo "[$logdt] ms_body empty, fetching from repository (mssn=$mssn)" >> $LogFileName
					get_script_by_mssn "$mssn" "$tmpFileName"
					if [ $? -ne 0 ]; then
						echo "[$logdt] ❌ Failed to fetch script from repository" >> $LogFileName
						
					
					# Save error to KVS
					error_details="{\"error_type\":\"api_error\",\"error_message\":\"Failed to fetch script from repository\",\"error_code\":1,\"context\":\"queue_fetch\",\"mssn\":${mssn}}"
					save_execution_log "error" "$error_details"
					
					rm -f $tmpFileName
					cntgiip=999
					# Exit instead of continue (no loop)
				fi
				echo "[$logdt] Queue received (repository)" >> $LogFileName					# Save queue check to KVS
					queue_check_details="{\"api_response\":\"200\",\"has_queue\":true,\"mssn\":${mssn},\"script_source\":\"repository\"}"
					save_execution_log "queue_check" "$queue_check_details"
				else
					# No script available
					echo "[$logdt] ⚠️  No script available (no ms_body, no mssn)" >> $LogFileName
					
					# Save queue check to KVS
					queue_check_details="{\"api_response\":\"200\",\"has_queue\":false,\"mssn\":0,\"script_source\":\"none\"}"
					save_execution_log "queue_check" "$queue_check_details"
					
					rm -f $tmpFileName
					cntgiip=999
					# Exit instead of continue (no loop)
				fi
			else
				# Other error (but rstval has some value)
				echo "[$logdt] ⚠️  API returned unexpected RstVal: '$rstval'" >> $LogFileName
				
				# Save raw response to temp file for analysis
				RESPONSE_DEBUG="/tmp/giip_api_response_debug_$(date +%Y%m%d_%H%M%S).json"
				cp "$tmpFileName" "$RESPONSE_DEBUG" 2>/dev/null
				echo "[$logdt] [DEBUG] Response saved to: $RESPONSE_DEBUG" >> $LogFileName
				
				# Save error to KVS with more details
				error_details="{\"error_type\":\"unexpected_rstval\",\"error_message\":\"Unexpected RstVal value\",\"rstval\":\"$rstval\",\"context\":\"queue_check\",\"response_file\":\"$RESPONSE_DEBUG\"}"
				save_execution_log "error" "$error_details"
				
				rm -f $tmpFileName
				cntgiip=999
				# Exit instead of continue (no loop)
			fi
		else
			# Not JSON, assume it's raw script (backward compatibility)
			echo "[$logdt] Non-JSON response detected, treating as raw script" >> $LogFileName
		fi
		
		# Only process if file still has content and is not JSON error response
		if [ -s ${tmpFileName} ]; then
			ls -l $tmpFileName
			dos2unix $tmpFileName
			echo "[$logdt] Downloaded queue... " >> $LogFileName
		else
			echo "[$logdt] Empty script file after processing" >> $LogFileName
			cntgiip=999
			# Exit instead of continue (no loop)
		fi
	else
		echo "[$logdt] No queue" >> $LogFileName
		
		# Save queue check to KVS (no response)
		queue_check_details="{\"api_response\":\"empty\",\"has_queue\":false,\"mssn\":0,\"script_source\":\"none\"}"
		save_execution_log "queue_check" "$queue_check_details"
	fi

	cmpFile=`cat $tmpFileName`
	ErrChk=`cat ${tmpFileName} | grep "HTTP Error"`
	if [ "${ErrChk}" != "" ]; then
		rm -f $tmpFileName
	    echo "[$logdt]Stop by error. ${ErrChk}" >> $LogFileName
	    
	    # Save error to KVS
	    error_details="{\"error_type\":\"script_error\",\"error_message\":\"HTTP Error in script\",\"error_code\":1,\"context\":\"script_execution\"}"
	    save_execution_log "error" "$error_details"
	    
		exit 0
	else
		if [ -s ${tmpFileName} ];then
			n=`cat ${tmpFileName} 2>/dev/null | grep 'expect=' | wc -l`
			if [ ${n} -ge 1 ]; then
				# Execute expect script
				script_start_time=$(date +%s)
				expect ./giipTmpScript.sh >> $LogFileName 2>&1
				script_exit_code=$?
				script_end_time=$(date +%s)
				script_duration=$((script_end_time - script_start_time))
				
				echo "[$logdt]Executed expect script (exit_code=${script_exit_code}, duration=${script_duration}s)..." >> $LogFileName
				
				# Save script execution to KVS
				exec_details="{\"script_type\":\"expect\",\"exit_code\":${script_exit_code},\"execution_time_seconds\":${script_duration}}"
				save_execution_log "script_execution" "$exec_details"
				
				rm -f $tmpFileName
			else
				# Execute bash script
				script_start_time=$(date +%s)
				sh ./giipTmpScript.sh >> $LogFileName 2>&1
				script_exit_code=$?
				script_end_time=$(date +%s)
				script_duration=$((script_end_time - script_start_time))
				
				echo "[$logdt]Executed bash script (exit_code=${script_exit_code}, duration=${script_duration}s)..." >> $LogFileName
				
				# Save script execution to KVS
				exec_details="{\"script_type\":\"bash\",\"exit_code\":${script_exit_code},\"execution_time_seconds\":${script_duration}}"
				save_execution_log "script_execution" "$exec_details"
				
				rm -f $tmpFileName
			fi
		else
			echo "[$logdt]Work Done $giipagentdelay" >> $LogFileName
	        	#sleep $giipagentdelay
			cntgiip=999
		fi
	fi
	rm -f $tmpFileName
# End of single execution (no loop)

# Save Agent shutdown to KVS
if [ ${cntgiip} -ge 4 ]; then
        if [ ${cntgiip} -eq 999 ]; then
                echo "[$logdt]All process was done" >> $LogFileName
                
                # Save shutdown to KVS (normal completion)
                shutdown_details="{\"reason\":\"normal\",\"process_count\":${cntgiip},\"uptime_seconds\":0}"
                save_execution_log "shutdown" "$shutdown_details"
        else
                echo "[$logdt]terminate by process count $cntgiip" >> $LogFileName
                
                # Save shutdown to KVS (duplicate process)
                shutdown_details="{\"reason\":\"duplicate_process\",\"process_count\":${cntgiip},\"uptime_seconds\":0}"
                save_execution_log "shutdown" "$shutdown_details"
        fi
	ret=`ps aux | grep giipAgent2.sh | grep -v grep`
	echo "$ret" >> $LogFileName
fi

rm -f $tmpFileName
