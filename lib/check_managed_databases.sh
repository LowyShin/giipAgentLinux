#!/bin/bash
# Check Managed Databases Module
# Purpose: Query tManagedDatabase, perform health checks, update last_check_dt
# Called by: gateway.sh when is_gateway=1

# Function: Check managed databases and update health status
# Requires: lssn, sk, apiaddrv2, apiaddrcode (from config)
# Returns: 0 on success, 1 on error
check_managed_databases() {
	echo "[Gateway] 🔍 Checking managed databases..." >&2
	
	local temp_file=$(mktemp)
	local text="GatewayManagedDatabaseList lssn"
	local jsondata="{\"lssn\":${lssn}}"
	
	# Fetch managed database list from API
	wget -O "$temp_file" --quiet \
		--post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"${apiaddrv2}?code=${apiaddrcode}" \
		--no-check-certificate 2>&1
	
	if [ ! -s "$temp_file" ]; then
		echo "[Gateway] ⚠️  Failed to fetch managed databases from DB" >&2
		rm -f "$temp_file"
		return 1
	fi
	
	# Parse JSON - Extract "data" array using Python (grep cannot handle nested JSON)
	local db_list=$(python3 -c "
import json, sys
try:
    data = json.load(open('$temp_file'))
    if 'data' in data and isinstance(data['data'], list):
        for item in data['data']:
            print(json.dumps(item))
except Exception as e:
    print(f'Error parsing JSON: {e}', file=sys.stderr)
    sys.exit(1)
")
	
	rm -f "$temp_file"
	
	if [ -z "$db_list" ]; then
		echo "[Gateway] ⚠️  No databases in response data array" >&2
		return 0
	fi
	
	local db_count=$(echo "$db_list" | grep -c '"mdb_id"')
	echo "[Gateway] 📊 Found $db_count managed database(s)" >&2
	
	# Build health_results
	local health_results_file=$(mktemp)
	
	echo "$db_list" | while IFS= read -r db_json; do
		[[ -z "$db_json" ]] && continue
		
		# Parse JSON fields using Python
		local mdb_id=$(echo "$db_json" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('mdb_id', ''))")
		local db_name=$(echo "$db_json" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('db_name', ''))")
		local db_type=$(echo "$db_json" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('db_type', ''))")
		local db_host=$(echo "$db_json" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('db_host', ''))")
		
		[[ -z $mdb_id ]] && continue
		[[ -z $db_name ]] && continue
		
		local logdt=$(date '+%Y%m%d%H%M%S')
		echo "[${logdt}] [Gateway] Checking DB: $db_name (mdb_id:$mdb_id, type:$db_type)" >> $LogFileName
		
		# Test connection based on DB type
		local check_status="success"
		local check_message=""
		local performance_json="{}"
		
		case "$db_type" in
			MySQL|MariaDB)
				# MySQL 성능 지표 수집
				if command -v mysql >/dev/null 2>&1; then
					# CPU 사용률 (processlist 기반 추정)
					# 활성 세션 수, 총 연결 수 등 수집
					performance_json="{\"cpu_percent\":0,\"active_sessions\":0,\"total_connections\":0,\"slow_queries\":0}"
					check_message="MySQL/MariaDB metrics collected (placeholder)"
				else
					check_message="MySQL client not available - basic check only"
					check_status="warning"
				fi
				;;
			PostgreSQL)
				# PostgreSQL 성능 지표 수집
				if command -v psql >/dev/null 2>&1; then
					performance_json="{\"cpu_percent\":0,\"active_sessions\":0,\"database_size_mb\":0,\"transaction_count\":0}"
					check_message="PostgreSQL metrics collected (placeholder)"
				else
					check_message="PostgreSQL client not available - basic check only"
					check_status="warning"
				fi
				;;
			MSSQL)
				# MSSQL 성능 지표 수집 (pyodbc 사용)
				if ! python3 -c "import pyodbc" 2>/dev/null; then
					echo "[Gateway-MSSQL] ⚠️  pyodbc not available, skipping MSSQL check for $db_name" >&2
					check_status="warning"
					check_message="pyodbc not available - MSSQL check skipped"
				else
					# Python으로 MSSQL 성능 쿼리 실행
					# TODO: 실제 DB 연결 및 성능 쿼리
					performance_json="{\"cpu_percent\":0,\"active_sessions\":0,\"buffer_cache_hit_ratio\":0,\"wait_stats\":{}}"
					check_message="MSSQL metrics collected (placeholder)"
				fi
				;;
			*)
				check_message="DB type $db_type not supported yet"
				check_status="info"
				;;
		esac
		
		# Log result to KVS
		local kv_key="managed_db_check_${mdb_id}"
		local kv_value="{\"mdb_id\":${mdb_id},\"db_name\":\"${db_name}\",\"db_type\":\"${db_type}\",\"check_status\":\"${check_status}\",\"check_message\":\"${check_message}\",\"check_time\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"performance\":${performance_json}}"
		
		save_execution_log "managed_db_check" "$kv_value" "$kv_key"
		
		# Write to health results file (성능 지표 포함)
		echo "{\"mdb_id\":${mdb_id},\"status\":\"${check_status}\",\"message\":\"${check_message}\",\"response_time_ms\":0,\"performance_metrics\":${performance_json}}" >> "$health_results_file"
		
		echo "[${logdt}] [Gateway]   → Status: $check_status - $check_message" >> $LogFileName
	done
	
	# Build JSON array with awk
	local health_results=$(awk 'BEGIN{printf "["} NR>1{printf ","} {printf "%s", $0} END{printf "]"}' "$health_results_file")
	
	local logdt=$(date '+%Y%m%d%H%M%S')
	echo "[${logdt}] [Gateway] Health results JSON: $health_results" >> $LogFileName
	
	# Update tManagedDatabase.last_check_dt via API
	if [ "$health_results" != "[]" ] && [ "$health_results" != "[
]" ]; then
		echo "[Gateway] 📤 Updating tManagedDatabase.last_check_dt via API..." >&2
		local api_temp_file=$(mktemp)
		wget -O "$api_temp_file" --quiet \
			--post-data="text=ManagedDatabaseHealthUpdate jsondata&token=${sk}&jsondata=${health_results}" \
			"${apiaddrv2}?code=${apiaddrcode}" 2>/dev/null
		
		if [ -f "$api_temp_file" ]; then
			logdt=$(date '+%Y%m%d%H%M%S')
			echo "[${logdt}] [Gateway] API Response: $(cat "$api_temp_file")" >> $LogFileName
			echo "[${logdt}] [Gateway] Updated tManagedDatabase.last_check_dt for $db_count database(s)" >> $LogFileName
			rm -f "$api_temp_file"
		fi
	else
		echo "[Gateway] ⚠️  Skipping API update - health_results is empty" >&2
		logdt=$(date '+%Y%m%d%H%M%S')
		echo "[${logdt}] [Gateway] Skipped API update - health_results='$health_results'" >> $LogFileName
	fi
	
	# Clean up
	rm -f "$health_results_file"
	
	logdt=$(date '+%Y%m%d%H%M%S')
	echo "[${logdt}] [Gateway] Managed database check completed" >> $LogFileName
	
	return 0
}

# Export function for use in other scripts
export -f check_managed_databases
