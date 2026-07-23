#!/bin/bash
# DB Check: MongoDB
# Purpose: Perform health check for MongoDB databases

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

export -f perform_check_mongodb
