#!/bin/bash
# giipAgent Ver. 1.4
sv="1.80"
# Written by Lowy Shin at 20140922
# Supported OS : MacOS, CentOS, Ubuntu, Some Linux
# 190611 Lowy, Change agent download method to git repository.
# 20251104 Lowy, Add Gateway mode support with auto-dependency installation

# Usable giip variables =========
# {{today}} : Replace today to "YYYYMMDD"

# User Variables ===============================================
. ../giipAgent.cnf

if [ "${giipagentdelay}" = "" ];then
	giipagentdelay="60"
fi

# Gateway mode default
if [ "${gateway_mode}" = "" ];then
	gateway_mode="0"
fi

# Gateway heartbeat interval (seconds) - how often to collect remote server info
if [ "${gateway_heartbeat_interval}" = "" ];then
	gateway_heartbeat_interval="300"  # Default: 5 minutes
fi

# Self Check
cntgiip=`ps aux | grep giipAgent.sh | grep -v grep | wc -l`

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
	
	# Use GIIP API to get server list
	local temp_file="/tmp/gateway_servers_$$.json"
	
	# Build API request (using giipApiSk endpoint with text parameter)
	local api_url="${apiaddr}/api/giipApiSk"
	local text="GatewayRemoteServerListForAgent ${lssn}"
	
	# Fetch from API
	wget -O "$temp_file" \
		--post-data="text=${text}&token=${sk}&usertoken=${sk}" \
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
	local api_url="${apiaddr}/api/giipApiSk"
	local text="GatewayDBQueryList ${lssn}"
	
	# Fetch from API
	wget -O "$temp_file" \
		--post-data="text=${text}&token=${sk}&usertoken=${sk}" \
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
			
			local python_helper="${GIIP_HOME}/scripts/db_query_helper.py"
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
			
			local python_helper="${GIIP_HOME}/scripts/db_query_helper.py"
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
		
		# Call KVS API
		local api_url="${apiaddr}/api/giipApiSk"
		local text="KVSPut kType kKey kFactor"
		local jsondata="{\"kType\":\"${kvs_type}\",\"kKey\":\"${kvs_key}\",\"kFactor\":$(echo "${kvs_value}" | jq -Rs .)}"
		
		wget -O /dev/null \
			--post-data="text=${text}&token=${sk}&usertoken=${sk}&jsondata=${jsondata}" \
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
			continue
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

# Function: Get queue for specific server
get_remote_queue() {
	local lssn=$1
	local hostname=$2
	local os=$3
	local output_file=$4
	
	local download_url=`echo "${apiaddr}/api/cqe/cqequeueget03.asp?sk=$sk&lssn=$lssn&hn=${hostname}&os=$os&df=os&sv=${sv}" | sed -e "s/ /\%20/g"`
	
	wget -O "$output_file" "$download_url" --no-check-certificate -q
	
	if [ -s "$output_file" ]; then
		dos2unix "$output_file" 2>/dev/null
		return 0
	else
		return 1
	fi
}

