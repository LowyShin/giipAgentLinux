#!/bin/bash
# giipAgent Gateway Mode Library
# Version: 2.00
# Date: 2025-01-10
# Purpose: Gateway mode functions for managing remote servers and database queries
# Rule: Follow giipapi_rules.md - text contains parameter names only, jsondata contains actual values

# ============================================================================
# Server Management Functions
# ============================================================================

# Function: Get remote servers from database (real-time query, no cache)
# Per GATEWAY_CONFIG_PHILOSOPHY.md: Database as Single Source of Truth
# Returns: temp file path with JSON data (caller must delete!)
get_gateway_servers() {
	local temp_file="/tmp/gateway_servers_$$.json"
	local api_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && api_url="${api_url}?code=${apiaddrcode}"
	
	local text="GatewayRemoteServerListForAgent lssn"
	local jsondata="{\"lssn\":${lssn}}"
	
	wget -O "$temp_file" \
		--post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"$api_url" \
		--no-check-certificate -q 2>&1
	
	if [ ! -s "$temp_file" ]; then
		echo "[Gateway] ⚠️  Failed to fetch servers from DB" >&2
		rm -f "$temp_file"
		return 1
	fi
	
	# Check for error response
	local err_check=$(cat "$temp_file" | grep -i "rstval.*40[0-9]")
	if [ -n "$err_check" ]; then
		echo "[Gateway] ⚠️  API error response" >&2
		rm -f "$temp_file"
		return 1
	fi
	
	echo "$temp_file"
	return 0
}

# Legacy function removed: sync_gateway_servers
# Reason: Database as Single Source of Truth - no CSV caching

# Function: Get DB queries from database (real-time query, no cache)
# Returns: temp file path with JSON data (caller must delete!)
get_db_queries() {
	local temp_file="/tmp/gateway_db_queries_$$.json"
	local api_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && api_url="${api_url}?code=${apiaddrcode}"
	
	local text="GatewayDBQueryList lssn"
	local jsondata="{\"lssn\":${lssn}}"
	
	wget -O "$temp_file" \
		--post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"$api_url" \
		--no-check-certificate -q 2>&1
	
	if [ ! -s "$temp_file" ]; then
		rm -f "$temp_file"
		return 1
	fi
	
	echo "$temp_file"
	return 0
}

# Legacy function removed: sync_db_queries
# Reason: Database as Single Source of Truth - no CSV caching

# Function: Get managed databases from tManagedDatabase (real-time query, no cache)
# Returns: temp file path with JSON data (caller must delete!)
get_managed_databases() {
	local temp_file="/tmp/managed_databases_$$.json"
	local api_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && api_url="${api_url}?code=${apiaddrcode}"
	
	local text="GatewayManagedDatabaseList lssn"
	local jsondata="{\"lssn\":${lssn}}"
	
	wget -O "$temp_file" \
		--post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"$api_url" \
		--no-check-certificate -q 2>&1
	
	if [ ! -s "$temp_file" ]; then
		echo "[Gateway] ⚠️  Failed to fetch managed databases from DB" >&2
		rm -f "$temp_file"
		return 1
	fi
	
	# Check for error response
	local err_check=$(cat "$temp_file" | grep -i "rstval.*40[0-9]")
	if [ -n "$err_check" ]; then
		echo "[Gateway] ⚠️  API error response" >&2
		rm -f "$temp_file"
		return 1
	fi
	
	echo "$temp_file"
	return 0
}

# ============================================================================
# Remote Execution Functions
# ============================================================================

