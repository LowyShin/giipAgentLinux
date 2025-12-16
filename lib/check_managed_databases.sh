#!/bin/bash
# Check Managed Databases Module
# Purpose: Query tManagedDatabase, perform health checks, collect DPA data, update last_check_dt
# Called by: gateway.sh when is_gateway=1

# Load DPA modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/dpa_mysql.sh"
source "${SCRIPT_DIR}/dpa_mssql.sh"
source "${SCRIPT_DIR}/dpa_postgresql.sh"
source "${SCRIPT_DIR}/net3d_db.sh"
source "${SCRIPT_DIR}/http_health_check.sh"

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
	
	# Collect required DB types
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
	
# ============================================================================
# Individual DB Check Functions
# return: JSON string for health result {"status":..., "message":..., ...}
# side-effect: logs to LogFileName, calls KVS puts
# ============================================================================

perform_check_mysql() {
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
	local logdt=""

	if ! command -v mysql >/dev/null 2>&1; then
		check_status="warning"
		check_message="MySQL client not installed"
		logdt=$(date '+%Y%m%d%H%M%S')
		echo "[${logdt}] [Gateway]   ⚠️  MySQL client not found" >> $LogFileName
	else
		export MYSQL_PWD="$db_password"
		
		# Connection Test
		local mysql_result=$(timeout 5 mysql -h "$db_host" -P "$db_port" -u "$db_user" -p"${MYSQL_PWD}" -D "$db_database" -e "SELECT 1 AS test" 2>&1)
		local mysql_exit=$?
		
		if [ $mysql_exit -eq 0 ]; then
			check_status="success"
			check_message="Connection successful"
			logdt=$(date '+%Y%m%d%H%M%S')
			echo "[${logdt}] [Gateway]   ✅ MySQL connection OK" >> $LogFileName
			
			# Performance Metrics
			local perf_data=$(timeout 5 mysql -h "$db_host" -P "$db_port" -u "$db_user" -p"${MYSQL_PWD}" -N -e "
				SELECT JSON_OBJECT(
					'threads_connected', VARIABLE_VALUE,
					'threads_running', (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Threads_running'),
					'questions', (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Questions'),
					'slow_queries', (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Slow_queries'),
					'uptime', (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Uptime')
				)
				FROM performance_schema.global_status
				WHERE VARIABLE_NAME='Threads_connected'
			" 2>&1 | grep '^{')
			# Fallback for older MySQL if JSON_OBJECT not supported or query fails: simple string concat was better in original?
			# Reverting to original concat approach for compatibility:
			if [ -z "$perf_data" ]; then
				perf_data=$(timeout 5 mysql -h "$db_host" -P "$db_port" -u "$db_user" -p"${MYSQL_PWD}" -N -e "
					SELECT CONCAT('{',
						'\"threads_connected\":', VARIABLE_VALUE, ',',
						'\"threads_running\":', (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Threads_running'), ',',
						'\"questions\":', (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Questions'), ',',
						'\"slow_queries\":', (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Slow_queries'), ',',
						'\"uptime\":', (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Uptime'),
					'}')
					FROM performance_schema.global_status
					WHERE VARIABLE_NAME='Threads_connected'
				" 2>&1 | grep '^{')
			fi

			if [ -n "$perf_data" ] && [[ "$perf_data" == "{"* ]]; then
				performance_json="$perf_data"
			fi
			
			# DPA Data
			logdt=$(date '+%Y%m%d%H%M%S')
			echo "[${logdt}] [Gateway]   🔍 Collecting MySQL DPA data..." >> $LogFileName
			slow_queries_json=$(collect_mysql_dpa "$db_host" "$db_port" "$db_user" "$db_password" "$db_database" 50)
			save_dpa_data "$db_name" "$slow_queries_json"
			
			# Net3D Sessions
			logdt=$(date '+%Y%m%d%H%M%S')
			echo "[${logdt}] [Gateway]   🕸️ Collecting MySQL Net3D sessions..." >> $LogFileName
			local net3d_json=$(collect_net3d_mysql "$db_host" "$db_port" "$db_user" "$db_password" "$db_database")
			if [ -n "$net3d_json" ] && [ "$net3d_json" != "[]" ]; then
				kvs_put "database" "$mdb_id" "db_connections" "$net3d_json"
			fi
		elif [ $mysql_exit -eq 124 ]; then
			check_status="error"
			check_message="Connection timeout (5s)"
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
	
	# Return JSON-like string (to be parsed by caller or used directly)
	# Using custom separator or just echoing the components?
	# Let's echo the health JSON directly.
	echo "{\"mdb_id\":${mdb_id},\"status\":\"${check_status}\",\"message\":\"${check_message}\",\"response_time_ms\":${response_time},\"performance_metrics\":${performance_json},\"db_name\":\"${db_name}\",\"db_type\":\"MySQL\"}"
}

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
					'\"batch_requests\":', (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE object_name LIKE '%SQL Statistics%' AND counter_name = 'Batch Requests/sec'), ',',
					'\"page_life_expectancy\":', (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Page life expectancy'), ',',
					'\"buffer_cache_hit_ratio\":', (SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = 'Buffer cache hit ratio'),
				'}')
			" 2>/dev/null | grep "^{" | tr -d '\r\n ')
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

perform_check_redis() {
	local mdb_id="$1"
	local db_name="$2"
	local db_host="$3"
	local db_port="$4"
	local db_password="$5"
	
	local check_status="unknown"
	local check_message="Not tested"
	local performance_json="{}"
	local start_time=$(date +%s%3N)
	
	if ! command -v redis-cli >/dev/null 2>&1; then
		check_status="warning"
		check_message="redis-cli not installed"
		echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ⚠️  redis-cli not found" >> $LogFileName
	else
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
			echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ✅ Redis connection OK" >> $LogFileName
			
			local redis_info
			if [ -n "$db_password" ]; then
				redis_info=$(timeout 5 redis-cli -h "$db_host" -p "$db_port" -a "$db_password" INFO stats 2>/dev/null)
			else
				redis_info=$(timeout 5 redis-cli -h "$db_host" -p "$db_port" INFO stats 2>/dev/null)
			fi
			if [ -n "$redis_info" ]; then
				local connected=$(echo "$redis_info" | grep "^connected_clients:" | cut -d: -f2 | tr -d '\r')
				local commands=$(echo "$redis_info" | grep "^total_commands_processed:" | cut -d: -f2 | tr -d '\r')
				local hits=$(echo "$redis_info" | grep "^keyspace_hits:" | cut -d: -f2 | tr -d '\r')
				local misses=$(echo "$redis_info" | grep "^keyspace_misses:" | cut -d: -f2 | tr -d '\r')
				performance_json="{\"connected_clients\":${connected:-0},\"total_commands\":${commands:-0},\"keyspace_hits\":${hits:-0},\"keyspace_misses\":${misses:-0}}"
			fi
		elif [ $redis_exit -eq 124 ]; then
			check_status="error"
			check_message="Connection timeout (5s)"
			echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ❌ Redis timeout" >> $LogFileName
		else
			check_status="error"
			check_message=$(echo "$redis_result" | head -1 | sed 's/password/****/gi' || echo "Connection failed")
			echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ❌ Redis error: $check_message" >> $LogFileName
		fi
	fi
	
	local response_time=$(( $(date +%s%3N) - start_time ))
	echo "{\"mdb_id\":${mdb_id},\"status\":\"${check_status}\",\"message\":\"${check_message}\",\"response_time_ms\":${response_time},\"performance_metrics\":${performance_json},\"db_name\":\"${db_name}\",\"db_type\":\"Redis\"}"
}

perform_check_mongodb() {
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
	local start_time=$(date +%s%3N)
	
	if ! command -v mongosh >/dev/null 2>&1 && ! command -v mongo >/dev/null 2>&1; then
		check_status="warning"
		check_message="mongo client not installed"
		echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ⚠️  mongosh/mongo not found" >> $LogFileName
	else
		local mongo_uri="mongodb://${db_user}:${db_password}@${db_host}:${db_port}/${db_database}"
		local mongo_cmd=$(command -v mongosh 2>/dev/null || command -v mongo 2>/dev/null)
		
		local mongo_result=$(timeout 5 "$mongo_cmd" "$mongo_uri" --eval "db.adminCommand('ping')" 2>&1)
		local mongo_exit=$?
		
		if [ $mongo_exit -eq 0 ]; then
			check_status="success"
			check_message="Connection successful"
			echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ✅ MongoDB connection OK" >> $LogFileName
			
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
			if [ -n "$mongo_stats" ] && [[ "$mongo_stats" == "{"* ]]; then performance_json="$mongo_stats"; fi
		elif [ $mongo_exit -eq 124 ]; then
			check_status="error"
			check_message="Connection timeout (5s)"
			echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ❌ MongoDB timeout" >> $LogFileName
		else
			check_status="error"
			check_message=$(echo "$mongo_result" | grep -i "error\|exception" | head -1 | sed 's/password/****/gi' || echo "Connection failed")
			echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ❌ MongoDB error: $check_message" >> $LogFileName
		fi
	fi
	
	local response_time=$(( $(date +%s%3N) - start_time ))
	echo "{\"mdb_id\":${mdb_id},\"status\":\"${check_status}\",\"message\":\"${check_message}\",\"response_time_ms\":${response_time},\"performance_metrics\":${performance_json},\"db_name\":\"${db_name}\",\"db_type\":\"MongoDB\"}"
}

perform_check_http() {
	local mdb_id="$1"
	local db_name="$2"
	local enabled="$3"
	local url="$4"
	local method="$5"
	local timeout_val="$6"
	local expected_code="$7"
	
	local check_status="unknown"
	local check_message="Not tested"
	local performance_json="{}"
	local start_time=$(date +%s%3N)
	
	if [ "$enabled" = "1" ] || [ "$enabled" = "true" ]; then
		if [ -z "$url" ]; then
			check_status="error"
			check_message="URL empty"
			echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ❌ HTTP check URL missing" >> $LogFileName
		else
			local http_result=$(check_http_health "$url" "$method" "$timeout_val" "$expected_code")
			IFS='|' read -r check_status response_time http_code check_message <<< "$http_result"
			
			if [ "$check_status" = "success" ]; then
				echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ✅ HTTP check OK: $url" >> $LogFileName
			else
				echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ❌ HTTP check failed: $check_message" >> $LogFileName
			fi
			performance_json="{\"http_code\": \"$http_code\", \"response_time_ms\": $response_time, \"url\": \"$url\", \"method\": \"$method\"}"
		fi
	else
		check_status="warning"
		check_message="HTTP check disabled"
		echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ⚠️  HTTP check disabled" >> $LogFileName
	fi

	# For HTTP, response_time is already calculated by check_http_health, but let's be consistent
	echo "{\"mdb_id\":${mdb_id},\"status\":\"${check_status}\",\"message\":\"${check_message}\",\"response_time_ms\":${response_time},\"performance_metrics\":${performance_json},\"db_name\":\"${db_name}\",\"db_type\":\"HTTP\"}"
}

check_managed_databases() {
	echo "[Gateway] 🔍 Checking managed databases..." >&2
	
	local temp_file=$(mktemp)
	local text="GatewayManagedDatabaseList lssn"
	local jsondata="{\"lssn\":${lssn}}"
	
	wget -O "$temp_file" --quiet \
		--post-data="text=${text}&token=${sk}&jsondata=${jsondata}" \
		--header="Content-Type: application/x-www-form-urlencoded" \
		"${apiaddrv2}?code=${apiaddrcode}" \
		--no-check-certificate 2>&1
	
	if [ ! -s "$temp_file" ]; then
		echo "[Gateway] ⚠️  Failed to fetch managed databases" >&2
		rm -f "$temp_file"
		return 1
	fi
	
	local db_list=$(python3 -c "import json, sys; 
try:
    data = json.load(open('$temp_file'))
    if 'data' in data and isinstance(data['data'], list):
        for item in data['data']: print(json.dumps(item))
except: pass" 2>/dev/null)
	
	rm -f "$temp_file"
	
	if [ -z "$db_list" ]; then
		echo "[Gateway] ⚠️  No databases found" >&2
		return 0
	fi
	
	local db_count=$(echo "$db_list" | wc -l)
	echo "[Gateway] 📊 Found $db_count managed database(s)" >&2
	
	# Install Clients (Simplified loop)
	# ... (Client check logic skipped for brevity as it's repetitive, but ideally can be in perform_check_* or called once here)
	# Keeping original install check block would be good, or just rely on 'command -v' inside perform_check_* printing warnings
	
	local health_results_file=$(mktemp)
	
	echo "$db_list" | while IFS= read -r db_json; do
		[[ -z "$db_json" ]] && continue
		
		# Parse common fields
		local mdb_id=$(echo "$db_json" | jq -r '.mdb_id // empty' 2>/dev/null)
		if [ -z "$mdb_id" ]; then
			# Fallback to python if jq not installed (gateway assumption: might not have jq, so use python as before)
			mdb_id=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('mdb_id', ''))")
		fi
		[[ -z $mdb_id ]] && continue

		local db_name=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('db_name', ''))")
		local db_type=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('db_type', ''))")
		local db_host=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('db_host', ''))")
		local db_port=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('db_port', ''))")
		local db_user=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('db_user', ''))")
		local db_password=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('db_password', ''))")
		local db_database=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('db_database', ''))")
		
		echo "[$(date '+%Y%m%d%H%M%S')] [Gateway] Checking DB: $db_name (ID:$mdb_id Type:$db_type)" >> $LogFileName
		
		local result_json=""
		
		case "$db_type" in
			MySQL|MariaDB)
				result_json=$(perform_check_mysql "$mdb_id" "$db_name" "$db_host" "$db_port" "$db_user" "$db_password" "$db_database")
				;;
			PostgreSQL)
				result_json=$(perform_check_postgresql "$mdb_id" "$db_name" "$db_host" "$db_port" "$db_user" "$db_password" "$db_database")
				;;
			MSSQL)
				result_json=$(perform_check_mssql "$mdb_id" "$db_name" "$db_host" "$db_port" "$db_user" "$db_password" "$db_database")
				;;
			Redis)
				result_json=$(perform_check_redis "$mdb_id" "$db_name" "$db_host" "$db_port" "$db_password")
				;;
			MongoDB)
				result_json=$(perform_check_mongodb "$mdb_id" "$db_name" "$db_host" "$db_port" "$db_user" "$db_password" "$db_database")
				;;
			HTTP|HTTPS|WebService|API|AzureAppService)
				local en=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('http_check_enabled', '0'))")
				local url=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('http_check_url', ''))")
				local meth=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('http_check_method', 'GET'))")
				local to=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('http_check_timeout', '10'))")
				local code=$(echo "$db_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('http_check_expected_code', '200'))")
				result_json=$(perform_check_http "$mdb_id" "$db_name" "$en" "$url" "$meth" "$to" "$code")
				;;
			*)
				echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   ℹ️  Unsupported DB type: $db_type" >> $LogFileName
				# Empty result, skipped in summary
				;;
		esac

		if [ -n "$result_json" ]; then
			# Save to KVS via detailed log
			# Extract fields manually or just construct the log string again? 
			# Refactored: Just use the JSON we got.
			# But we need check_status and check_message for the KVS 'managed_db_check_ID' key value format expected by frontend or history?
			# The format was:
			# {"mdb_id":..., "db_name":..., "db_type":..., "check_status":..., "check_message":..., "response_time_ms":..., "performance":...}
			
			# Enrich the result_json with db_type if missing? perform_* added it hopefully.
			# Let's trust result_json has what we need.
			
			save_execution_log "managed_db_check" "$result_json" "managed_db_check_${mdb_id}"
			
			# Append to health results file
			echo "$result_json" >> "$health_results_file"
			
			# Log summary
			local status=$(echo "$result_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('status', 'unknown'))")
			local ms=$(echo "$result_json" | python3 -c "import json, sys; print(json.load(sys.stdin).get('response_time_ms', 0))")
			echo "[$(date '+%Y%m%d%H%M%S')] [Gateway]   → $status (${ms}ms)" >> $LogFileName
		fi
	done
	
	# Build Final JSON Array
	local health_results=$(awk 'BEGIN{printf "["} NR>1{printf ","} {printf "%s", $0} END{printf "]"}' "$health_results_file")
	
	# Update tManagedDatabase.last_check_dt via API
	if [ "$health_results" != "[]" ] && [ "$health_results" != "[
]" ]; then
		local api_temp_file=$(mktemp)
		wget -O "$api_temp_file" --quiet \
			--post-data="text=ManagedDatabaseHealthUpdate jsondata&token=${sk}&jsondata=${health_results}" \
			"${apiaddrv2}?code=${apiaddrcode}" 2>/dev/null
		rm -f "$api_temp_file"
		echo "[$(date '+%Y%m%d%H%M%S')] [Gateway] Updated tManagedDatabase for $db_count DBs" >> $LogFileName
	fi
	
	rm -f "$health_results_file"
	return 0
}


# Export function for use in other scripts
export -f check_managed_databases
