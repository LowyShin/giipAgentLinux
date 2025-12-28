#!/bin/bash
# DB Check: MySQL/MariaDB
# Purpose: Perform health check for MySQL databases

perform_check_mysql() {
	local mdb_id="$1"
	local db_name="$2"
	local db_host="$3"
	local db_port="$4"
	local db_user="$5"
	local db_password="$6"
	local db_database="$7"
	
	local start_time=$(date +%s%3N)
	local check_status="unknown"
	local check_message="Not tested"
	local performance_json="{}"
	
	# Attempt MySQL connection test
	if command -v mysql >/dev/null 2>&1; then
		export MYSQL_PWD="$db_password"
		local timeout_seconds=10
		local mysql_result=$(timeout ${timeout_seconds}s mysql -h "$db_host" -P "$db_port" -u "$db_user" -D "$db_database" -e "SELECT 1 AS test;" 2>&1)
		local mysql_exit_code=$?
		
		if [ $mysql_exit_code -eq 0 ]; then
			check_status="healthy"
			check_message="Connection successful"
			logdt=$(date '+%Y%m%d%H%M%S')
			echo "[${logdt}] [Gateway]   ✅ MySQL connection OK: ${db_name} ($db_host:$db_port)" >> $LogFileName
			
			# Collect slow queries if available
			local slow_queries_json=$(timeout 5s mysql -h "$db_host" -P "$db_port" -u "$db_user" -D "$db_database" -e "SELECT query, exec_count, avg_time FROM mysql.slow_log LIMIT 10;" 2>/dev/null | tail -n +2 || echo "")
			if [ -n "$slow_queries_json" ]; then
				save_dpa_data "$db_name" "$slow_queries_json"
			fi
		elif [ $mysql_exit_code -eq 124 ]; then
			check_status="timeout"
			check_message="Connection timeout (${timeout_seconds}s)"
			logdt=$(date '+%Y%m%d%H%M%S')
			echo "[${logdt}] [Gateway]   ❌ MySQL timeout" >> $LogFileName
		else
			check_status="error"
			check_message=$(echo "$mysql_result" | grep -i "error" | head -1 | sed 's/password/****/gi' || echo "Connection failed")
			logdt=$(date '+%Y%m%d%H%M%S')
			echo "[${logdt}] [Gateway]   ❌ MySQL error: $check_message" >> $LogFileName
		fi
		unset MYSQL_PWD
	fi

	local end_time=$(date +%s%3N)
	local response_time=$((end_time - start_time))
	
	echo "{\"mdb_id\":${mdb_id},\"status\":\"${check_status}\",\"message\":\"${check_message}\",\"response_time_ms\":${response_time},\"performance_metrics\":${performance_json},\"db_name\":\"${db_name}\",\"db_type\":\"MySQL\"}"
}

export -f perform_check_mysql
