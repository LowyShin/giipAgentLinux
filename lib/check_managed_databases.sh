#!/bin/bash
# Check Managed Databases Module
# Purpose: Query tManagedDatabase, perform health checks, collect DPA data, update last_check_dt
# Called by: gateway.sh when is_gateway=1

# Load DPA modules (provide collect_*_dpa functions)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/dpa_mysql.sh"
source "${SCRIPT_DIR}/dpa_mssql.sh"
source "${SCRIPT_DIR}/dpa_postgresql.sh"
source "${SCRIPT_DIR}/net3d_db.sh"
source "${SCRIPT_DIR}/http_health_check.sh"

# Load DB check modules (provide perform_check_* functions)
source "${SCRIPT_DIR}/db_check_mysql.sh"
source "${SCRIPT_DIR}/db_check_mssql.sh"
source "${SCRIPT_DIR}/db_check_postgresql.sh"
source "${SCRIPT_DIR}/db_check_redis.sh"
source "${SCRIPT_DIR}/db_check_mongodb.sh"
source "${SCRIPT_DIR}/db_check_http.sh"

# Function: Check managed databases and update health status
# Requires: lssn, sk, apiaddrv2, apiaddrcode (from config)
# Returns: 0 on success, 1 on error
check_managed_databases() {
	echo "[Gateway] 🔍 Checking managed databases..." >&2
	
	local temp_file="/tmp/managed_db_api_response_$$.json"
	local text="GatewayManagedDatabaseList lssn"
	local jsondata="{\"lssn\":${lssn}}"
	
	# DEBUG: API 호출 파라미터 표시
	echo "[Gateway-DB-API] 📤 Calling API..." >&2
	echo "[Gateway-DB-API]   text: $text" >&2
	echo "[Gateway-DB-API]   token: ${sk:0:20}..." >&2
	echo "[Gateway-DB-API]   jsondata: $jsondata" >&2
	echo "[Gateway-DB-API]   endpoint: ${apiaddrv2}?code=${apiaddrcode:0:20}..." >&2
	
	# Fetch managed database list from API
	wget -O "$temp_file" --quiet \
		--post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"${apiaddrv2}?code=${apiaddrcode}" \
		--no-check-certificate 2>&1
	
	# DEBUG: API 응답 확인
	if [ -s "$temp_file" ]; then
		local file_size=$(wc -c < "$temp_file")
		echo "[Gateway-DB-API] 📥 Response received: ${file_size} bytes" >&2
		echo "[Gateway-DB-API] 📄 Response preview (first 500 chars):" >&2
		head -c 500 "$temp_file" >&2
		echo "" >&2
		echo "[Gateway-DB-API] 💾 Full response saved to: $temp_file" >&2
	else
		echo "[Gateway] ⚠️  Failed to fetch managed databases from DB" >&2
		return 1
	fi
	
	# Parse JSON - Extract "data" array using external Python script
	local db_list=$(cat "$temp_file" | python3 "${SCRIPT_DIR}/parse_managed_db_list.py")

	# Note: $temp_file will be cleaned up by cleanup.sh
	
	if [ -z "$db_list" ]; then
		echo "[Gateway] ⚠️  No databases in response data array" >&2
		return 0
	fi
	
	local db_count=$(echo "$db_list" | grep -c '"mdb_id"')
	echo "[Gateway] 📊 Found $db_count managed database(s)" >&2
	
	# Collect required DB types using external Python script
	local db_types=$(echo "$db_list" | python3 "${SCRIPT_DIR}/extract_db_types.py")

	
	# Check and install required DB clients
	for db_type in $db_types; do
		case "$db_type" in
			MySQL|MariaDB)
				if ! command -v mysql >/dev/null 2>&1; then
					echo "[Gateway] Installing MySQL client..." >&2
					check_mysql_client
				fi
				;;
			PostgreSQL)
				if ! command -v psql >/dev/null 2>&1; then
					echo "[Gateway] PostgreSQL client not found, skipping installation (CentOS 7 EOL)" >&2
					# check_psql_client  # Disabled: CentOS 7 mirrors unavailable
				fi
				;;
			MSSQL)
				if ! command -v sqlcmd >/dev/null 2>&1; then
					echo "[Gateway] Installing MSSQL client..." >&2
					check_mssql_client
				fi
				;;
			Redis)
				if ! command -v redis-cli >/dev/null 2>&1; then
					echo "[Gateway] Installing Redis client..." >&2
					check_redis_client
				fi
				;;
			MongoDB)
				if ! command -v mongosh >/dev/null 2>&1 && ! command -v mongo >/dev/null 2>&1; then
					echo "[Gateway] Installing MongoDB client..." >&2
					check_mongo_client
				fi
				;;
		esac
	done
	
	# Process each database
	echo "[Gateway] 🔄 Processing databases..." >&2
	
	# Collect all check results
	local check_results_file="/tmp/db_check_results_$$.jsonl"
	> "$check_results_file"  # Clear file
	
	while IFS= read -r db_json; do
		[ -z "$db_json" ] && continue
		
		# Extract all fields from JSON using external Python script
		local fields=$(echo "$db_json" | python3 "${SCRIPT_DIR}/parse_db_json_fields.py")
		[ $? -ne 0 ] && continue
		
		IFS=$'\t' read -r mdb_id db_type db_name db_host db_port db_user db_password db_database \
			http_enabled http_url http_method http_timeout http_expected <<< "$fields"
		
		echo "[Gateway]   Checking: $db_name ($db_type)" >&2
		
		# Call appropriate check function based on db_type
		local check_result=""
		case "$db_type" in
			MySQL|MariaDB)
				check_result=$(perform_check_mysql "$mdb_id" "$db_name" "$db_host" "$db_port" "$db_user" "$db_password" "$db_database")
				;;
			PostgreSQL)
				check_result=$(perform_check_postgresql "$mdb_id" "$db_name" "$db_host" "$db_port" "$db_user" "$db_password" "$db_database")
				;;
			MSSQL)
				check_result=$(perform_check_mssql "$mdb_id" "$db_name" "$db_host" "$db_port" "$db_user" "$db_password" "$db_database")
				;;
			Redis)
				check_result=$(perform_check_redis "$mdb_id" "$db_name" "$db_host" "$db_port" "$db_password")
				;;
			MongoDB)
				check_result=$(perform_check_mongodb "$mdb_id" "$db_name" "$db_host" "$db_port" "$db_user" "$db_password" "$db_database")
				;;
			HTTP)
				# Fields already extracted above
				check_result=$(perform_check_http "$mdb_id" "$db_name" "$http_enabled" "$http_url" "$http_method" "$http_timeout" "$http_expected")
				;;
			*)
				echo "[Gateway]   ⚠️  Unknown DB type: $db_type" >&2
				continue
				;;
		esac
		
		# Save result and log status
		if [ -n "$check_result" ]; then
			echo "$check_result" >> "$check_results_file"
			local status=$(echo "$check_result" | python3 "${SCRIPT_DIR}/extract_check_status.py")
			echo "[Gateway]   Result: $db_name - $status" >&2
		fi
	done <<< "$db_list"
	
	# Send all results to API (MdbStatsUpdate)
	if [ -s "$check_results_file" ]; then
		echo "[Gateway] 📤 Sending stats to API..." >&2
		
		# Convert to MdbStatsUpdate format
		local stats_json=$(cat "$check_results_file" | python3 "${SCRIPT_DIR}/convert_to_mdb_stats.py")
		
		if [ -n "$stats_json" ] && [ "$stats_json" != "[]" ]; then
			local text="MdbStatsUpdate 0"
			
			# URL encode using jq (match kvs.sh method)
			local encoded_jsondata=$(printf '%s' "$stats_json" | jq -sRr '@uri')
			
			local api_response=$(wget -O - --quiet \
				--post-data="text=${text}&token=${sk}&jsondata=${encoded_jsondata}" \
				--header="Content-Type: application/x-www-form-urlencoded" \
				"${apiaddrv2}?code=${apiaddrcode}" \
				--no-check-certificate 2>&1)
			
			if echo "$api_response" | grep -q '"RstVal":"200"'; then
				echo "[Gateway] ✅ Stats saved successfully" >&2
			else
				echo "[Gateway] ⚠️  API response: $api_response" >&2
			fi
		fi
		
		# Note: check_results_file will be cleaned up by cleanup.sh
	fi
	
	echo "[Gateway] ✅ Database checks completed" >&2
	return 0

}


# Export function for use in other scripts
export -f check_managed_databases