# Function: Execute command on remote server
execute_remote_command() {
	local remote_host=$1
	local remote_user=$2
	local remote_port=$3
	local ssh_key=$4
	local ssh_password=$5
	local script_file=$6
	
	local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
	
	if [ -n "${ssh_password}" ]; then
		if ! command -v sshpass &> /dev/null; then
			echo "  ❌ sshpass not available"
			return 1
		fi
		
		sshpass -p "${ssh_password}" scp ${ssh_opts} -P ${remote_port} \
		    ${script_file} ${remote_user}@${remote_host}:/tmp/giipTmpScript.sh 2>&1 | head -5
		
		[ $? -ne 0 ] && return 1
		
		sshpass -p "${ssh_password}" ssh ${ssh_opts} -p ${remote_port} \
		    ${remote_user}@${remote_host} \
		    "chmod +x /tmp/giipTmpScript.sh && /tmp/giipTmpScript.sh && rm -f /tmp/giipTmpScript.sh" 2>&1 | head -20
	elif [ -n "${ssh_key}" ] && [ -f "${ssh_key}" ]; then
		scp ${ssh_opts} -i ${ssh_key} -P ${remote_port} \
		    ${script_file} ${remote_user}@${remote_host}:/tmp/giipTmpScript.sh 2>&1 | head -5
		
		[ $? -ne 0 ] && return 1
		
		ssh ${ssh_opts} -i ${ssh_key} -p ${remote_port} \
		    ${remote_user}@${remote_host} \
		    "chmod +x /tmp/giipTmpScript.sh && /tmp/giipTmpScript.sh && rm -f /tmp/giipTmpScript.sh" 2>&1 | head -20
	else
		echo "  ❌ No authentication method available"
		return 1
	fi
	
	return $?
}

# ============================================================================
# Queue Management Functions
# ============================================================================

# Function: Get script by mssn (from repository)
get_script_by_mssn() {
	local mssn=$1
	local output_file=$2
	
	local api_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && api_url="${api_url}?code=${apiaddrcode}"
	
	local text="CQERepoScript mssn"
	local jsondata="{\"mssn\":${mssn}}"
	
	wget -O "$output_file" \
		--post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"$api_url" \
		--no-check-certificate -q 2>&1
	
	if [ -s "$output_file" ]; then
		dos2unix "$output_file" 2>/dev/null
		return 0
	fi
	return 1
}

# Function: Get queue for specific server
get_remote_queue() {
	local lssn=$1
	local hostname=$2
	local os=$3
	local output_file=$4
	
	local api_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && api_url="${api_url}?code=${apiaddrcode}"
	
	local text="CQEQueueGet lssn hostname os op"
	local jsondata="{\"lssn\":${lssn},\"hostname\":\"${hostname}\",\"os\":\"${os}\",\"op\":\"op\"}"
	
	wget -O "$output_file" \
		--post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"$api_url" \
		--no-check-certificate -q 2>&1
	
	if [ -s "$output_file" ]; then
		local is_json=$(cat "$output_file" | grep -o '^{.*}$')
		if [ -n "$is_json" ]; then
			local rstval=$(cat "$output_file" | grep -o '"RstVal":"[^"]*"' | sed 's/"RstVal":"//; s/"$//' | head -1)
			local script_body=$(cat "$output_file" | grep -o '"ms_body":"[^"]*"' | sed 's/"ms_body":"//; s/"$//' | sed 's/\\n/\n/g')
			local mssn=$(cat "$output_file" | grep -o '"mssn":[0-9]*' | sed 's/"mssn"://' | head -1)
			
			[ "$rstval" = "404" ] && return 1
			
			if [ "$rstval" = "200" ]; then
				if [ -n "$script_body" ] && [ "$script_body" != "null" ]; then
					echo "$script_body" > "$output_file"
					dos2unix "$output_file" 2>/dev/null
					return 0
				elif [ -n "$mssn" ] && [ "$mssn" != "null" ] && [ "$mssn" != "0" ]; then
					get_script_by_mssn "$mssn" "$output_file"
					return $?
				fi
			fi
			return 1
		else
			dos2unix "$output_file" 2>/dev/null
			return 0
		fi
	fi
	return 1
}

