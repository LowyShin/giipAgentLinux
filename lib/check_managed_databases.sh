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
	
	# 1. 먼저 필요한 DB 타입들을 수집
	local db_types=$(echo "$db_list" | python3 -c "
import json, sys
db_types = set()
for line in sys.stdin:
    if line.strip():
        try:
            data = json.loads(line)
            db_type = data.get('db_type', '')
            if db_type:
                db_types.add(db_type)
        except:
            pass
print(' '.join(sorted(db_types)))
")
	
	echo "[Gateway] 📋 Required DB types: $db_types" >&2
	
	# 2. 필요한 DB 클라이언트만 체크 및 설치
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
					echo "[Gateway] Installing PostgreSQL client..." >&2
					check_psql_client
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
	
	# Build health_results
	local health_results_file=$(mktemp)
	
	echo "$db_list" | while IFS= read -r db_json; do
		[[ -z "$db_json" ]] && continue
		
		# Parse JSON fields using Python
		local mdb_id=$(echo "$db_json" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('mdb_id', ''))")
		local db_name=$(echo "$db_json" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('db_name', ''))")
		local db_type=$(echo "$db_json" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('db_type', ''))")
		local db_host=$(echo "$db_json" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('db_host', ''))")
		local db_port=$(echo "$db_json" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('db_port', ''))")
		local db_user=$(echo "$db_json" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('db_user', ''))")
		local db_password=$(echo "$db_json" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('db_password', ''))")
		local db_database=$(echo "$db_json" | python3 -c "import json, sys; data=json.load(sys.stdin); print(data.get('db_database', ''))")
		
		[[ -z $mdb_id ]] && continue
		[[ -z $db_name ]] && continue
		
		local logdt=$(date '+%Y%m%d%H%M%S')
		echo "[${logdt}] [Gateway] Checking DB: $db_name (mdb_id:$mdb_id, type:$db_type, host:$db_host:$db_port)" >> $LogFileName
		
		# Test connection based on DB type
		local check_status="unknown"
		local check_message="Not tested"
		local performance_json="{}"
		local start_time=$(date +%s%3N)  # milliseconds
		
		case "$db_type" in
			MySQL|MariaDB)
				# MySQL 연결 테스트
				if ! command -v mysql >/dev/null 2>&1; then
					check_status="warning"
					check_message="MySQL client not installed on gateway server"
					logdt=$(date '+%Y%m%d%H%M%S')
					echo "[${logdt}] [Gateway]   ⚠️  MySQL client not found" >> $LogFileName
				else
					# 실제 연결 테스트 (timeout 5초)
					local mysql_result=$(timeout 5 mysql -h "$db_host" -P "$db_port" -u "$db_user" -p"$db_password" -D "$db_database" -e "SELECT 1 AS test" 2>&1)
					local mysql_exit=$?
					
					if [ $mysql_exit -eq 0 ]; then
						check_status="success"
						check_message="Connection successful"
						logdt=$(date '+%Y%m%d%H%M%S')
						echo "[${logdt}] [Gateway]   ✅ MySQL connection OK" >> $LogFileName
						
						# 성능 메트릭 수집
						local perf_data=$(timeout 5 mysql -h "$db_host" -P "$db_port" -u "$db_user" -p"$db_password" -D "$db_database" -N -e "
							SELECT 
								CONCAT('{',
									'\"threads_connected\":', VARIABLE_VALUE, ',',
									'\"threads_running\":', (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='Threads_running'), ',',
									'\"questions\":', (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='Questions'), ',',
									'\"slow_queries\":', (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='Slow_queries'), ',',
									'\"uptime\":', (SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME='Uptime'),
								'}')
							FROM information_schema.GLOBAL_STATUS 
							WHERE VARIABLE_NAME='Threads_connected'
						" 2>/dev/null)
						
						if [ -n "$perf_data" ] && [[ "$perf_data" == "{"* ]]; then
							performance_json="$perf_data"
						fi
					elif [ $mysql_exit -eq 124 ]; then
						check_status="error"
						check_message="Connection timeout (5s)"
						logdt=$(date '+%Y%m%d%H%M%S')
						echo "[${logdt}] [Gateway]   ❌ MySQL timeout" >> $LogFileName
					else
						check_status="error"
						# 에러 메시지에서 민감 정보 제거
						check_message=$(echo "$mysql_result" | grep -i "error" | head -1 | sed 's/password/****/gi' || echo "Connection failed")
						logdt=$(date '+%Y%m%d%H%M%S')
						echo "[${logdt}] [Gateway]   ❌ MySQL error: $check_message" >> $LogFileName
					fi
				fi
				;;
			PostgreSQL)
				# PostgreSQL 연결 테스트
				if ! command -v psql >/dev/null 2>&1; then
					check_status="warning"
					check_message="PostgreSQL client (psql) not installed on gateway server"
					logdt=$(date '+%Y%m%d%H%M%S')
					echo "[${logdt}] [Gateway]   ⚠️  psql not found" >> $LogFileName
				else
					# PGPASSWORD 환경변수 사용 (보안상 안전)
					local psql_result=$(PGPASSWORD="$db_password" timeout 5 psql -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_database" -c "SELECT 1;" 2>&1)
					local psql_exit=$?
					
					if [ $psql_exit -eq 0 ]; then
						check_status="success"
						check_message="Connection successful"
						logdt=$(date '+%Y%m%d%H%M%S')
						echo "[${logdt}] [Gateway]   ✅ PostgreSQL connection OK" >> $LogFileName
						
						# 성능 메트릭 수집
						local perf_data=$(PGPASSWORD="$db_password" timeout 5 psql -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_database" -t -A -c "
							SELECT json_build_object(
								'connections', (SELECT count(*) FROM pg_stat_activity),
								'active_connections', (SELECT count(*) FROM pg_stat_activity WHERE state = 'active'),
								'idle_connections', (SELECT count(*) FROM pg_stat_activity WHERE state = 'idle'),
								'database_size_mb', (SELECT pg_database_size(current_database()) / 1024 / 1024),
								'uptime_seconds', (SELECT EXTRACT(EPOCH FROM (now() - pg_postmaster_start_time())))
							)::text;
						" 2>/dev/null)
						
						if [ -n "$perf_data" ] && [[ "$perf_data" == "{"* ]]; then
							performance_json="$perf_data"
						fi
					elif [ $psql_exit -eq 124 ]; then
						check_status="error"
						check_message="Connection timeout (5s)"
						logdt=$(date '+%Y%m%d%H%M%S')
						echo "[${logdt}] [Gateway]   ❌ PostgreSQL timeout" >> $LogFileName
					else
						check_status="error"
						check_message=$(echo "$psql_result" | grep -i "error\|fatal" | head -1 | sed 's/password/****/gi' || echo "Connection failed")
						logdt=$(date '+%Y%m%d%H%M%S')
						echo "[${logdt}] [Gateway]   ❌ PostgreSQL error: $check_message" >> $LogFileName
					fi
				fi
				;;
			MSSQL)
				# MSSQL 연결 테스트 (sqlcmd 사용)
				if ! command -v sqlcmd >/dev/null 2>&1; then
					check_status="warning"
					check_message="MSSQL client (sqlcmd) not installed on gateway server"
					logdt=$(date '+%Y%m%d%H%M%S')
					echo "[${logdt}] [Gateway]   ⚠️  sqlcmd not found" >> $LogFileName
				else
					# sqlcmd 연결 테스트
					local mssql_result=$(timeout 5 sqlcmd -S "$db_host,$db_port" -U "$db_user" -P "$db_password" -d "$db_database" -Q "SELECT 1;" 2>&1)
					local mssql_exit=$?
					
					if [ $mssql_exit -eq 0 ]; then
						check_status="success"
						check_message="Connection successful"
						logdt=$(date '+%Y%m%d%H%M%S')
						echo "[${logdt}] [Gateway]   ✅ MSSQL connection OK" >> $LogFileName
						
						# 성능 메트릭 수집
						local mssql_stats=$(timeout 5 sqlcmd -S "$db_host,$db_port" -U "$db_user" -P "$db_password" -d "$db_database" -h -1 -Q "
							SET NOCOUNT ON;
							SELECT 
								CONCAT('{',
									'\"user_connections\":', (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'User Connections'), ',',
									'\"batch_requests\":', (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE object_name LIKE '%SQL Statistics%' AND counter_name = 'Batch Requests/sec'), ',',
									'\"page_life_expectancy\":', (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Page life expectancy'), ',',
									'\"buffer_cache_hit_ratio\":', (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Buffer cache hit ratio'),
								'}')
						" 2>/dev/null | grep "^{" | tr -d '\r\n ')
						
						if [ -n "$mssql_stats" ] && [[ "$mssql_stats" == "{"* ]]; then
							performance_json="$mssql_stats"
						fi
					elif [ $mssql_exit -eq 124 ]; then
						check_status="error"
						check_message="Connection timeout (5s)"
						logdt=$(date '+%Y%m%d%H%M%S')
						echo "[${logdt}] [Gateway]   ❌ MSSQL timeout" >> $LogFileName
					else
						check_status="error"
						check_message=$(echo "$mssql_result" | grep -i "error\|sqlstate" | head -1 | sed 's/password/****/gi' || echo "Connection failed")
						logdt=$(date '+%Y%m%d%H%M%S')
						echo "[${logdt}] [Gateway]   ❌ MSSQL error: $check_message" >> $LogFileName
					fi
				fi
				;;
			Redis)
				# Redis 연결 테스트
				if ! command -v redis-cli >/dev/null 2>&1; then
					check_status="warning"
					check_message="Redis client (redis-cli) not installed on gateway server"
					logdt=$(date '+%Y%m%d%H%M%S')
					echo "[${logdt}] [Gateway]   ⚠️  redis-cli not found" >> $LogFileName
				else
					# Redis PING 테스트
					local redis_result
					if [ -n "$db_password" ]; then
						redis_result=$(timeout 5 redis-cli -h "$db_host" -p "$db_port" -a "$db_password" PING 2>&1)
					else
						redis_result=$(timeout 5 redis-cli -h "$db_host" -p "$db_port" PING 2>&1)
					fi
					local redis_exit=$?
					
					if [ $redis_exit -eq 0 ] && [[ "$redis_result" == "PONG" ]]; then
						check_status="success"
						check_message="Connection successful (PONG)"
						logdt=$(date '+%Y%m%d%H%M%S')
						echo "[${logdt}] [Gateway]   ✅ Redis connection OK" >> $LogFileName
						
						# 성능 메트릭 수집 (INFO stats)
						local redis_info
						if [ -n "$db_password" ]; then
							redis_info=$(timeout 5 redis-cli -h "$db_host" -p "$db_port" -a "$db_password" INFO stats 2>/dev/null)
						else
							redis_info=$(timeout 5 redis-cli -h "$db_host" -p "$db_port" INFO stats 2>/dev/null)
						fi
						
						if [ -n "$redis_info" ]; then
							local connected_clients=$(echo "$redis_info" | grep "^connected_clients:" | cut -d: -f2 | tr -d '\r')
							local total_commands=$(echo "$redis_info" | grep "^total_commands_processed:" | cut -d: -f2 | tr -d '\r')
							local keyspace_hits=$(echo "$redis_info" | grep "^keyspace_hits:" | cut -d: -f2 | tr -d '\r')
							local keyspace_misses=$(echo "$redis_info" | grep "^keyspace_misses:" | cut -d: -f2 | tr -d '\r')
							
							performance_json="{\"connected_clients\":${connected_clients:-0},\"total_commands\":${total_commands:-0},\"keyspace_hits\":${keyspace_hits:-0},\"keyspace_misses\":${keyspace_misses:-0}}"
						fi
					elif [ $redis_exit -eq 124 ]; then
						check_status="error"
						check_message="Connection timeout (5s)"
						logdt=$(date '+%Y%m%d%H%M%S')
						echo "[${logdt}] [Gateway]   ❌ Redis timeout" >> $LogFileName
					else
						check_status="error"
						check_message=$(echo "$redis_result" | head -1 | sed 's/password/****/gi' || echo "Connection failed")
						logdt=$(date '+%Y%m%d%H%M%S')
						echo "[${logdt}] [Gateway]   ❌ Redis error: $check_message" >> $LogFileName
					fi
				fi
				;;
			MongoDB)
				# MongoDB 연결 테스트
				if ! command -v mongosh >/dev/null 2>&1 && ! command -v mongo >/dev/null 2>&1; then
					check_status="warning"
					check_message="MongoDB client (mongosh/mongo) not installed on gateway server"
					logdt=$(date '+%Y%m%d%H%M%S')
					echo "[${logdt}] [Gateway]   ⚠️  mongosh/mongo not found" >> $LogFileName
				else
					# MongoDB 연결 문자열 생성
					local mongo_uri="mongodb://${db_user}:${db_password}@${db_host}:${db_port}/${db_database}"
					local mongo_cmd=$(command -v mongosh 2>/dev/null || command -v mongo 2>/dev/null)
					
					local mongo_result=$(timeout 5 "$mongo_cmd" "$mongo_uri" --eval "db.adminCommand('ping')" 2>&1)
					local mongo_exit=$?
					
					if [ $mongo_exit -eq 0 ]; then
						check_status="success"
						check_message="Connection successful"
						logdt=$(date '+%Y%m%d%H%M%S')
						echo "[${logdt}] [Gateway]   ✅ MongoDB connection OK" >> $LogFileName
						
						# 성능 메트릭 수집
						local mongo_stats=$(timeout 5 "$mongo_cmd" "$mongo_uri" --quiet --eval "
							var stats = db.serverStatus();
							print(JSON.stringify({
								connections: stats.connections.current,
								active_connections: stats.connections.active || 0,
								network_bytes_in: stats.network.bytesIn,
								network_bytes_out: stats.network.bytesOut,
								opcounters_query: stats.opcounters.query,
								opcounters_insert: stats.opcounters.insert,
								opcounters_update: stats.opcounters.update,
								opcounters_delete: stats.opcounters.delete,
								uptime: stats.uptime
							}));
						" 2>/dev/null)
						
						if [ -n "$mongo_stats" ] && [[ "$mongo_stats" == "{"* ]]; then
							performance_json="$mongo_stats"
						fi
					elif [ $mongo_exit -eq 124 ]; then
						check_status="error"
						check_message="Connection timeout (5s)"
						logdt=$(date '+%Y%m%d%H%M%S')
						echo "[${logdt}] [Gateway]   ❌ MongoDB timeout" >> $LogFileName
					else
						check_status="error"
						check_message=$(echo "$mongo_result" | grep -i "error\|exception" | head -1 | sed 's/password/****/gi' || echo "Connection failed")
						logdt=$(date '+%Y%m%d%H%M%S')
						echo "[${logdt}] [Gateway]   ❌ MongoDB error: $check_message" >> $LogFileName
					fi
				fi
				;;
			*)
				check_status="info"
				check_message="DB type '$db_type' not supported yet"
				logdt=$(date '+%Y%m%d%H%M%S')
				echo "[${logdt}] [Gateway]   ℹ️  Unsupported DB type: $db_type" >> $LogFileName
				;;
		esac
		
		# Calculate response time
		local end_time=$(date +%s%3N)
		local response_time=$((end_time - start_time))
		# Calculate response time
		local end_time=$(date +%s%3N)
		local response_time=$((end_time - start_time))
		
		# Log result to KVS
		local kv_key="managed_db_check_${mdb_id}"
		local kv_value="{\"mdb_id\":${mdb_id},\"db_name\":\"${db_name}\",\"db_type\":\"${db_type}\",\"check_status\":\"${check_status}\",\"check_message\":\"${check_message}\",\"check_time\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"response_time_ms\":${response_time},\"performance\":${performance_json}}"
		
		save_execution_log "managed_db_check" "$kv_value" "$kv_key"
		
		# Write to health results file (성능 지표 포함)
		echo "{\"mdb_id\":${mdb_id},\"status\":\"${check_status}\",\"message\":\"${check_message}\",\"response_time_ms\":${response_time},\"performance_metrics\":${performance_json}}" >> "$health_results_file"
		
		logdt=$(date '+%Y%m%d%H%M%S')
		echo "[${logdt}] [Gateway]   → Status: $check_status - $check_message (${response_time}ms)" >> $LogFileName
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
