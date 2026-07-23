#!/bin/bash
# DB Check: Redis
# Purpose: Perform health check for Redis databases

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

export -f perform_check_redis
