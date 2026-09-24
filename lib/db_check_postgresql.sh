#!/bin/bash
# DB Check: PostgreSQL
# Purpose: Perform health check for PostgreSQL databases

perform_check_postgresql() {
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
	
	if ! command -v psql >/dev/null 2>&1; then
		check_status="warning"
		check_message="psql client not installed"
		echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ⚠️  psql not found" >> $LogFileName
	else
		local psql_result=$(PGPASSWORD="$db_password" timeout 5 psql -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_database" -c "SELECT 1;" 2>&1)
		local psql_exit=$?
		
		if [ $psql_exit -eq 0 ]; then
			check_status="success"
			check_message="Connection successful"
			echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ✅ PostgreSQL connection OK" >> $LogFileName
			
			local perf_data=$(PGPASSWORD="$db_password" timeout 5 psql -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_database" -t -A -c "
				SELECT json_build_object(
					'connections', (SELECT count(*) FROM pg_stat_activity),
					'active_connections', (SELECT count(*) FROM pg_stat_activity WHERE state = 'active'),
					'idle_connections', (SELECT count(*) FROM pg_stat_activity WHERE state = 'idle'),
					'database_size_mb', (SELECT pg_database_size(current_database()) / 1024 / 1024),
					'uptime_seconds', (SELECT EXTRACT(EPOCH FROM (now() - pg_postmaster_start_time())))
				)::text;
			" 2>/dev/null)
			if [ -n "$perf_data" ] && [[ "$perf_data" == "{"* ]]; then performance_json="$perf_data"; fi
			
			echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   🔍 Collecting PostgreSQL DPA data..." >> $LogFileName
			slow_queries_json=$(collect_postgresql_dpa "$db_host" "$db_port" "$db_user" "$db_password" "$db_database" 50)
			save_dpa_data "$db_name" "$slow_queries_json"
			
			echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   🕸️ Collecting PostgreSQL Net3D sessions..." >> $LogFileName
			local net3d_json=$(collect_net3d_postgresql "$db_host" "$db_port" "$db_user" "$db_password" "$db_database")
			[[ -n "$net3d_json" && "$net3d_json" != "[]" ]] && kvs_put "database" "$mdb_id" "db_connections" "$net3d_json"
			
		elif [ $psql_exit -eq 124 ]; then
			check_status="error"
			check_message="Connection timeout (5s)"
			echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ❌ PostgreSQL timeout" >> $LogFileName
		else
			check_status="error"
			check_message=$(echo "$psql_result" | grep -i "error\|fatal" | head -1 | sed 's/password/****/gi' || echo "Connection failed")
			echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ❌ PostgreSQL error: $check_message" >> $LogFileName
		fi
	fi
	
	local response_time=$(( $(date +%s%3N) - start_time ))
	echo "{\"mdb_id\":${mdb_id},\"status\":\"${check_status}\",\"message\":\"${check_message}\",\"response_time_ms\":${response_time},\"performance_metrics\":${performance_json},\"db_name\":\"${db_name}\",\"db_type\":\"PostgreSQL\"}"
}

export -f perform_check_postgresql
