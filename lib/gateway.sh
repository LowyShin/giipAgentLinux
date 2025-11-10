#!/bin/bash
# giipAgent Gateway Mode Library
# Version: 2.00
# Date: 2025-01-10
# Purpose: Gateway mode functions for managing remote servers and database queries
# Rule: Follow giipapi_rules.md - text contains parameter names only, jsondata contains actual values

# ============================================================================
# Server Management Functions
# ============================================================================

# Function: Sync servers from database
sync_gateway_servers() {
	local output_file="${gateway_serverlist}"
	
	echo "[Gateway] Fetching server list from GIIP API..."
	
	local temp_file="/tmp/gateway_servers_$$.json"
	local api_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && api_url="${api_url}?code=${apiaddrcode}"
	
	local text="GatewayRemoteServerListForAgent ${lssn}"
	
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
		rm -f "$temp_file"
		return 0
	fi
	
	# Create CSV header
	cat > "$output_file" << EOF
# Auto-generated from GIIP API at $(date '+%Y-%m-%d %H:%M:%S')
# Gateway LSSN: ${lssn}
# DO NOT EDIT - This file is regenerated from Web UI settings
# hostname,lssn,ssh_host,ssh_user,ssh_port,ssh_key_path,ssh_password,os_info,enabled
EOF
	
	# Parse JSON and create CSV
	cat "$temp_file" | grep -o '{[^}]*}' | while read -r server_json; do
		hostname=$(echo "$server_json" | grep -o '"hostname"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		lssn=$(echo "$server_json" | grep -o '"lssn"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
		ssh_host=$(echo "$server_json" | grep -o '"ssh_host"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		ssh_user=$(echo "$server_json" | grep -o '"ssh_user"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		ssh_port=$(echo "$server_json" | grep -o '"ssh_port"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
		ssh_key_path=$(echo "$server_json" | grep -o '"ssh_key_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		ssh_password=$(echo "$server_json" | grep -o '"ssh_password"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		os_info=$(echo "$server_json" | grep -o '"os_info"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		enabled=$(echo "$server_json" | grep -o '"enabled"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
		
		if [ -n "$hostname" ] && [ -n "$ssh_host" ]; then
			echo "${hostname},${lssn},${ssh_host},${ssh_user},${ssh_port},${ssh_key_path},${ssh_password},${os_info},${enabled}" >> "$output_file"
		fi
	done
	
	rm -f "$temp_file"
	chmod 600 "$output_file"
	
	local server_count=$(grep -v "^#" "$output_file" | grep -v "^$" | wc -l)
	[ $server_count -gt 0 ] && echo "[Gateway] ✅ Fetched $server_count servers from API"
	
	return 0
}

# Function: Sync DB queries from API
sync_db_queries() {
	local output_file="${gateway_db_querylist:-/tmp/gateway_db_queries.csv}"
	local temp_file="/tmp/gateway_db_queries_$$.json"
	local api_url="${apiaddrv2}"
	[ -n "$apiaddrcode" ] && api_url="${api_url}?code=${apiaddrcode}"
	
	wget -O "$temp_file" \
		--post-data="text=GatewayDBQueryList ${lssn}&token=${sk}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"$api_url" \
		--no-check-certificate -q 2>&1
	
	if [ ! -s "$temp_file" ]; then
		rm -f "$temp_file"
		return 0
	fi
	
	cat > "$output_file" << EOF
# Auto-generated DB queries from GIIP API at $(date '+%Y-%m-%d %H:%M:%S')
# gmq_sn,target_lssn,target_hostname,db_type,db_host,db_port,db_user,db_password,db_database,db_instance,query_name,query_text,kvs_key_prefix,kvs_value_format,timeout_seconds,should_execute
EOF
	
	cat "$temp_file" | grep -o '{[^}]*}' | while read -r query_json; do
		gmq_sn=$(echo "$query_json" | grep -o '"gmq_sn"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
		target_lssn=$(echo "$query_json" | grep -o '"target_lssn"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:\s*\([0-9]*\).*/\1/')
		db_type=$(echo "$query_json" | grep -o '"db_type"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		db_host=$(echo "$query_json" | grep -o '"db_host"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		query_text=$(echo "$query_json" | grep -o '"query_text"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/')
		
		if [ -n "$gmq_sn" ] && [ -n "$target_lssn" ] && [ -n "$db_type" ]; then
			query_text=$(echo "$query_text" | sed 's/,/\\,/g' | sed 's/"/\\"/g')
			echo "${gmq_sn},${target_lssn},...,\"${query_text}\",..." >> "$output_file"
		fi
	done
	
	rm -f "$temp_file"
	chmod 600 "$output_file"
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
	
	wget -O "$output_file" \
		--post-data="text=CQERepoScript ${mssn}&token=${sk}" \
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
	
	wget -O "$output_file" \
		--post-data="text=CQEQueueGet ${lssn} ${hostname} ${os} op&token=${sk}" \
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
	local serverlist="${gateway_serverlist}"
	local tmpdir="/tmp/giipAgent_gateway_$$"
	
	mkdir -p "$tmpdir"
	
	[ ! -f "$serverlist" ] && return 1
	
	local logdt=$(date '+%Y%m%d%H%M%S')
	echo "[${logdt}] [Gateway] Starting server processing cycle..." >> $LogFileName
	
	while IFS=',' read -r hostname lssn ssh_host ssh_user ssh_port ssh_key ssh_password os_info enabled; do
		[[ $hostname =~ ^#.*$ ]] && continue
		[[ -z $hostname ]] && continue
		[[ $enabled == "0" ]] && continue
		
		hostname=$(echo $hostname | xargs)
		lssn=$(echo $lssn | xargs)
		ssh_host=$(echo $ssh_host | xargs)
		ssh_user=$(echo $ssh_user | xargs)
		ssh_port=$(echo $ssh_port | xargs)
		ssh_key=$(echo $ssh_key | xargs)
		ssh_password=$(echo $ssh_password | xargs)
		os_info=$(echo $os_info | xargs)
		
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
			
			execute_remote_command "$ssh_host" "$ssh_user" "$ssh_port" "$ssh_key" "$ssh_password" "$tmpfile" >> $LogFileName
			rm -f "$tmpfile"
		fi
	done < "$serverlist"
	
	rm -rf "$tmpdir"
	logdt=$(date '+%Y%m%d%H%M%S')
	echo "[${logdt}] [Gateway] Cycle completed" >> $LogFileName
}

# ============================================================================
# Export Functions
# ============================================================================

export -f sync_gateway_servers
export -f sync_db_queries
export -f execute_remote_command
export -f get_script_by_mssn
export -f get_remote_queue
export -f process_gateway_servers