# Function: Process gateway servers
process_gateway_servers() {
	local tmpdir="/tmp/giipAgent_gateway_$$"
	mkdir -p "$tmpdir"
	
	# Get servers from DB (real-time query, no cache)
	local server_list_file=$(get_gateway_servers)
	if [ $? -ne 0 ] || [ ! -f "$server_list_file" ]; then
		echo "[Gateway] ⚠️  Failed to fetch servers from DB" >&2
		rm -rf "$tmpdir"
		return 1
	fi
	
	local logdt=$(date '+%Y%m%d%H%M%S')
	echo "[${logdt}] [Gateway] Starting server processing cycle..." >> $LogFileName
	
	# Parse JSON and process each server
	cat "$server_list_file" | grep -o '{[^}]*}' | while read -r server_json; do
		hostname=$(echo "$server_json" | grep -o '"hostname"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		lssn=$(echo "$server_json" | grep -o '"lssn"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
		ssh_host=$(echo "$server_json" | grep -o '"ssh_host"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		ssh_user=$(echo "$server_json" | grep -o '"ssh_user"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		ssh_port=$(echo "$server_json" | grep -o '"ssh_port"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
		ssh_key_path=$(echo "$server_json" | grep -o '"ssh_key_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		ssh_password=$(echo "$server_json" | grep -o '"ssh_password"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		os_info=$(echo "$server_json" | grep -o '"os_info"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		enabled=$(echo "$server_json" | grep -o '"enabled"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
		
		# Skip disabled servers
		[[ -z $hostname ]] && continue
		[[ $enabled == "0" ]] && continue
		
		# Set defaults
		[ -z "$ssh_port" ] && ssh_port="22"
		[ -z "$ssh_user" ] && ssh_user="root"
		[ -z "$os_info" ] && os_info="Linux"
		
		logdt=$(date '+%Y%m%d%H%M%S')
		echo "[${logdt}] [Gateway] Processing: $hostname (LSSN:$lssn)" >> $LogFileName
		
		local tmpfile="${tmpdir}/script_${lssn}.sh"
		get_remote_queue "$lssn" "$hostname" "$os_info" "$tmpfile"
		
		if [ -s "$tmpfile" ]; then
			local err_check=$(cat "$tmpfile" | grep "HTTP Error")
			if [ -n "$err_check" ]; then
				rm -f "$tmpfile"
				continue
			fi
			
			execute_remote_command "$ssh_host" "$ssh_user" "$ssh_port" "$ssh_key_path" "$ssh_password" "$tmpfile" >> $LogFileName
			rm -f "$tmpfile"
		fi
	done
	
	# Clean up
	rm -f "$server_list_file"
	rm -rf "$tmpdir"
	
	logdt=$(date '+%Y%m%d%H%M%S')
	echo "[${logdt}] [Gateway] Cycle completed" >> $LogFileName
}

# ============================================================================
# Managed Database Check Functions
# ============================================================================

# Function: Check managed databases (tManagedDatabase)
# Purpose: Auto-check DB connection and update last_check_dt
check_managed_databases() {
	echo "[Gateway] 🔍 Checking managed databases..." >&2
	
	local db_list_file=$(get_managed_databases)
	if [ -z "$db_list_file" ] || [ ! -f "$db_list_file" ]; then
		echo "[Gateway] ⚠️  No managed databases found" >&2
		return 0
	fi
	
	local db_count=$(cat "$db_list_file" | grep -o '"mdb_id"' | wc -l)
	echo "[Gateway] 📊 Found $db_count managed database(s)" >&2
	
	# Temporary file for health results
	local health_results_file=$(mktemp)
	echo "[" > "$health_results_file"
	
	# Parse JSON and check each database
	local first=true
	while read -r db_json; do
		mdb_id=$(echo "$db_json" | grep -o '"mdb_id"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
		db_name=$(echo "$db_json" | grep -o '"db_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		db_type=$(echo "$db_json" | grep -o '"db_type"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		db_host=$(echo "$db_json" | grep -o '"db_host"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		db_port=$(echo "$db_json" | grep -o '"db_port"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
		
		[[ -z $mdb_id ]] && continue
		[[ -z $db_name ]] && continue
		
		logdt=$(date '+%Y%m%d%H%M%S')
		echo "[${logdt}] [Gateway] Checking DB: $db_name (mdb_id:$mdb_id, type:$db_type)" >> $LogFileName
		
		# Test connection based on DB type
		local check_status="success"
		local check_message=""
		
		case "$db_type" in
			MySQL|MariaDB)
				check_message="MySQL/MariaDB check placeholder - to be implemented"
				;;
			PostgreSQL)
				check_message="PostgreSQL check placeholder - to be implemented"
				;;
			MSSQL)
				# pyodbc should be installed by db_clients.sh
				if ! python3 -c "import pyodbc" 2>/dev/null; then
					echo "[Gateway-MSSQL] ⚠️  pyodbc not available, skipping MSSQL check for $db_name" >&2
					check_status="warning"
					check_message="pyodbc not available - MSSQL check skipped"
				else
					check_message="MSSQL check placeholder - to be implemented"
				fi
				;;
			*)
				check_message="DB type $db_type not supported yet"
				check_status="info"
				;;
		esac
		
		# Log result to KVS
		local kv_key="managed_db_check_${mdb_id}"
		local kv_value="{\"mdb_id\":${mdb_id},\"db_name\":\"${db_name}\",\"db_type\":\"${db_type}\",\"check_status\":\"${check_status}\",\"check_message\":\"${check_message}\",\"check_time\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}"
		
		save_execution_log "managed_db_check" "$kv_value" "$kv_key"
		
		# Append to health results file
		if [ "$first" = true ]; then
			echo -n "{\"mdb_id\":${mdb_id},\"status\":\"${check_status}\",\"message\":\"${check_message}\",\"response_time_ms\":0}" >> "$health_results_file"
			first=false
		else
			echo -n ",{\"mdb_id\":${mdb_id},\"status\":\"${check_status}\",\"message\":\"${check_message}\",\"response_time_ms\":0}" >> "$health_results_file"
		fi
		
		echo "[${logdt}] [Gateway]   → Status: $check_status - $check_message" >> $LogFileName
	done < <(cat "$db_list_file" | grep -o '{[^}]*}')
	
	echo "]" >> "$health_results_file"
	
	# Read health results
	local health_results=$(cat "$health_results_file")
	
	logdt=$(date '+%Y%m%d%H%M%S')
	echo "[${logdt}] [Gateway] Health results JSON: $health_results" >> $LogFileName
	
	# Update tManagedDatabase.last_check_dt via API
	if [ "$health_results" != "[]" ] && [ "$health_results" != "[
]" ]; then
		echo "[Gateway] 📤 Updating tManagedDatabase.last_check_dt via API..." >&2
		local temp_file=$(mktemp)
		wget -O "$temp_file" --quiet \
			--post-data="text=ManagedDatabaseHealthUpdate jsondata&token=${sk}&jsondata=${health_results}" \
			"${apiaddrv2}?code=${apiaddrcode}" 2>/dev/null
		
		if [ -f "$temp_file" ]; then
			logdt=$(date '+%Y%m%d%H%M%S')
			echo "[${logdt}] [Gateway] API Response: $(cat "$temp_file")" >> $LogFileName
			echo "[${logdt}] [Gateway] Updated tManagedDatabase.last_check_dt for $db_count database(s)" >> $LogFileName
			rm -f "$temp_file"
		fi
	else
		echo "[Gateway] ⚠️  Skipping API update - health_results is empty" >&2
		logdt=$(date '+%Y%m%d%H%M%S')
		echo "[${logdt}] [Gateway] Skipped API update - health_results='$health_results'" >> $LogFileName
	fi
	
	# Clean up
	rm -f "$db_list_file" "$health_results_file"
	
	logdt=$(date '+%Y%m%d%H%M%S')
	echo "[${logdt}] [Gateway] Managed database check completed" >> $LogFileName
}

# ============================================================================
# Export Functions
# ============================================================================

export -f get_gateway_servers
export -f get_db_queries
export -f get_managed_databases
export -f execute_remote_command
export -f get_script_by_mssn
export -f get_remote_queue
export -f process_gateway_servers
export -f check_managed_databases
