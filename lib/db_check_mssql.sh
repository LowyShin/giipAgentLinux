#!/bin/bash
# DB Check: MSSQL
# Purpose: Perform health check for MSSQL databases

perform_check_mssql() {
	local mdb_id="$1"
	local db_name="$2"
	local db_host="$3"
	local db_port="$4"
	local db_user="$5"
	local db_password="$6"
	local db_database="$7"
	
	local check_status="unknown"
	local check_message="Not tested"
	local performance_json="{}"
	local slow_queries_json="[]"
	local start_time=$(date +%s%3N)
	
	if ! command -v sqlcmd >/dev/null 2>&1; then
		check_status="warning"
		check_message="sqlcmd not installed"
		echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ⚠️  sqlcmd not found" >> $LogFileName
	else
		local mssql_result=$(timeout 5 sqlcmd -S "$db_host,$db_port" -U "$db_user" -P "$db_password" -d "$db_database" -Q "SELECT 1;" 2>&1)
		local mssql_exit=$?
		
		if [ $mssql_exit -eq 0 ]; then
			check_status="success"
			check_message="Connection successful"
			echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ✅ MSSQL connection OK" >> $LogFileName
			
			local mssql_stats=$(timeout 5 sqlcmd -S "$db_host,$db_port" -U "$db_user" -P "$db_password" -d "$db_database" -h -1 -Q "
				SET NOCOUNT ON;
				SELECT CONCAT('{',
					'\"user_connections\":', (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'User Connections'), ',',
					'\"total_batch_requests\":', (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE object_name LIKE '%SQL Statistics%' AND counter_name = 'Batch Requests/sec'), ',',
					'\"page_life_expectancy\":', (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Page life expectancy'), ',',
					'\"buffer_cache_hit_ratio\":', (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Buffer cache hit ratio'),
				'}')" 2>/dev/null | grep "^{" | tr -d '\r\n ')
			if [ -n "$mssql_stats" ] && [[ "$mssql_stats" == "{"* ]]; then performance_json="$mssql_stats"; fi
			
			echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   🔍 Collecting MSSQL DPA data..." >> $LogFileName
			slow_queries_json=$(collect_mssql_dpa "$db_host" "$db_port" "$db_user" "$db_password" "$db_database" 50000)
			save_dpa_data "$db_name" "$slow_queries_json"
			
			echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   🕸️ Collecting MSSQL Net3D sessions..." >> $LogFileName
			local net3d_json=$(collect_net3d_mssql "$db_host" "$db_port" "$db_user" "$db_password" "$db_database")
			[[ -n "$net3d_json" && "$net3d_json" != "[]" ]] && kvs_put "database" "$mdb_id" "db_connections" "$net3d_json"
			
		elif [ $mssql_exit -eq 124 ]; then
			check_status="error"
			check_message="Connection timeout (5s)"
			echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ❌ MSSQL timeout" >> $LogFileName
		else
			check_status="error"
			check_message=$(echo "$mssql_result" | grep -i "error\|sqlstate" | head -1 | sed 's/password/****/gi' || echo "Connection failed")
			echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ❌ MSSQL error: $check_message" >> $LogFileName
		fi
	fi
	
	local response_time=$(( $(date +%s%3N) - start_time ))
	echo "{\"mdb_id\":${mdb_id},\"status\":\"${check_status}\",\"message\":\"${check_message}\",\"response_time_ms\":${response_time},\"performance_metrics\":${performance_json},\"db_name\":\"${db_name}\",\"db_type\":\"MSSQL\"}"
}

export -f perform_check_mssql