# Function: Process gateway servers
process_gateway_servers() {
	local serverlist="${gateway_serverlist}"
	local tmpdir="/tmp/giipAgent_gateway_$$"
	
	mkdir -p "$tmpdir"
	
	if [ ! -f "$serverlist" ]; then
		echo "[Gateway] Error: Server list not found: $serverlist"
		return 1
	fi
	
	local logdt=$(date '+%Y%m%d%H%M%S')
	echo "[${logdt}] [Gateway] Starting server processing cycle..." >> $LogFileName
	
	while IFS=',' read -r hostname lssn ssh_host ssh_user ssh_port ssh_key ssh_password os_info enabled; do
		# Skip comments and empty lines
		[[ $hostname =~ ^#.*$ ]] && continue
		[[ -z $hostname ]] && continue
		[[ $enabled == "0" ]] && continue
		
		# Clean variables
		hostname=$(echo $hostname | xargs)
		lssn=$(echo $lssn | xargs)
		ssh_host=$(echo $ssh_host | xargs)
		ssh_user=$(echo $ssh_user | xargs)
		ssh_port=$(echo $ssh_port | xargs)
		ssh_key=$(echo $ssh_key | xargs)
		ssh_password=$(echo $ssh_password | xargs)
		os_info=$(echo $os_info | xargs)
		
		# Defaults
		[ -z "$ssh_port" ] && ssh_port="22"
		[ -z "$ssh_user" ] && ssh_user="root"
		[ -z "$os_info" ] && os_info="Linux"
		
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
				continue
			fi
			
			echo "[${logdt}] [Gateway]   📥 Queue received, executing..." >> $LogFileName
			
			# Execute on remote server
			execute_remote_command "$ssh_host" "$ssh_user" "$ssh_port" "$ssh_key" "$ssh_password" "$tmpfile" >> $LogFileName
			
			if [ $? -eq 0 ]; then
				echo "[${logdt}] [Gateway]   ✅ Success" >> $LogFileName
			else
				echo "[${logdt}] [Gateway]   ❌ Failed" >> $LogFileName
			fi
			
			rm -f "$tmpfile"
		else
			echo "[${logdt}] [Gateway]   ⏸️  No queue" >> $LogFileName
		fi
		
	done < "$serverlist"
	
	rm -rf "$tmpdir"
	logdt=$(date '+%Y%m%d%H%M%S')
	echo "[${logdt}] [Gateway] Cycle completed" >> $LogFileName
}

# ============================================================================
# End of Gateway Mode Functions
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

LogFileName="${LOG_DIR}/giipAgent_$Today.log"
lwDownloadURL=`echo "${apiaddr}/api/cqe/cqequeueget03.asp?sk=$sk&lssn=$lssn&hn=${hn}&os=$os&df=os&sv=${sv}" | sed -e "s/ /\%20/g"`
echo $lwDownloadURL

# Add Server
if [ "${lssn}" = "0" ];then
	curl -o $tmpFileName "$lwDownloadURL"
	lssn=`cat ${tmpFileName}`
	cnfdmp=`cat ./giipAgent.cnf | sed -e "s|lssn=\"0\"|lssn=\"${lssn}\"|g"`
	echo "${cnfdmp}" >giipAgent.cnf
	rm -f $tmpFileName
	lwDownloadURL=`echo "${apiaddr}/api/cqe/cqequeueget03.asp?sk=$sk&lssn=$lssn&hn=${hn}&os=$os&df=os&sv=${sv}" | sed -e "s/ /\%20/g"`
fi

# ============================================================================
# Gateway Mode: Check and initialize
# ============================================================================
if [ "${gateway_mode}" = "1" ]; then
	logdt=`date '+%Y%m%d%H%M%S'`
	echo "[$logdt] ========================================" >> $LogFileName
	echo "[$logdt] Starting GIIP Agent in GATEWAY MODE" >> $LogFileName
	echo "[$logdt] Version: ${sv}" >> $LogFileName
	echo "[$logdt] Gateway LSSN: ${lssn}" >> $LogFileName
	echo "[$logdt] ========================================" >> $LogFileName
	
	# Save gateway startup status to KVS
	startup_status="{\"status\":\"started\",\"version\":\"${sv}\",\"lssn\":${lssn},\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"mode\":\"gateway\"}"
	kvs_url="${apiaddr}/api/giipApiSk"
	kvs_text="KVSPut kType kKey kFactor"
	kvs_data="{\"kType\":\"gateway_status\",\"kKey\":\"gateway_${lssn}_startup\",\"kFactor\":${startup_status}}"
	wget -O /dev/null --post-data="text=${kvs_text}&token=${sk}&jsondata=$(echo ${kvs_data} | sed 's/ /%20/g')" "${kvs_url}" --no-check-certificate -q 2>&1
	
	# Check and install sshpass
	check_sshpass
	if [ $? -ne 0 ]; then
		echo "[$logdt] Error: Failed to setup sshpass" >> $LogFileName
		
		# Save error to KVS
		error_status="{\"status\":\"error\",\"error\":\"Failed to setup sshpass\",\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}"
		kvs_data="{\"kType\":\"gateway_status\",\"kKey\":\"gateway_${lssn}_error\",\"kFactor\":${error_status}}"
		wget -O /dev/null --post-data="text=${kvs_text}&token=${sk}&jsondata=$(echo ${kvs_data} | sed 's/ /%20/g')" "${kvs_url}" --no-check-certificate -q 2>&1
		
		exit 1
	fi
	
	# Check and install database clients
	check_db_clients
	
	# Initial fetch from API
	echo "[$logdt] [Gateway] Fetching initial server list from Web UI..." >> $LogFileName
	sync_gateway_servers
	
	# Fetch DB queries
	echo "[$logdt] [Gateway-DB] Fetching database query list from Web UI..." >> $LogFileName
	sync_db_queries
	
	# Check if we got any servers
	server_count=0
	if [ ! -f "${gateway_serverlist}" ]; then
		echo "[$logdt] [Gateway] Warning: No server list file created" >> $LogFileName
		echo "[$logdt] [Gateway] Please configure remote servers via Web UI" >> $LogFileName
		echo "[$logdt] [Gateway] Go to: lsvrdetail page > Gateway Settings" >> $LogFileName
	else
		server_count=$(grep -v "^#" "${gateway_serverlist}" | grep -v "^$" | wc -l)
		echo "[$logdt] [Gateway] Found ${server_count} servers to manage" >> $LogFileName
	fi
	
	# Save initial sync status to KVS
	sync_status="{\"status\":\"synced\",\"server_count\":${server_count},\"timestamp\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}"
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
			
			# Save heartbeat trigger to KVS
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
				
				# Save heartbeat start to KVS
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
		cntgiip=`ps aux | grep giipAgent.sh | grep -v grep | wc -l`
	done
	
	logdt=`date '+%Y%m%d%H%M%S'`
	if [ ${cntgiip} -ge 4 ]; then
		echo "[$logdt] [Gateway] Terminated by process count $cntgiip" >> $LogFileName
		ret=`ps aux | grep giipAgent.sh | grep -v grep`
		echo "$ret" >> $LogFileName
	fi
	
	exit 0
fi

# ============================================================================
# Normal Mode: Local agent execution
# ============================================================================

# self process count = 2
while [ ${cntgiip} -le 3 ];
do

	#curl -o $tmpFileName "$lwDownloadURL"
	wget -O $tmpFileName "$lwDownloadURL" --no-check-certificate

	if [ -s ${tmpFileName} ];then
		ls -l $tmpFileName
		dos2unix $tmpFileName
		echo "[$logdt] Downloaded queue... " >> $LogFileName
	else
		echo "[$logdt] No queue" >> $LogFileName
	fi

	cmpFile=`cat $tmpFileName`
	ErrChk=`cat ${tmpFileName} | grep "HTTP Error"`
	if [ "${ErrChk}" != "" ]; then
		rm -f $tmpFileName
	    echo "[$logdt]Stop by error. ${ErrChk}" >> $LogFileName
		exit 0
	else
		if [ -s ${tmpFileName} ];then
			n=`cat giipTmpScript.sh | grep 'expect=' | wc -l`
			if [ ${n} -ge 1 ]; then
				expect ./giipTmpScript.sh >> $LogFileName
				echo "[$logdt]Executed expect script..." >> $LogFileName
				rm -f $tmpFileName
			else
				sh ./giipTmpScript.sh >> $LogFileName
				echo "[$logdt]Executed script..." >> $LogFileName
				rm -f $tmpFileName
			fi
		else
			echo "[$logdt]Work Done $giipagentdelay" >> $LogFileName
	        	#sleep $giipagentdelay
			cntgiip=999
		fi
	fi
	rm -f $tmpFileName
done
if [ ${cntgiip} -ge 4 ]; then
        if [ ${cntgiip} -eq 999 ]; then
                echo "[$logdt]All process was done" >> $LogFileName
        else
                echo "[$logdt]terminate by process count $cntgiip" >> $LogFileName
        fi
	ret=`ps aux | grep giipAgent.sh | grep -v grep`
	echo "$ret" >> $LogFileName
fi

rm -f $tmpFileName
